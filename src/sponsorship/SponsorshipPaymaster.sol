// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {SignatureCheckerLib} from "solady/utils/SignatureCheckerLib.sol";
import {ECDSA as ECDSA_solady} from "solady/utils/ECDSA.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {BasePaymaster} from "../base/BasePaymaster.sol";
import {UserOperationLib, PackedUserOperation} from "@account-abstraction/contracts/core/UserOperationLib.sol";
import {_packValidationData} from "@account-abstraction/contracts/core/Helpers.sol";
import {IEntryPoint} from "@account-abstraction/contracts/interfaces/IEntryPoint.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ISponsorshipPaymaster} from "../interfaces/ISponsorshipPaymaster.sol";
import {MultiSigners} from "../lib/MultiSigners.sol";

/**
 * @title SponsorshipPaymaster
 * @notice Paymaster contract that enables transaction sponsorship for account abstraction
 * @dev Manages funds from sponsors to pay for user operations
 */
contract SponsorshipPaymaster is BasePaymaster, MultiSigners, ReentrancyGuardTransient, ISponsorshipPaymaster {
    using UserOperationLib for PackedUserOperation;
    using SignatureCheckerLib for address;
    using ECDSA_solady for bytes32;

    // Denominator to prevent precision errors when applying fee markup
    uint256 private constant FEE_MARKUP_DENOMINATOR = 1e6;

    // Offset in PaymasterAndData to get to SPONSOR_ACCOUNT_OFFSET
    // paymasterData part of userOp.paymasterAndData starts here
    // userOp.paymasterAndData is paymaster address(20 bytes) + paymaster validation gas limit(16 bytes) + paymaster post-op gas limit(16 bytes) + paymasterData
    // where + means concat
    uint256 private constant SPONSOR_ACCOUNT_OFFSET = PAYMASTER_DATA_OFFSET;

    // Limit for unaccounted gas cost
    uint256 private constant UNACCOUNTED_GAS_LIMIT = 150_000;

    // Penalty percentage for exceeding the execution gas limit
    uint256 private constant PENALTY_PERCENT = 10;

    // paymasterData is sponsorAccount(20 bytes) + validUntil(6 bytes) + validAfter(6 bytes) + feeMarkup(4 bytes) + signature

    uint256 private constant SPONSOR_ACCOUNT_LENGTH = 20;
    uint256 private constant TIMESTAMP_DATA_LENGTH = 6;
    uint256 private constant FEE_MARKUP_LENGTH = 4;
    uint256 private constant VALID_UNTIL_TIMESTAMP_OFFSET = SPONSOR_ACCOUNT_OFFSET + SPONSOR_ACCOUNT_LENGTH;
    uint256 private constant VALID_AFTER_TIMESTAMP_OFFSET = VALID_UNTIL_TIMESTAMP_OFFSET + TIMESTAMP_DATA_LENGTH;
    uint256 private constant FEE_MARKUP_OFFSET = VALID_AFTER_TIMESTAMP_OFFSET + TIMESTAMP_DATA_LENGTH;
    uint256 private constant SIGNATURE_OFFSET =
        PAYMASTER_DATA_OFFSET + SPONSOR_ACCOUNT_LENGTH + (2 * TIMESTAMP_DATA_LENGTH) + FEE_MARKUP_LENGTH;

    address public feeCollector;
    uint256 public minDeposit;
    mapping(address => uint256) public sponsorBalances;

    //Keep withdrawal related info in one struct
    mapping(address sponsorAccount => WithdrawalRequest request) internal withdrawalRequests;

    uint256 public sponsorWithdrawalDelay;
    uint256 public unaccountedGas;

    /**
     * @notice Initializes the SponsorshipPaymaster contract
     * @param _owner The owner of the paymaster
     * @param _entryPoint The ERC-4337 EntryPoint contract address
     * @param _signers Array of authorized signers for paymaster validation
     * @param _feeCollector Address that collects the extra fee (premium)
     * @param _minDeposit Minimum deposit required for a user to be sponsored
     * @param _withdrawalDelay Delay in seconds before a user can withdraw funds
     * @param _unaccountedGas Extra gas used for post-operation adjustments
     */
    constructor(
        address _owner,
        address _entryPoint,
        address[] memory _signers,
        address _feeCollector,
        uint256 _minDeposit,
        uint256 _withdrawalDelay,
        uint256 _unaccountedGas
    ) BasePaymaster(_owner, IEntryPoint(_entryPoint)) MultiSigners(_signers) {
        _checkConstructorArgs(_feeCollector, _unaccountedGas);
        feeCollector = _feeCollector;
        minDeposit = _minDeposit;
        sponsorWithdrawalDelay = _withdrawalDelay;
        unaccountedGas = _unaccountedGas;
        emit UnaccountedGasChanged(0, _unaccountedGas);
    }

    /**
     * @notice Receives ETH payments
     * @dev Silent receive function (no events to save gas)
     */
    receive() external payable {
        // do nothing
        // unnecessary to emit that consume gas
    }

    /**
     * @notice Allows users to deposit ETH to be used for sponsoring gas fees
     * @param _sponsorAccount The address of the user making the deposit
     */
    function depositFor(address _sponsorAccount) external payable nonReentrant {
        // check zero address for deposit
        if (_sponsorAccount == address(0)) revert InvalidDepositAddress();
        // cache msg.value in a variable. https://www.evm.codes/ is a good resource for gas costs
        uint256 depositAmount = msg.value;

        if (depositAmount == 0) revert LowDeposit(depositAmount, minDeposit);

        if (sponsorBalances[_sponsorAccount] == 0 && depositAmount < minDeposit) {
            revert LowDeposit(depositAmount, minDeposit);
        }

        sponsorBalances[_sponsorAccount] += depositAmount;
        emit DepositAdded(_sponsorAccount, depositAmount);

        entryPoint.depositTo{value: depositAmount}(address(this));
    }

    /**
     * @notice Sets the minimum deposit required for gas sponsorship
     * @param _newMinDeposit The new minimum deposit value
     */
    function setMinDeposit(uint256 _newMinDeposit) external onlyOwner {
        if (_newMinDeposit == 0) {
            revert MinDepositCanNotBeZero();
        }
        emit MinDepositChanged(minDeposit, _newMinDeposit);
        minDeposit = _newMinDeposit;
    }

    /**
     * @notice Allows users to request withdrawals from their paymaster balance
     * @param _withdrawAddress The address to send the withdrawal to
     * @param _amount The amount of ETH the user wishes to withdraw
     */
    function requestWithdrawal(address _withdrawAddress, uint256 _amount) external {
        uint256 currentBalance = sponsorBalances[msg.sender];
        // check zero address for withdrawal
        if (_withdrawAddress == address(0)) {
            revert InvalidWithdrawalAddress();
        }
        // check for non-zero amount
        if (_amount == 0) {
            revert CanNotWithdrawZeroAmount();
        }
        if (currentBalance < _amount) {
            revert InsufficientFunds(msg.sender, currentBalance, _amount);
        }
        uint256 balanceAfterWithdrawal = currentBalance - _amount;
        /// notice: have to display this on front end.
        /// applies to fee collector as well.
        /// toggle to withdraw full instead of manually entering amount.
        if (balanceAfterWithdrawal != 0 && balanceAfterWithdrawal < minDeposit) {
            revert RequiredToWithdrawFullBalanceOrKeepMinDeposit(currentBalance, _amount, minDeposit);
        }
        withdrawalRequests[msg.sender] =
            WithdrawalRequest({amount: _amount, to: _withdrawAddress, requestSubmittedTimestamp: block.timestamp});
        emit WithdrawalRequested(msg.sender, _withdrawAddress, _amount);
    }

    /**
     * @notice Sets a new withdrawal delay
     * @param _newWithdrawalDelay The new withdrawal delay in seconds
     */
    function setWithdrawalDelay(uint256 _newWithdrawalDelay) external onlyOwner {
        if (_newWithdrawalDelay > 86400) {
            // 1 day
            revert WithdrawalDelayTooLong();
        }
        uint256 oldWithdrawalDelay = sponsorWithdrawalDelay;
        sponsorWithdrawalDelay = _newWithdrawalDelay;
        emit WithdrawalDelayChanged(oldWithdrawalDelay, _newWithdrawalDelay);
    }

    /**
     * @notice Executes the withdrawal request for a given funding account
     * @param _sponsorAccount The address of the user withdrawing funds
     */
    function executeWithdrawal(address _sponsorAccount) external nonReentrant {
        WithdrawalRequest memory req = withdrawalRequests[_sponsorAccount];
        if (req.requestSubmittedTimestamp == 0) revert NoWithdrawalRequestSubmitted(_sponsorAccount);

        // Note: We could add trusted sponsor accounts with zero withdrawal delay
        uint256 clearanceTimestamp = req.requestSubmittedTimestamp + sponsorWithdrawalDelay;

        if (block.timestamp < clearanceTimestamp) revert WithdrawalTooSoon(_sponsorAccount, clearanceTimestamp);

        uint256 currentBalance = sponsorBalances[_sponsorAccount];

        req.amount = req.amount > currentBalance ? currentBalance : req.amount;
        if (req.amount == 0) revert CanNotWithdrawZeroAmount();
        sponsorBalances[_sponsorAccount] = currentBalance - req.amount;
        delete withdrawalRequests[_sponsorAccount];
        entryPoint.withdrawTo(payable(req.to), req.amount);
        emit WithdrawalExecuted(_sponsorAccount, req.to, req.amount);
    }

    /**
     * @dev Cancel a withdrawal request
     */
    function cancelWithdrawal() external {
        delete withdrawalRequests[msg.sender];
        emit WithdrawalRequestCancelledFor(msg.sender);
    }

    /**
     * @notice Sets a new fee collector address
     * @param _newFeeCollector The new fee collector address
     */
    function setFeeCollector(address _newFeeCollector) external payable onlyOwner {
        if (_newFeeCollector == address(0)) revert FeeCollectorCanNotBeZero();
        address oldFeeCollector = feeCollector;
        feeCollector = _newFeeCollector;
        emit FeeCollectorChanged(oldFeeCollector, _newFeeCollector);
    }

    /**
     * @notice Adds a new signer to the list of authorized signers
     * @param _signer The address of the signer to add
     */
    function addSigner(address _signer) external payable onlyOwner {
        _addSigner(_signer);
    }

    /**
     * @notice Removes a signer from the list of authorized signers
     * @param _signer The address of the signer to remove
     */
    function removeSigner(address _signer) external payable onlyOwner {
        _removeSigner(_signer);
    }

    /**
     * @notice Withdraws ETH from the paymaster
     * @param _recipient The recipient address
     * @param _amount The amount of ETH to withdraw
     */
    function withdrawEth(address payable _recipient, uint256 _amount) external payable onlyOwner nonReentrant {
        if (_recipient == address(0)) {
            revert InvalidWithdrawalAddress();
        }
        (bool success,) = _recipient.call{value: _amount}("");
        if (!success) {
            revert WithdrawalFailed();
        }
        emit EthWithdrawn(_recipient, _amount);
    }

    /**
     * @notice Withdraws ERC20 tokens from the paymaster
     * @param _token The token contract to withdraw from
     * @param _target The recipient address
     * @param _amount The amount to withdraw
     */
    function withdrawERC20(IERC20 _token, address _target, uint256 _amount) external onlyOwner nonReentrant {
        _withdrawERC20(_token, _target, _amount);
    }

    /**
     * @notice Sets the unaccounted gas value used for post-operation calculations
     * @param _value The new unaccounted gas value
     */
    function setUnaccountedGas(uint256 _value) external payable onlyOwner {
        if (_value > UNACCOUNTED_GAS_LIMIT) {
            revert UnaccountedGasTooHigh();
        }
        uint256 oldUnaccountedGas = unaccountedGas;
        unaccountedGas = _value;
        emit UnaccountedGasChanged(oldUnaccountedGas, _value);
    }

    /**
     * @notice Overrides default deposit function to prevent direct deposits
     */
    function deposit() external payable virtual override {
        revert UseDepositForInstead();
    }

    /**
     * @notice Overrides default withdraw function to enforce request-based withdrawal
     */
    function withdrawTo(address payable _withdrawAddress, uint256 _amount) external virtual override {
        (_withdrawAddress, _amount); // Unused parameters
        revert SubmitRequestInstead();
    }

    /**
     * @notice Gets the current balance of a sponsor account
     * @param _sponsorAccount The sponsor account address to check
     * @return balance The current balance of the sponsor account
     */
    function getBalance(address _sponsorAccount) external view returns (uint256 balance) {
        balance = sponsorBalances[_sponsorAccount];
    }

    /**
     * @notice Generates a hash of the given UserOperation to be signed by the paymaster
     * @param _userOp The UserOperation structure
     * @param _sponsorAccount The sponsor account address
     * @param _validUntil The timestamp until which the operation is valid
     * @param _validAfter The timestamp after which the operation is valid
     * @param _feeMarkup The fee markup for the operation
     * @return The hashed UserOperation data
     */
    function getHash(
        PackedUserOperation calldata _userOp,
        address _sponsorAccount,
        uint48 _validUntil,
        uint48 _validAfter,
        uint32 _feeMarkup
    ) public view returns (bytes32) {
        return keccak256(
            abi.encode(
                _userOp.getSender(),
                _userOp.nonce,
                keccak256(_userOp.initCode),
                keccak256(_userOp.callData),
                _userOp.accountGasLimits,
                uint256(bytes32(_userOp.paymasterAndData[PAYMASTER_VALIDATION_GAS_OFFSET:PAYMASTER_DATA_OFFSET])),
                _userOp.preVerificationGas,
                _userOp.gasFees,
                block.chainid,
                address(this),
                _sponsorAccount,
                _validUntil,
                _validAfter,
                _feeMarkup
            )
        );
    }

    /**
     * @notice Retrieves withdrawal request details for a given sponsor account
     * @param _sponsorAccount The address of the sponsor
     * @return exists Boolean indicating if a withdrawal request exists
     * @return amount The amount requested for withdrawal
     * @return to The address where the withdrawal is requested to be sent
     * @return requestSubmittedTimestamp The timestamp when the withdrawal request was submitted
     */
    function getWithdrawalRequest(address _sponsorAccount)
        external
        view
        returns (bool exists, uint256 amount, address to, uint256 requestSubmittedTimestamp)
    {
        WithdrawalRequest memory request = withdrawalRequests[_sponsorAccount];
        if (request.requestSubmittedTimestamp != 0) {
            // Request exists
            return (true, request.amount, request.to, request.requestSubmittedTimestamp);
        } else {
            // No request exists, return defaults
            return (false, 0, address(0), 0);
        }
    }

    /**
     * @notice Parses the paymaster data to extract relevant information
     * @param _paymasterAndData The encoded paymaster data
     * @return sponsorAccount The sponsor account address
     * @return validUntil The timestamp until which the operation is valid
     * @return validAfter The timestamp after which the operation is valid
     * @return feeMarkup The fee markup for the operation
     * @return paymasterValidationGasLimit The gas limit for paymaster validation
     * @return paymasterPostOpGasLimit The gas limit for post-operation
     * @return signature The signature validating the operation
     */
    function parsePaymasterAndData(bytes calldata _paymasterAndData)
        public
        pure
        returns (
            address sponsorAccount,
            uint48 validUntil,
            uint48 validAfter,
            uint32 feeMarkup,
            uint128 paymasterValidationGasLimit,
            uint128 paymasterPostOpGasLimit,
            bytes calldata signature
        )
    {
        // require(_paymasterAndData.length > SIGNATURE_OFFSET, "Invalid paymasterAndData length");
        sponsorAccount = address(bytes20(_paymasterAndData[SPONSOR_ACCOUNT_OFFSET:VALID_UNTIL_TIMESTAMP_OFFSET]));
        validUntil = uint48(bytes6(_paymasterAndData[VALID_UNTIL_TIMESTAMP_OFFSET:VALID_AFTER_TIMESTAMP_OFFSET]));
        validAfter = uint48(bytes6(_paymasterAndData[VALID_AFTER_TIMESTAMP_OFFSET:FEE_MARKUP_OFFSET]));
        feeMarkup = uint32(bytes4(_paymasterAndData[FEE_MARKUP_OFFSET:FEE_MARKUP_OFFSET + FEE_MARKUP_LENGTH]));
        paymasterValidationGasLimit =
            uint128(bytes16(_paymasterAndData[PAYMASTER_VALIDATION_GAS_OFFSET:PAYMASTER_POSTOP_GAS_OFFSET]));
        paymasterPostOpGasLimit = uint128(bytes16(_paymasterAndData[PAYMASTER_POSTOP_GAS_OFFSET:PAYMASTER_DATA_OFFSET]));
        signature = _paymasterAndData[SIGNATURE_OFFSET:];
    }

    /**
     * @notice Internal function that validates constructor arguments
     * @param _feeCollectorArg The fee collector address to validate
     * @param _unaccountedGasArg The unaccounted gas value to validate
     */
    function _checkConstructorArgs(address _feeCollectorArg, uint256 _unaccountedGasArg) internal view {
        // Checks for constructor arguments
        // Ensure feeCollector is not zero address
        // Ensure feeCollector is not a contract
        // Ensure unaccountedGas is within limit
        if (_feeCollectorArg == address(0)) {
            revert FeeCollectorCanNotBeZero();
        } else if (_isContract(_feeCollectorArg)) {
            revert FeeCollectorCanNotBeContract();
        } else if (_unaccountedGasArg > UNACCOUNTED_GAS_LIMIT) {
            revert UnaccountedGasTooHigh();
        }
    }

    /**
     * @notice Validates the UserOperation and deducts the required gas sponsorship amount
     * @param _userOp The UserOperation being validated
     * @param _userOpHash The hash of the UserOperation
     * @param _requiredPreFund The required ETH for the UserOperation
     * @return Encoded context for post-operation handling and validationData for EntryPoint
     */
    function _validatePaymasterUserOp(
        PackedUserOperation calldata _userOp,
        bytes32 _userOpHash,
        uint256 _requiredPreFund
    ) internal override returns (bytes memory, uint256) {
        (
            address sponsorAccount,
            uint48 validUntil,
            uint48 validAfter,
            uint32 feeMarkup,
            uint128 paymasterValidationGasLimit,
            uint128 paymasterPostOpGasLimit,
            bytes calldata signature
        ) = parsePaymasterAndData(_userOp.paymasterAndData);
        (paymasterValidationGasLimit, paymasterPostOpGasLimit); // Unused parameters

        if (signature.length != 64 && signature.length != 65) {
            revert PaymasterSignatureLengthInvalid();
        }

        if (unaccountedGas > _userOp.unpackPostOpGasLimit()) {
            revert PostOpGasLimitTooLow();
        }

        address recoveredSigner = (
            (getHash(_userOp, sponsorAccount, validUntil, validAfter, feeMarkup).toEthSignedMessageHash()).tryRecover(
                signature
            )
        );

        if (recoveredSigner == address(0)) {
            revert PotentiallyMalformedSignature();
        }

        bool isValidSig = signers[recoveredSigner];

        uint256 validationData = _packValidationData(!isValidSig, validUntil, validAfter);

        // Do not revert if signature is invalid, just return validationData
        if (!isValidSig) {
            return ("", validationData);
        }

        // Ensure valid feeMarkup (1e6 for no markup, up to 2e6 max)
        if (feeMarkup > 2e6 || feeMarkup < 1e6) {
            revert InvalidPriceMarkup();
        }

        // Calculate effective cost including unaccountedGas and feeMarkup
        uint256 effectiveCost = (
            ((_requiredPreFund + (unaccountedGas * _userOp.unpackMaxFeePerGas())) * feeMarkup) + FEE_MARKUP_DENOMINATOR
                - 1
        ) / FEE_MARKUP_DENOMINATOR;

        // Ensure the paymaster can cover the effective cost + max penalty
        if (effectiveCost > sponsorBalances[sponsorAccount]) {
            revert InsufficientFunds(sponsorAccount, sponsorBalances[sponsorAccount], effectiveCost);
        }

        sponsorBalances[sponsorAccount] -= (effectiveCost);
        emit UserOperationSponsored(_userOpHash, _userOp.getSender());

        // Save some state to help calculate the expected penalty during postOp
        uint256 preOpGasApproximation = _userOp.preVerificationGas + _userOp.unpackVerificationGasLimit()
            + _userOp.unpackPaymasterVerificationGasLimit();
        uint256 executionGasLimit = _userOp.unpackCallGasLimit() + _userOp.unpackPostOpGasLimit();

        return (
            abi.encode(sponsorAccount, feeMarkup, effectiveCost, preOpGasApproximation, executionGasLimit),
            validationData
        );
    }

    /**
     * @notice Handles the post-operation logic after transaction execution
     * @param _mode The PostOpMode (OpSucceeded, OpReverted, or PostOpReverted)
     * @param _context Encoded context passed from `_validatePaymasterUserOp`
     * @param _actualGasCost The actual gas cost incurred
     * @param _actualUserOpFeePerGas The effective gas price used for calculation
     */
    function _postOp(PostOpMode _mode, bytes calldata _context, uint256 _actualGasCost, uint256 _actualUserOpFeePerGas)
        internal
        override
    {
        (
            address sponsorAccount,
            uint32 feeMarkup,
            uint256 prechargedAmount,
            uint256 preOpGasApproximation,
            uint256 executionGasLimit
        ) = abi.decode(_context, (address, uint32, uint256, uint256, uint256));

        uint256 actualGas = _actualGasCost / _actualUserOpFeePerGas;

        uint256 executionGasUsed;
        if (actualGas + unaccountedGas > preOpGasApproximation) {
            executionGasUsed = actualGas + unaccountedGas - preOpGasApproximation;
        }

        uint256 expectedPenaltyGas;
        if (executionGasLimit > executionGasUsed) {
            expectedPenaltyGas = (executionGasLimit - executionGasUsed) * PENALTY_PERCENT / 100;
        }
        // Review: could emit expected penalty gas

        // Include unaccountedGas since EP doesn't include this in actualGasCost
        // unaccountedGas = postOpGas + EP overhead gas
        _actualGasCost = _actualGasCost + ((unaccountedGas + expectedPenaltyGas) * _actualUserOpFeePerGas);

        uint256 adjustedGasCost = (_actualGasCost * feeMarkup + FEE_MARKUP_DENOMINATOR - 1) / FEE_MARKUP_DENOMINATOR;
        uint256 premium = adjustedGasCost - _actualGasCost;
        sponsorBalances[feeCollector] += premium;

        if (prechargedAmount > adjustedGasCost) {
            // Refund excess gas fees
            uint256 refund = prechargedAmount - adjustedGasCost;
            sponsorBalances[sponsorAccount] += refund;
            // Review: whether to consider this for premium
            emit RefundProcessed(sponsorAccount, refund);
        } else {
            // Handle undercharge scenario
            uint256 deduction = adjustedGasCost - prechargedAmount;
            sponsorBalances[sponsorAccount] -= deduction;
        }

        emit GasBalanceDeducted(sponsorAccount, _actualGasCost, premium, _mode);
    }

    /**
     * @notice Internal function to withdraw ERC20 tokens
     * @param _token The token to withdraw
     * @param _target The address to send tokens to
     * @param _amount The amount to withdraw
     */
    function _withdrawERC20(IERC20 _token, address _target, uint256 _amount) private {
        if (_target == address(0)) revert InvalidWithdrawalAddress();
        SafeTransferLib.safeTransfer(address(_token), _target, _amount);
        emit TokensWithdrawn(address(_token), _target, msg.sender, _amount);
    }
}
