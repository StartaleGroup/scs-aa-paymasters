// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

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
 * @notice ERC20 Token Paymaster for Startale that supports multiple tokens.
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

    // Denominator to prevent precision errors when applying fee markup
    uint256 private constant FEE_MARKUP_DENOMINATOR = 1e6;

    uint256 private constant MAX_FEE_MARKUP = 2e6;

    // Limit for unaccounted gas cost
    uint256 private constant UNACCOUNTED_GAS_LIMIT = 150_000;

    // Fee collector address
    address public tokenFeesTreasury;

    // Note: Type may be updated to pack efficiently.
    uint256 public unaccountedGas;

    /// @notice This is a mapping for independent tokens to their activated state and fee markup.
    /// The actual information on token oracle config is stored in the parent contract(OracleHelper) in a different mapping.
    mapping(address => TokenConfig) private tokenConfigs;

    constructor(
        address _owner,
        address _entryPoint,
        address[] memory _signers,
        address _tokenFeesTreasury,
        uint256 _unaccountedGas,
        address _nativeAssetToUsdOracle,
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

        if (_tokenFeesTreasury == address(0)) revert InvalidTokenFeesTreasury();
        tokenFeesTreasury = _tokenFeesTreasury;

        if (_unaccountedGas > UNACCOUNTED_GAS_LIMIT) {
            revert UnaccountedGasTooHigh();
        }
        unaccountedGas = _unaccountedGas;

        for (uint256 i = 0; i < _independentTokens.length; i++) {
            _addSupportedToken(_independentTokens[i], _feeMarkupsForIndependentTokens[i], _tokenOracleConfigs[i]);
        }
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

    /**
     * @dev Sets the token fees treasury address.
     * @param _tokenFeesTreasury The address of the token fees treasury.
     */
    function setTokenFeesTreasury(address _tokenFeesTreasury) external payable onlyOwner {
        // @dev We can add a check here to ensure the treasury is a valid address.
        // @notice It is allowed to be a contract.
        if (_tokenFeesTreasury == address(0)) revert InvalidTokenFeesTreasury();
        tokenFeesTreasury = _tokenFeesTreasury;
    }

    /**
     * @dev pull tokens out of paymaster in case they were sent to the paymaster at any point.
     * @dev This could happen if someone accidently sends ERC20 to paymaster address and we need to recover them.
     * @notice tokenFeeTreasury could also be set to paymaster address address itself. In case of manual withdraw to recharge we would use this method
     * @notice we could also add withdrawMultipleERC20() method to batch withdraw several tokens.
     * @param token the token deposit to withdraw
     * @param target address to send to
     * @param amount amount to withdraw
     */
    function withdrawERC20(IERC20 token, address target, uint256 amount) external onlyOwner nonReentrant {
        _withdrawERC20(token, target, amount);
    }

    /**
     * @dev Internal function to withdraw ERC20 tokens.
     * @param token The token to withdraw.
     * @param target The address to send the tokens to.
     * @param amount The amount of tokens to withdraw.
     */
    function _withdrawERC20(IERC20 token, address target, uint256 amount) private {
        if (target == address(0)) revert InvalidWithdrawalAddress();
        SafeTransferLib.safeTransfer(address(token), target, amount);
        emit TokensWithdrawn(address(token), target, msg.sender, amount);
    }

    /**
     * @dev Withdraws ETH from the paymaster.
     * @param recipient The address to send the ETH to.
     * @param amount The amount of ETH to withdraw.
     */
    function withdrawEth(address payable recipient, uint256 amount) external payable onlyOwner nonReentrant {
        (bool success,) = recipient.call{value: amount}("");
        if (!success) {
            revert WithdrawalFailed();
        }
        emit EthWithdrawn(recipient, amount);
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
    ) internal view override returns (bytes memory, uint256) {
        (_userOpHash, requiredPreFund);
        (PaymasterMode mode, bytes calldata modeSpecificData) = _userOp.paymasterAndData.parsePaymasterAndData();

        // @dev We only have two modes for now. Change this if we add more modes.
        if (uint8(mode) > 1) {
            revert InvalidPaymasterMode();
        }

        // @dev We need to ensure the postOp gas limit is not too low.
        if (unaccountedGas > _userOp.unpackPostOpGasLimit()) {
            revert PostOpGasLimitTooLow();
        }

        // Save some state to help calculate the expected penalty during postOp
        uint256 preOpGasApproximation = _userOp.preVerificationGas + _userOp.unpackVerificationGasLimit()
            + _userOp.unpackPaymasterVerificationGasLimit();

        uint256 executionGasLimit = _userOp.unpackCallGasLimit() + _userOp.unpackPostOpGasLimit();

        if (mode == PaymasterMode.INDEPENDENT) {
            (address tokenAddress) = modeSpecificData.parseIndependentModeSpecificData();
            // Check length it must be 20 bytes.
            if (modeSpecificData.length != 20) {
                revert InvalidIndependentModeSpecificData();
            }

            // Check if token is supported.
            if (!isTokenSupported(tokenAddress)) {
                revert TokenNotSupported(tokenAddress);
            }

            // @dev Implementation below for validateIndependentMode() -> context, validationData
            uint48 feeMarkup = getTokenFeeMarkup(tokenAddress);

            /// @notice If we want to check balance here, we need to uncomment gasPenalty from above.
            /// @notice We only need to calculate exchange rate if we are checking balance here.
            /// @notice In that case we would calculate max cost in token terms using above exchange rate.
            /// @notice Then we would check if sender has enough balance.
            /// @notice We avoid transferFrom here. So there is no precharge.

            // prepare appropriate context.
            bytes memory context = abi.encode(
                _userOp.sender,
                tokenAddress,
                preOpGasApproximation,
                executionGasLimit,
                uint256(0), // exchangeRate. zero in case we solely rely on postOp to call oracle
                feeMarkup
            );
            uint256 validationData = _packValidationData(false, 0, 0);
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

            // @dev Implementation below for validateExternalMode() -> context, validationData

            // Validate Sig Length
            if (signature.length != 64 && signature.length != 65) {
                revert PaymasterSignatureLengthInvalid();
            }

            // Validate supplied markup is not greater than max markup.
            if (appliedFeeMarkup > MAX_FEE_MARKUP) {
                revert FeeMarkupTooHigh();
            }

            address recoveredSigner = (
                (
                    getHashForExternalMode(
                        _userOp, validUntil, validAfter, tokenAddress, exchangeRate, appliedFeeMarkup
                    ).toEthSignedMessageHash()
                ).tryRecover(signature)
            );

            bool isValidSig = signers[recoveredSigner];

            uint256 validationData = _packValidationData(!isValidSig, validUntil, validAfter);

            // Do not revert if signature is invalid, just return validationData
            if (!isValidSig) {
                return ("", validationData);
            }

            /// @notice If we want to check balance here, we need to uncomment gasPenalty from above.
            /// @notice We only need to use supplied exchange rate if we are checking balance here.
            /// @notice In that case we would calculate max cost in token terms using above exchange rate.
            /// @notice Then we would check if sender has enough balance.
            /// @notice We avoid transferFrom here. So there is no precharge.

            // prepare appropriate context.
            bytes memory context = abi.encode(
                _userOp.sender, tokenAddress, preOpGasApproximation, executionGasLimit, exchangeRate, appliedFeeMarkup
            );
            return (context, validationData);
        }
    }

    /**
     * @dev Generates a hash of the given UserOperation to be signed by the paymaster.
     * @param userOp The UserOperation structure.
     * @param validUntil The timestamp until which the UserOperation is valid.
     * @param validAfter The timestamp after which the UserOperation is valid.
     * @param tokenAddress The address of the token to be used for the UserOperation.
     * @param exchangeRate The exchange rate of the token.
     * @param appliedFeeMarkup The fee markup for the UserOperation.
     * @return The hashed UserOperation data.
     */
    function getHashForExternalMode(
        PackedUserOperation calldata userOp,
        uint48 validUntil,
        uint48 validAfter,
        address tokenAddress,
        uint256 exchangeRate,
        uint48 appliedFeeMarkup
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
                validUntil,
                validAfter,
                tokenAddress,
                exchangeRate,
                appliedFeeMarkup
            )
        );
    }

    /**
     * @dev Handles the post-operation logic after transaction execution.
     * @notice Adjusts gas costs, refunds excess gas, and ensures sufficient paymaster balance.
     * @param context Encoded context passed from `_validatePaymasterUserOp`.
     * @param actualGasCost The actual gas cost incurred.
     * @param actualUserOpFeePerGas The effective gas price used for calculation.
     */
    function _postOp(PostOpMode, bytes calldata context, uint256 actualGasCost, uint256 actualUserOpFeePerGas)
        internal
        override
    {
        // @dev implementation below for parseContext() below
        (
            address sender,
            address tokenAddress,
            uint256 preOpGasApproximation,
            uint256 executionGasLimit,
            uint256 exchangeRate,
            uint48 appliedFeeMarkup
        ) = abi.decode(context, (address, address, uint256, uint256, uint256, uint48));
        uint256 actualGas = actualGasCost / actualUserOpFeePerGas;

        // If exchangeRate is 0, it means it was not set in the validatePaymasterUserOp => independent mode
        // So we need to get the price of the token from the oracle now
        if (exchangeRate == 0) {
            /// @notice try/catch only works for external calls.
            // If we want to throw custom error TokenPriceFeedErrored then we have to make staticcall via assembly and throw based on failiure.
            exchangeRate = getExchangeRate(tokenAddress);
            // if exchangeRate is still 0, it means the token is not supported or something went wrong.
            if (exchangeRate == 0) {
                revert TokenPriceFeedErrored(tokenAddress);
            }
        }

        uint256 executionGasUsed;
        if (actualGas + unaccountedGas > preOpGasApproximation) {
            executionGasUsed = actualGas + unaccountedGas - preOpGasApproximation;
        }

        uint256 expectedPenaltyGas;
        if (executionGasLimit > executionGasUsed) {
            expectedPenaltyGas = (executionGasLimit - executionGasUsed) * 10 / 100;
        }

        // Include unaccountedGas since EP doesn't include this in actualGasCost
        // unaccountedGas = postOpGas + EP overhead gas
        actualGasCost = actualGasCost + ((unaccountedGas + expectedPenaltyGas) * actualUserOpFeePerGas);

        uint256 adjustedGasCost = (actualGasCost * appliedFeeMarkup) / FEE_MARKUP_DENOMINATOR;

        // There is no preCharged amount so we can go ahead and transfer the token now.
        uint256 tokenAmount = (adjustedGasCost * exchangeRate) / (10 ** nativeOracleConfig.nativeAssetDecimals);

        if (SafeTransferLib.trySafeTransferFrom(tokenAddress, sender, tokenFeesTreasury, tokenAmount)) {
            emit PaidGasInTokens(sender, tokenAddress, tokenAmount, appliedFeeMarkup, exchangeRate);
        } else {
            revert FailedToChargeTokens(sender, tokenAddress, tokenAmount);
        }
    }

    /**
     * @dev Adds a new supported token with its configuration
     * @param token The token address
     * @param feeMarkup The fee markup for the token
     * @param oracleConfig The oracle configuration for the token
     */
    function addSupportedToken(address token, uint48 feeMarkup, IOracleHelper.TokenOracleConfig calldata oracleConfig)
        external
        onlyOwner
    {
        _addSupportedToken(token, feeMarkup, oracleConfig);
    }

    /**
     * @dev Internal function to add a supported token
     * @param token The token address
     * @param feeMarkup The fee markup for the token
     * @param oracleConfig The oracle configuration for the token
     */
    function _addSupportedToken(address token, uint48 feeMarkup, IOracleHelper.TokenOracleConfig memory oracleConfig)
        private
    {
        if (token == address(0)) revert InvalidTokenAddress();
        ///@notice We can add a check here to ensure the fee markup is not too low.
        if (feeMarkup > MAX_FEE_MARKUP) revert FeeMarkupTooHigh();
        if (tokenConfigs[token].isEnabled) revert TokenAlreadySupported();

        tokenConfigs[token] = TokenConfig({feeMarkup: feeMarkup, isEnabled: true});

        _updateTokenOracleConfig(token, oracleConfig);
        emit TokenAdded(token, feeMarkup, oracleConfig);
    }

    /**
     * @dev Removes a supported token
     * @param token The token address to remove
     */
    function removeSupportedToken(address token) external onlyOwner {
        if (!tokenConfigs[token].isEnabled) revert TokenNotSupported(token);

        delete tokenConfigs[token];
        delete tokenOracleConfigurations[token];
        emit TokenRemoved(token);
    }

    /**
     * @dev Updates the oracle configuration for a specific token
     * @param token The token address
     * @param newOracleConfig The new oracle configuration
     */
    function updateTokenOracleConfig(address token, IOracleHelper.TokenOracleConfig calldata newOracleConfig)
        external
        onlyOwner
    {
        if (!tokenConfigs[token].isEnabled) revert TokenNotSupported(token);

        _updateTokenOracleConfig(token, newOracleConfig);
    }

    /**
     * @dev Updates the native oracle configuration
     * @param newNativeOracleConfig The new oracle configuration
     */
    function updateNativeOracleConfig(IOracleHelper.NativeOracleConfig calldata newNativeOracleConfig)
        external
        onlyOwner
    {
        _updateNativeOracleConfig(newNativeOracleConfig);
    }

    /**
     * @dev Updates the fee markup for a specific token
     * @param token The token address to update
     * @param newFeeMarkup The new fee markup value
     */
    function updateTokenFeeMarkup(address token, uint48 newFeeMarkup) external onlyOwner {
        if (!tokenConfigs[token].isEnabled) revert TokenNotSupported(token);
        if (newFeeMarkup > MAX_FEE_MARKUP) revert FeeMarkupTooHigh();

        tokenConfigs[token].feeMarkup = newFeeMarkup;
        emit TokenFeeMarkupUpdated(token, newFeeMarkup);
    }

    /**
     * @dev Checks if a token is supported and enabled
     * @param token The token address to check
     * @return bool True if token is supported and enabled
     */
    function isTokenSupported(address token) public view returns (bool) {
        return tokenConfigs[token].isEnabled;
    }

    /**
     * @dev Gets the fee markup for a specific token
     * @param token The token address
     * @return uint48 The fee markup value
     */
    function getTokenFeeMarkup(address token) public view returns (uint48) {
        return tokenConfigs[token].feeMarkup;
    }
}
