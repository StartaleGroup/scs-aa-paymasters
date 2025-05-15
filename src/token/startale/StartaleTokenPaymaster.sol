// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {SignatureCheckerLib} from "solady/utils/SignatureCheckerLib.sol";
import {ECDSA as ECDSA_solady} from "solady/utils/ECDSA.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {BasePaymaster} from "../../base/BasePaymaster.sol";
import {UserOperationLib, PackedUserOperation} from "@account-abstraction/contracts/core/UserOperationLib.sol";
import {_packValidationData} from "@account-abstraction/contracts/core/Helpers.sol";
import {IEntryPoint} from "@account-abstraction/contracts/interfaces/IEntryPoint.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MultiSigners} from "../../lib/MultiSigners.sol";
import {PriceOracleHelper} from "./PriceOracleHelper.sol";
import {IStartaleTokenPaymaster} from "../../interfaces/IStartaleTokenPaymaster.sol";
import {IOracleHelper} from "../../interfaces/IOracleHelper.sol";
import {IWETH} from "@uniswap/swap-router-contracts/contracts/interfaces/IWETH.sol";
import {TokenPaymasterParserLib} from "../../lib/TokenPaymasterParserLib.sol";

/**
 * @title StartaleTokenPaymaster
 * @author Startale
 * @notice ERC20 Token Paymaster for Startale that supports multiple tokens
 * @dev Handles payment for account abstraction operations using ERC20 tokens
 */
