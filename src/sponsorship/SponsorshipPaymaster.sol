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
import {MultiSigners} from "./MultiSigners.sol";

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

    //Keep withdrwal related info in one struct
    mapping(address sponsorAccount => WithdrawalRequest request) internal withdrawalRequests;

    uint256 public sponsorWithdrawalDelay;
    uint256 public unaccountedGas;

    /**
     * @dev Initializes the SponsorshipPaymaster contract.
     * @param _owner The owner of the paymaster.
     * @param _entryPoint The ERC-4337 EntryPoint contract address.
     * @param _signers Array of authorized signers for paymaster validation.
     * @param _feeCollector Address that collects the extra fee (premium).
     * @param _minDeposit Minimum deposit required for a user to be sponsored.
     * @param _withdrawalDelay Delay in seconds before a user can withdraw funds.
     * @param _unaccountedGas Extra gas used for post-operation adjustments.
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
    }

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
     * @dev Allows users to deposit ETH to be used for sponsoring gas fees.
     * @param _sponsorAccount The address of the user making the deposit.
     * @notice The deposit is recorded in `sponsorBalances` and also transferred to EntryPoint.
     * @notice Requires first-time deposit to be greater than `minDeposit`.
     */
    function depositFor(address _sponsorAccount) external payable nonReentrant {
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
     * @dev Allows the contract owner to set the minimum deposit required for gas sponsorship.
     * @param newMinDeposit The new minimum deposit value.
     */
    function setMinDeposit(uint256 newMinDeposit) external onlyOwner {
        emit MinDepositChanged(minDeposit, newMinDeposit);
        minDeposit = newMinDeposit;
    }

    /**
     * @dev Allows users to request withdrawals from their paymaster balance.
     * @notice Ensures the user has enough balance and respects the withdrawal delay.
     * @param withdrawAddress The address to send the withdrawal to.
     * @param amount The amount of ETH the user wishes to withdraw.
     */
    function requestWithdrawal(address withdrawAddress, uint256 amount) external {
        // check zero address for withdrawal
        if (withdrawAddress == address(0)) {
            revert InvalidWithdrawalAddress();
        }
        // check for non-zero amount
        if (amount == 0) {
            revert CanNotWithdrawZeroAmount();
        }
        if (sponsorBalances[msg.sender] < amount) {
            revert InsufficientFunds(msg.sender, sponsorBalances[msg.sender], amount);
        }
        withdrawalRequests[msg.sender] =
            WithdrawalRequest({amount: amount, to: withdrawAddress, requestSubmittedTimestamp: block.timestamp});
        emit WithdrawalRequested(msg.sender, withdrawAddress, amount);
    }

    /**
     * @dev Allows the owner to set a new withdrawal delay.
     * @param newWithdrawalDelay The new withdrawal delay in seconds.
     */
    function setWithdrawalDelay(uint256 newWithdrawalDelay) external onlyOwner {
        sponsorWithdrawalDelay = newWithdrawalDelay;
    }

    /**
     * @dev Executes the withdrawal request for a given funding account.
     * @notice Ensures the request was made, checks withdrawal delay
     * @param sponsorAccount The address of the user withdrawing funds.
     */
    function executeWithdrawal(address sponsorAccount) external nonReentrant {
        WithdrawalRequest memory req = withdrawalRequests[sponsorAccount];
        if (req.requestSubmittedTimestamp == 0) revert NoWithdrawalRequestSubmitted(sponsorAccount);

        // Note: We could add trusted sponsor accounts with zero withdrawal delay
        uint256 clearanceTimestamp = req.requestSubmittedTimestamp + sponsorWithdrawalDelay;

        if (block.timestamp < clearanceTimestamp) revert WithdrawalTooSoon(sponsorAccount, clearanceTimestamp);

        uint256 currentBalance = sponsorBalances[sponsorAccount];

        req.amount = req.amount > currentBalance ? currentBalance : req.amount;
        if (req.amount == 0) revert CanNotWithdrawZeroAmount();
        sponsorBalances[sponsorAccount] = currentBalance - req.amount;
        delete withdrawalRequests[sponsorAccount];
        entryPoint.withdrawTo(payable(req.to), req.amount);
        emit WithdrawalExecuted(sponsorAccount, req.to, req.amount);
    }

    /**
     * @dev Allows the owner to set a new fee collector address.
     * @param newFeeCollector The new fee collector address.
     */
    function setFeeCollector(address newFeeCollector) external payable onlyOwner {
        require(newFeeCollector != address(0), "Invalid feeCollector address");
        address oldFeeCollector = feeCollector;
        feeCollector = newFeeCollector;
        emit FeeCollectorChanged(oldFeeCollector, newFeeCollector);
    }

    /**
     * @dev Adds a new signer to the list of authorized signers.
     * @param _signer The address of the signer to add.
     */
    function addSigner(address _signer) external payable onlyOwner {
        _addSigner(_signer);
    }

    /**
     * @dev Removes a signer from the list of authorized signers.
     * @param _signer The address of the signer to remove.
     */
    function removeSigner(address _signer) external payable onlyOwner {
        _removeSigner(_signer);
    }

    function withdrawEth(address payable recipient, uint256 amount) external payable onlyOwner nonReentrant {
        (bool success,) = recipient.call{value: amount}("");
        if (!success) {
            revert WithdrawalFailed();
        }
        emit EthWithdrawn(recipient, amount);
    }

    /**
     * @dev pull tokens out of paymaster in case they were sent to the paymaster at any point.
     * @param token the token deposit to withdraw
     * @param target address to send to
     * @param amount amount to withdraw
     */
    function withdrawERC20(IERC20 token, address target, uint256 amount) external onlyOwner nonReentrant {
        _withdrawERC20(token, target, amount);
    }

    function _withdrawERC20(IERC20 token, address target, uint256 amount) private {
        if (target == address(0)) revert InvalidWithdrawalAddress();
        SafeTransferLib.safeTransfer(address(token), target, amount);
        emit TokensWithdrawn(address(token), target, msg.sender, amount);
    }

    /**
     * @dev Retrieves the balance of a specific funding account.
     * @param sponsorAccount The address of the user.
     * @return balance The current balance of the user in the paymaster.
     */
    function getBalance(address sponsorAccount) external view returns (uint256 balance) {
        balance = sponsorBalances[sponsorAccount];
    }

    /**
     * @dev Generates a hash of the given UserOperation to be signed by the paymaster.
     * @param userOp The UserOperation structure.
     * @return The hashed UserOperation data.
     */
    function getHash(
        PackedUserOperation calldata userOp,
        address sponsorAccount,
        uint48 validUntil,
        uint48 validAfter,
        uint32 feeMarkup
    ) public view returns (bytes32) {
        return keccak256(
            abi.encode(
                userOp.getSender(),
                userOp.nonce,
                keccak256(userOp.initCode),
                keccak256(userOp.callData),
                userOp.accountGasLimits,
                uint256(bytes32(userOp.paymasterAndData[PAYMASTER_VALIDATION_GAS_OFFSET:PAYMASTER_DATA_OFFSET])),
                userOp.preVerificationGas,
                userOp.gasFees,
                block.chainid,
                address(this),
                sponsorAccount,
                validUntil,
                validAfter,
                feeMarkup
            )
        );
    }

    /**
     * @dev Validates the UserOperation and deducts the required gas sponsorship amount.
     * @param _userOp The UserOperation being validated.
     * @param _userOpHash The hash of the UserOperation.
     * @param requiredPreFund The required ETH for the UserOperation.
     * @return Encoded context for post-operation handling and validationData for EntryPoint.
     */
    function _validatePaymasterUserOp(
        PackedUserOperation calldata _userOp,
        bytes32 _userOpHash,
        uint256 requiredPreFund
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
        (paymasterValidationGasLimit, paymasterPostOpGasLimit);

        if (signature.length != 64 && signature.length != 65) {
            revert PaymasterSignatureLengthInvalid();
        }

        address recoveredSigner = (
            (getHash(_userOp, sponsorAccount, validUntil, validAfter, feeMarkup).toEthSignedMessageHash()).tryRecover(
                signature
            )
        );

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

        // Calculate the max penalty to ensure the paymaster doesn't underpay
        uint256 maxPenalty = (
            (
                uint128(uint256(_userOp.accountGasLimits))
                    + uint128(bytes16(_userOp.paymasterAndData[PAYMASTER_POSTOP_GAS_OFFSET:PAYMASTER_DATA_OFFSET]))
            ) * 10 * _userOp.unpackMaxFeePerGas()
        ) / 100;

        // Calculate effective cost including unaccountedGas and feeMarkup
        uint256 effectiveCost =
            ((requiredPreFund + (unaccountedGas * _userOp.unpackMaxFeePerGas())) * feeMarkup) / FEE_MARKUP_DENOMINATOR;

        // Ensure the paymaster can cover the effective cost + max penalty
        if (effectiveCost + maxPenalty > sponsorBalances[sponsorAccount]) {
            revert InsufficientFunds(sponsorAccount, sponsorBalances[sponsorAccount], effectiveCost + maxPenalty);
        }

        sponsorBalances[sponsorAccount] -= (effectiveCost + maxPenalty);
        emit UserOperationSponsored(_userOpHash, _userOp.getSender());

        return (abi.encode(sponsorAccount, feeMarkup, effectiveCost), validationData);
    }

    /**
     * @dev Handles the post-operation logic after transaction execution.
     * @notice Adjusts gas costs, refunds excess gas, and ensures sufficient paymaster balance.
     * @param mode The PostOpMode (OpSucceeded, OpReverted, or PostOpReverted).
     * @param context Encoded context passed from `_validatePaymasterUserOp`.
     * @param actualGasCost The actual gas cost incurred.
     * @param actualUserOpFeePerGas The effective gas price used for calculation.
     */
    function _postOp(PostOpMode mode, bytes calldata context, uint256 actualGasCost, uint256 actualUserOpFeePerGas)
        internal
        override
    {
        (address sponsorAccount, uint32 feeMarkup, uint256 prechargedAmount) =
            abi.decode(context, (address, uint32, uint256));
        // Include unaccountedGas since EP doesn't include this in actualGasCost
        // unaccountedGas = postOpGas + EP overhead gas
        actualGasCost = actualGasCost + (unaccountedGas * actualUserOpFeePerGas);

        uint256 adjustedGasCost = (actualGasCost * feeMarkup) / FEE_MARKUP_DENOMINATOR;
        uint256 premium = adjustedGasCost - actualGasCost;
        sponsorBalances[feeCollector] += premium;

        if (prechargedAmount > adjustedGasCost) {
            // Refund excess gas fees
            uint256 refund = prechargedAmount - adjustedGasCost;
            sponsorBalances[sponsorAccount] += refund;
            emit RefundProcessed(sponsorAccount, refund);
        } else {
            // Handle undercharge scenario
            uint256 deduction = adjustedGasCost - prechargedAmount;
            sponsorBalances[sponsorAccount] -= deduction;
        }

        emit GasBalanceDeducted(sponsorAccount, actualGasCost, premium, mode);
    }

    /**
     * @dev Retrieves the withdrawal request details for a given sponsor account.
     * @param sponsorAccount The address of the sponsor.
     * @return exists Boolean indicating if a withdrawal request exists.
     * @return amount The amount requested for withdrawal (0 if no request exists).
     * @return to The address where the withdrawal is requested to be sent (address(0) if no request exists).
     * @return requestSubmittedTimestamp The timestamp when the withdrawal request was submitted (0 if no request exists).
     */
    function getWithdrawalRequest(address sponsorAccount)
        external
        view
        returns (bool exists, uint256 amount, address to, uint256 requestSubmittedTimestamp)
    {
        WithdrawalRequest memory request = withdrawalRequests[sponsorAccount];
        if (request.requestSubmittedTimestamp != 0) {
            // Request exists
            return (true, request.amount, request.to, request.requestSubmittedTimestamp);
        } else {
            // No request exists, return defaults
            return (false, 0, address(0), 0);
        }
    }

    /**
     * @dev Parses the paymaster data to extract relevant information.
     * @param _paymasterAndData The encoded paymaster data.
     * paymasterAndData[:20]   : address(this)
     * paymasterAndData[20:36] : paymaster validation gas
     * paymasterAndData[36:52] : paymaster post-op gas
     * paymasterAndData[52:72] : sponsorAccount
     * paymasterAndData[72:84] : abi.packedEncode(validUntil, validAfter) - uint48 (6bytes length) for each
     * paymasterAndData[84:88] : feeMarkup
     * paymasterAndData[88:]   : signature
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
     * @dev Overrides default deposit function to prevent direct deposits.
     */
    function deposit() external payable virtual override {
        revert UseDepositForInstead();
    }

    /**
     * @dev Overrides default withdraw function to enforce request-based withdrawal.
     */
    function withdrawTo(address payable withdrawAddress, uint256 amount) external virtual override {
        (withdrawAddress, amount);
        revert SubmitRequestInstead();
    }

    /**
     * @dev Allows the owner to set the extra gas used in post-op calculations.
     * @notice Ensures the value does not exceed `UNACCOUNTED_GAS_LIMIT`.
     * @param value The new unaccounted gas value.
     */
    function setUnaccountedGas(uint256 value) external payable onlyOwner {
        if (value > UNACCOUNTED_GAS_LIMIT) {
            revert UnaccountedGasTooHigh();
        }
        unaccountedGas = value;
    }
}