contract StartaleTokenPaymaster is
    BasePaymaster,
    MultiSigners,
    PriceOracleHelper,
    ReentrancyGuardTransient,
    IStartaleTokenPaymaster
{
    using UserOperationLib for PackedUserOperation;
    using SignatureCheckerLib for address;
    using ECDSA_solady for bytes32;
    using TokenPaymasterParserLib for bytes;

    // Constants
    /// @dev Denominator to prevent precision errors when applying fee markup
    uint256 private constant FEE_MARKUP_DENOMINATOR = 1e6;

    /// @dev Maximum allowed fee markup
    uint256 private constant MAX_FEE_MARKUP = 2e6;

    /// @dev Penalty percentage for exceeding the execution gas limit
    uint256 private constant PENALTY_PERCENT = 10;

    /// @dev Limit for unaccounted gas cost
    uint256 private constant UNACCOUNTED_GAS_LIMIT = 150_000;

    // State variables
    /// @notice Address where token fees are collected
    address public tokenFeesTreasury;

    /// @notice Gas amount not accounted for in calculations
    uint256 public unaccountedGas;

    /// @notice Allowlist of bundlers to use if restricting bundlers is enabled
    mapping(address bundler => bool allowed) public isBundlerAllowed;

    /// @notice Whether to allow all bundlers or not
    bool public allowAllBundlers;

    /// @notice Mapping for independent tokens to their activated state and fee markup
    /// @dev The actual information on token oracle config is stored in the parent contract(OracleHelper) in a different mapping
    mapping(address => TokenConfig) private tokenConfigs;

    /**
     * @notice Initializes the token paymaster contract
     * @param _owner Owner address for the paymaster
     * @param _entryPoint EntryPoint contract address
     * @param _signers Array of initial signer addresses
     * @param _tokenFeesTreasury Address where token fees will be collected
     * @param _unaccountedGas Gas amount not accounted for in calculations
     * @param _nativeAssetToUsdOracle Oracle for native asset to USD price
     * @param _nativeAssetMaxOracleRoundAge Maximum age for native asset oracle data
     * @param _nativeAssetDecimals Decimals of the native asset
     * @param _independentTokens Array of supported token addresses
     * @param _feeMarkupsForIndependentTokens Array of fee markups for supported tokens
     * @param _tokenOracleConfigs Array of oracle configs for supported tokens
     */
    constructor(
        address _owner,
        address _entryPoint,
        address[] memory _signers,
        address _tokenFeesTreasury,
        uint256 _unaccountedGas,
        address _nativeAssetToUsdOracle,
        address _sequencerUptimeOracle,
        uint48 _nativeAssetMaxOracleRoundAge,
        uint8 _nativeAssetDecimals,
        address[] memory _independentTokens,
        uint48[] memory _feeMarkupsForIndependentTokens,
        IOracleHelper.TokenOracleConfig[] memory _tokenOracleConfigs
    )
        BasePaymaster(_owner, IEntryPoint(_entryPoint))
        MultiSigners(_signers)
        PriceOracleHelper(
            _nativeAssetToUsdOracle,
            _sequencerUptimeOracle,
            IOracleHelper.NativeOracleConfig({
                maxOracleRoundAge: _nativeAssetMaxOracleRoundAge,
                nativeAssetDecimals: _nativeAssetDecimals
            }),
            _independentTokens,
            _tokenOracleConfigs
        )
    {
        if (
            _independentTokens.length != _feeMarkupsForIndependentTokens.length
                || _independentTokens.length != _tokenOracleConfigs.length
        ) {
            revert ArrayLengthMismatch();
        }

        if (_tokenFeesTreasury == address(0)) {
            revert InvalidTokenFeesTreasury();
        }
        tokenFeesTreasury = _tokenFeesTreasury;
        emit TokenFeesTreasuryChanged(address(0), _tokenFeesTreasury);

        if (_unaccountedGas > UNACCOUNTED_GAS_LIMIT) {
            revert UnaccountedGasTooHigh();
        }
        unaccountedGas = _unaccountedGas;
        emit UnaccountedGasChanged(0, _unaccountedGas);
        for (uint256 i = 0; i < _independentTokens.length; i++) {
            _addSupportedToken(_independentTokens[i], _feeMarkupsForIndependentTokens[i], _tokenOracleConfigs[i]);
        }
        allowAllBundlers = true;
    }

    // No receive/fallback functions in this contract

    // External non-view functions

    /**
     * @notice Sets the unaccounted gas used in post-op calculations
     * @dev Ensures the value does not exceed `UNACCOUNTED_GAS_LIMIT`
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
     * @notice Sets the token fees treasury address
     * @param _tokenFeesTreasury The address of the token fees treasury
     */
    function setTokenFeesTreasury(address _tokenFeesTreasury) external payable onlyOwner {
        if (_tokenFeesTreasury == address(0)) {
            revert InvalidTokenFeesTreasury();
        }
        address oldTokenFeesTreasury = tokenFeesTreasury;
        tokenFeesTreasury = _tokenFeesTreasury;
        emit TokenFeesTreasuryChanged(oldTokenFeesTreasury, _tokenFeesTreasury);
    }

    /**
     * @notice Withdraw tokens from paymaster in case they were sent to the paymaster
     * @dev Can be used to recover accidentally sent tokens or for manual withdrawals
     * @param _token The token to withdraw
     * @param _target Address to send tokens to
     * @param _amount Amount to withdraw
     */
    function withdrawERC20(IERC20 _token, address _target, uint256 _amount) external onlyOwner nonReentrant {
        _withdrawERC20(_token, _target, _amount);
    }

    /**
     * @notice Withdraws ETH from the paymaster
     * @param _recipient The address to send the ETH to
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
     * @notice Adds a new supported token with its configuration
     * @param _token The token address
     * @param _feeMarkup The fee markup for the token
     * @param _oracleConfig The oracle configuration for the token
     */
    function addSupportedToken(
        address _token,
        uint48 _feeMarkup,
        IOracleHelper.TokenOracleConfig calldata _oracleConfig
    ) external onlyOwner {
        _addSupportedToken(_token, _feeMarkup, _oracleConfig);
    }

    /**
     * @notice Removes a supported token
     * @param _token The token address to remove
     */
    function removeSupportedToken(address _token) external onlyOwner {
        if (!tokenConfigs[_token].isEnabled) {
            revert TokenNotSupported(_token);
        }

        delete tokenConfigs[_token];
        delete tokenOracleConfigurations[_token];
        emit TokenRemoved(_token);
    }

    /**
     * @notice Updates the oracle configuration for a specific token
     * @param _token The token address
     * @param _newOracleConfig The new oracle configuration
     */
    function updateTokenOracleConfig(address _token, IOracleHelper.TokenOracleConfig calldata _newOracleConfig)
        external
        onlyOwner
    {
        if (!tokenConfigs[_token].isEnabled) {
            revert TokenNotSupported(_token);
        }

        _updateTokenOracleConfig(_token, _newOracleConfig);
    }

    /**
     * @notice Updates the native oracle configuration
     * @param _newNativeOracleConfig The new oracle configuration
     */
    function updateNativeOracleConfig(IOracleHelper.NativeOracleConfig calldata _newNativeOracleConfig)
        external
        onlyOwner
    {
        _updateNativeOracleConfig(_newNativeOracleConfig);
    }

    /**
     * @notice Updates the native asset to USD oracle
     * @param _newNativeAssetToUsdOracle The new native asset to USD oracle address
     */
    function updateNativeAssetToUsdOracle(
        address _newNativeAssetToUsdOracle,
        uint48 _nativeAssetMaxOracleRoundAge,
        uint8 _nativeAssetDecimals
    ) external onlyOwner {
        _updateNativeAssetToUsdOracle(_newNativeAssetToUsdOracle);
        _updateNativeOracleConfig(
            IOracleHelper.NativeOracleConfig({
                maxOracleRoundAge: _nativeAssetMaxOracleRoundAge,
                nativeAssetDecimals: _nativeAssetDecimals
            })
        );
    }

    /**
     * @notice Updates the fee markup for a specific token
     * @param _token The token address to update
     * @param _newFeeMarkup The new fee markup value
     */
    function updateTokenFeeMarkup(address _token, uint48 _newFeeMarkup) external onlyOwner {
        if (!tokenConfigs[_token].isEnabled) {
            revert TokenNotSupported(_token);
        }
        if (_newFeeMarkup > MAX_FEE_MARKUP) {
            revert FeeMarkupTooHigh();
        }

        tokenConfigs[_token].feeMarkup = _newFeeMarkup;
        emit TokenFeeMarkupUpdated(_token, _newFeeMarkup);
    }

    /// @notice Add or remove multiple bundlers to/from the allowlist
    /// @param bundlers Array of bundler addresses
    /// @param allowed Boolean indicating if bundlers should be allowed or not
    function updateBundlerAllowlist(address[] calldata bundlers, bool allowed) external onlyOwner {
        for (uint256 i = 0; i < bundlers.length; i++) {
            isBundlerAllowed[bundlers[i]] = allowed;
            emit BundlerAllowlistUpdated(bundlers[i], allowed);
        }
    }

    /**
     * @notice Sets whether to allow all bundlers or not
     * @notice If true, all bundlers will be allowed regardless of the allowlist. Default is true
     * @param _allowAllBundlers Boolean indicating if all bundlers should be allowed
     */
    function allowAllBundlersYesOrNo(bool _allowAllBundlers) external onlyOwner {
        // Only update and emit if there's an actual change
        if (allowAllBundlers != _allowAllBundlers) {
            allowAllBundlers = _allowAllBundlers;
            emit AllowAllBundlersUpdated(_allowAllBundlers);
        }
    }

    // External view/pure functions

    /**
     * @notice Generates a hash of the given UserOperation to be signed by the paymaster
     * @param _userOp The UserOperation structure
     * @param _validUntil The timestamp until which the UserOperation is valid
     * @param _validAfter The timestamp after which the UserOperation is valid
     * @param _tokenAddress The address of the token to be used for the UserOperation
     * @param _exchangeRate The exchange rate of the token
     * @param _appliedFeeMarkup The fee markup for the UserOperation
     * @return The hashed UserOperation data
     */
    function getHashForExternalMode(
        PackedUserOperation calldata _userOp,
        uint48 _validUntil,
        uint48 _validAfter,
        address _tokenAddress,
        uint256 _exchangeRate,
        uint48 _appliedFeeMarkup
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
                _validUntil,
                _validAfter,
                _tokenAddress,
                _exchangeRate,
                _appliedFeeMarkup
            )
        );
    }

    /**
     * @notice Checks if a token is supported and enabled
     * @param _token The token address to check
     * @return bool True if token is supported and enabled
     */
    function isTokenSupported(address _token) public view returns (bool) {
        return tokenConfigs[_token].isEnabled;
    }

    /**
     * @notice Gets the fee markup for a specific token
     * @param _token The token address
     * @return uint48 The fee markup value
     */
    function getTokenFeeMarkup(address _token) public view returns (uint48) {
        return tokenConfigs[_token].feeMarkup;
    }

    /**
     * @notice Parses the paymaster data to extract relevant information for external mode
     * @param _paymasterAndData The encoded paymaster data
     * @return validUntil The timestamp until which the operation is valid
     * @return validAfter The timestamp after which the operation is valid
     * @return tokenAddress The address of the token to be used for the operation
     * @return exchangeRate The exchange rate of the token
     * @return appliedFeeMarkup The fee markup for the operation
     * @return paymasterValidationGasLimit The gas limit for paymaster validation
     * @return paymasterPostOpGasLimit The gas limit for post-operation
     * @return signature The signature validating the operation
     */
    function parsePaymasterAndDataForExternalMode(bytes calldata _paymasterAndData)
        public
        pure
        returns (
            uint48 validUntil,
            uint48 validAfter,
            address tokenAddress,
            uint256 exchangeRate,
            uint48 appliedFeeMarkup,
            uint128 paymasterValidationGasLimit,
            uint128 paymasterPostOpGasLimit,
            bytes calldata signature
        )
    {
        (PaymasterMode mode, bytes calldata modeSpecificData) = _paymasterAndData.parsePaymasterAndData();
        if (mode != PaymasterMode.EXTERNAL) {
            revert InvalidPaymasterMode();
        }

        paymasterValidationGasLimit =
            uint128(bytes16(_paymasterAndData[PAYMASTER_VALIDATION_GAS_OFFSET:PAYMASTER_POSTOP_GAS_OFFSET]));
        paymasterPostOpGasLimit = uint128(bytes16(_paymasterAndData[PAYMASTER_POSTOP_GAS_OFFSET:PAYMASTER_DATA_OFFSET]));

        (validUntil, validAfter, tokenAddress, exchangeRate, appliedFeeMarkup, signature) =
            modeSpecificData.parseExternalModeSpecificData();
    }

    // No public non-view functions in this contract

    // Internal non-view functions

    /**
     * @notice Handles the post-operation logic after transaction execution
     * @dev Adjusts gas costs, refunds excess gas, and ensures sufficient paymaster balance
     * @param _mode The post-operation mode
     * @param _context Encoded context passed from `_validatePaymasterUserOp`
     * @param _actualGasCost The actual gas cost incurred
     * @param _actualUserOpFeePerGas The effective gas price used for calculation
     */
    function _postOp(PostOpMode _mode, bytes calldata _context, uint256 _actualGasCost, uint256 _actualUserOpFeePerGas)
        internal
        override
    {
        (_mode); // Unused parameter

        (
            address sender,
            address tokenAddress,
            uint256 preOpGasApproximation,
            uint256 executionGasLimit,
            uint256 exchangeRate,
            uint48 appliedFeeMarkup
        ) = abi.decode(_context, (address, address, uint256, uint256, uint256, uint48));

        uint256 actualGas = _actualGasCost / _actualUserOpFeePerGas;

        uint256 executionGasUsed;
        if (actualGas + unaccountedGas > preOpGasApproximation) {
            executionGasUsed = actualGas + unaccountedGas - preOpGasApproximation;
        }

        uint256 expectedPenaltyGas;
        if (executionGasLimit > executionGasUsed) {
            expectedPenaltyGas = (executionGasLimit - executionGasUsed) * PENALTY_PERCENT / 100;
        }

        // Include unaccountedGas since EP doesn't include this in actualGasCost
        // unaccountedGas = postOpGas + EP overhead gas
        uint256 adjustedGasCost = _actualGasCost + ((unaccountedGas + expectedPenaltyGas) * _actualUserOpFeePerGas);
        adjustedGasCost = (adjustedGasCost * appliedFeeMarkup + FEE_MARKUP_DENOMINATOR - 1) / FEE_MARKUP_DENOMINATOR;

        // There is no preCharged amount so we can go ahead and transfer the token now
        uint256 tokenAmount = (adjustedGasCost * exchangeRate + (10 ** nativeOracleConfig.nativeAssetDecimals) - 1)
            / (10 ** nativeOracleConfig.nativeAssetDecimals);

        if (tokenAmount == 0) return;

        if (SafeTransferLib.trySafeTransferFrom(tokenAddress, sender, tokenFeesTreasury, tokenAmount)) {
            emit PaidGasInTokens(sender, tokenAddress, tokenAmount, appliedFeeMarkup, exchangeRate);
        } else {
            revert FailedToChargeTokens(sender, tokenAddress, tokenAmount);
        }
    }

    // Internal view/pure functions

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
    ) internal view override returns (bytes memory, uint256) {
        (_userOpHash); // Unused parameters

        (PaymasterMode mode, bytes calldata modeSpecificData) = _userOp.paymasterAndData.parsePaymasterAndData();

        // We only have two modes for now. Change this if we add more modes
        if (uint8(mode) > 1) {
            revert InvalidPaymasterMode();
        }

        // Ensure the postOp gas limit is not too low
        if (unaccountedGas > _userOp.unpackPostOpGasLimit()) {
            revert PostOpGasLimitTooLow();
        }

        address smartAccount = _userOp.getSender();

        // Save state to help calculate the expected penalty during postOp
        uint256 preOpGasApproximation = _userOp.preVerificationGas + _userOp.unpackVerificationGasLimit()
            + _userOp.unpackPaymasterVerificationGasLimit();

        uint256 executionGasLimit = _userOp.unpackCallGasLimit() + _userOp.unpackPostOpGasLimit();

        if (mode == PaymasterMode.INDEPENDENT) {
            // Check if bundler is allowed
            if (!allowAllBundlers && !isBundlerAllowed[tx.origin]) {
                revert BundlerNotAllowed(tx.origin);
            }

            (address tokenAddress) = modeSpecificData.parseIndependentModeSpecificData();
            // Check length - it must be 20 bytes
            if (modeSpecificData.length != 20) {
                revert InvalidIndependentModeSpecificData();
            }

            // Check if token is supported
            if (!isTokenSupported(tokenAddress)) {
                revert TokenNotSupported(tokenAddress);
            }

            uint48 feeMarkup = getTokenFeeMarkup(tokenAddress);

            // Calculate effective cost including unaccountedGas and feeMarkup
            uint256 effectiveCost = (
                ((_requiredPreFund + (unaccountedGas * _userOp.unpackMaxFeePerGas())) * feeMarkup)
                    + FEE_MARKUP_DENOMINATOR - 1
            ) / FEE_MARKUP_DENOMINATOR;

            (
                uint256 effectiveExchangeRate,
                uint256 effectiveExchangeRateValidUntil,
                uint256 effectiveExchangeRateValidAfter
            ) = getExchangeRate(tokenAddress);

            if (effectiveExchangeRate == 0) {
                revert TokenPriceFeedErrored(tokenAddress);
            }

            // There is no preCharged amount so we can go ahead and transfer the token now
            uint256 tokenAmount = (
                effectiveCost * effectiveExchangeRate + (10 ** nativeOracleConfig.nativeAssetDecimals) - 1
            ) / (10 ** nativeOracleConfig.nativeAssetDecimals);

            if (IERC20(tokenAddress).balanceOf(smartAccount) < tokenAmount) {
                revert InsufficientERC20Balance();
            }

            // Prepare context for postOp
            bytes memory context = abi.encode(
                _userOp.sender, tokenAddress, preOpGasApproximation, executionGasLimit, effectiveExchangeRate, feeMarkup
            );
            uint256 validationData = _packValidationData(false, uint48(effectiveExchangeRateValidUntil), 0);
            return (context, validationData);
        } else if (mode == PaymasterMode.EXTERNAL) {
            (
                uint48 validUntil,
                uint48 validAfter,
                address tokenAddress,
                uint256 exchangeRate,
                uint48 appliedFeeMarkup,
                bytes calldata signature
            ) = modeSpecificData.parseExternalModeSpecificData();

            if (exchangeRate == 0) {
                revert InvalidExchangeRate(tokenAddress);
            }

            // Validate signature length
            if (signature.length != 64 && signature.length != 65) {
                revert PaymasterSignatureLengthInvalid();
            }

            // Validate supplied markup is not greater than max markup
            if (appliedFeeMarkup > MAX_FEE_MARKUP) {
                revert FeeMarkupTooHigh();
            }

            // Calculate effective cost including unaccountedGas and feeMarkup
            uint256 effectiveCost = (
                ((_requiredPreFund + (unaccountedGas * _userOp.unpackMaxFeePerGas())) * appliedFeeMarkup)
                    + FEE_MARKUP_DENOMINATOR - 1
            ) / FEE_MARKUP_DENOMINATOR;

            // There is no preCharged amount so we can go ahead and transfer the token now
            uint256 tokenAmount = (effectiveCost * exchangeRate + (10 ** nativeOracleConfig.nativeAssetDecimals) - 1)
                / (10 ** nativeOracleConfig.nativeAssetDecimals);

            if (IERC20(tokenAddress).balanceOf(smartAccount) < tokenAmount) {
                revert InsufficientERC20Balance();
            }

            address recoveredSigner = (
                (
                    getHashForExternalMode(
                        _userOp, validUntil, validAfter, tokenAddress, exchangeRate, appliedFeeMarkup
                    ).toEthSignedMessageHash()
                ).tryRecover(signature)
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

            // Prepare context for postOp
            bytes memory context = abi.encode(
                _userOp.sender, tokenAddress, preOpGasApproximation, executionGasLimit, exchangeRate, appliedFeeMarkup
            );
            return (context, validationData);
        }

        // This should never be reached due to the mode check above
        revert InvalidPaymasterMode();
    }

    // Private non-view functions

    /**
     * @notice Internal function to withdraw ERC20 tokens
     * @param _token The token to withdraw
     * @param _target The address to send the tokens to
     * @param _amount The amount of tokens to withdraw
     */
    function _withdrawERC20(IERC20 _token, address _target, uint256 _amount) private {
        if (_target == address(0)) {
            revert InvalidWithdrawalAddress();
        }
        SafeTransferLib.safeTransfer(address(_token), _target, _amount);
        emit TokensWithdrawn(address(_token), _target, msg.sender, _amount);
    }

    /**
     * @notice Internal function to add a supported token
     * @param _token The token address
     * @param _feeMarkup The fee markup for the token
     * @param _oracleConfig The oracle configuration for the token
     */
    function _addSupportedToken(address _token, uint48 _feeMarkup, IOracleHelper.TokenOracleConfig memory _oracleConfig)
        private
    {
        if (_token == address(0)) {
            revert InvalidTokenAddress();
        }
        if (_feeMarkup > MAX_FEE_MARKUP) {
            revert FeeMarkupTooHigh();
        }
        if (tokenConfigs[_token].isEnabled) {
            revert TokenAlreadySupported();
        }

        tokenConfigs[_token] = TokenConfig({feeMarkup: _feeMarkup, isEnabled: true});

        _updateTokenOracleConfig(_token, _oracleConfig);
        emit TokenAdded(_token, _feeMarkup, _oracleConfig);
    }

    // No private view/pure functions in this contract
}
