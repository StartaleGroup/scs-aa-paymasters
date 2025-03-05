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
// import SwapRoputer

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

    // Denominator to prevent precision errors when applying fee markup
    uint256 private constant FEE_MARKUP_DENOMINATOR = 1e6;

    uint256 private constant MAX_FEE_MARKUP = 2e6;

    // Limit for unaccounted gas cost
    uint256 private constant UNACCOUNTED_GAS_LIMIT = 150_000;

    // Todo: can do
    // Constants for the paymaster data length in case of different modes.

    // fee collector address
    address public tokenFeesTreasury;

    uint256 public unaccountedGas;

    // Below could be part of swap helper contract
    /**
     * @notice The native token wrapper used by the swap router.
     */
    // IWETH public immutable wrappedNativeToken;

    /**
     * @notice The contract to execute swaps against.
     */
    // ISwapRouter public swapRouter;

    
    mapping(address => TokenConfig) private tokenConfigs;

    constructor(
        address _owner,
        address _entryPoint,
        address[] memory _signers,
        address _tokenFeesTreasury,
        uint256 _unaccountedGas,
        address _nativeAssetToUsdOracle,
        uint48 _nativeAssetmaxOracleRoundAge,
        uint8 _nativeAssetDecimals,
        address[] memory _independentTokens,
        uint48[] memory _feeMarkups,
        IOracleHelper.TokenOracleConfig[] memory _tokenOracleConfigs
    )
        BasePaymaster(_owner, IEntryPoint(_entryPoint))
        MultiSigners(_signers)
        PriceOracleHelper(
            _nativeAssetToUsdOracle,
            IOracleHelper.NativeOracleConfig({
                maxOracleRoundAge: _nativeAssetmaxOracleRoundAge,
                nativeAssetDecimals: _nativeAssetDecimals
            }),
            _independentTokens,
            _tokenOracleConfigs
        )
    {
        if (_independentTokens.length != _feeMarkups.length || _independentTokens.length != _tokenOracleConfigs.length) {
            revert ArrayLengthMismatch();
        }

        tokenFeesTreasury = _tokenFeesTreasury;
        unaccountedGas = _unaccountedGas;

        for (uint256 i = 0; i < _independentTokens.length; i++) {
            _addSupportedToken(_independentTokens[i], _feeMarkups[i], _tokenOracleConfigs[i]);
        }
    }

    // Todo: Some other internal methods like
    // _validateIndependentMode
    // _validateExternalMode
    // _validateSponsoredPostpaidMode
    // ...
    // _createPostOpContext
    // _parsePostOpContext
    // _parseConfig // Based on mode

    // Todo: Methods to update token oracle config
    // Todo: Methods to add new independent token support. -> oracle config, fee markup config, etc.
    // Todo: Methods to update configuration related to native token oracle

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
    ) internal override returns (bytes memory, uint256) {
        return ("", 0);
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
    {}

    /**
     * @notice Gets the cost in amount of tokens.
     * @param _actualGasCost The gas consumed by the userOperation.
     * @param _postOpGas The gas overhead of transfering the ERC-20 when making the postOp payment.
     * @param _actualUserOpFeePerGas The actual gas cost of the userOperation.
     * @param _exchangeRate The token exchange rate - how many tokens one full ETH (1e18 wei) is worth.
     * @return uint256 The gasCost in token units.
     */
    function getCostInToken(
        uint256 _actualGasCost,
        uint256 _postOpGas,
        uint256 _actualUserOpFeePerGas,
        uint256 _exchangeRate
    ) public pure returns (uint256) {
        return ((_actualGasCost + (_postOpGas * _actualUserOpFeePerGas)) * _exchangeRate) / 1e18;
    }

    /**
     * @dev Adds a new supported token with its configuration
     * @param token The token address
     * @param feeMarkup The fee markup for the token
     * @param oracleConfig The oracle configuration for the token
     */
    function addSupportedToken(
        address token,
        uint48 feeMarkup,
        IOracleHelper.TokenOracleConfig calldata oracleConfig
    ) external onlyOwner {
        _addSupportedToken(token, feeMarkup, oracleConfig);
    }

    /**
     * @dev Internal function to add a supported token
     */
    function _addSupportedToken(
        address token,
        uint48 feeMarkup,
        IOracleHelper.TokenOracleConfig memory oracleConfig
    ) private {
        if (token == address(0)) revert InvalidTokenAddress();
        if (feeMarkup > MAX_FEE_MARKUP) revert FeeMarkupTooHigh();
        if (tokenConfigs[token].isEnabled) revert TokenAlreadySupported();

        tokenConfigs[token] = TokenConfig({
            feeMarkup: feeMarkup,
            isEnabled: true
        });

        _updateTokenOracleConfig(token, oracleConfig);
        emit TokenAdded(token, feeMarkup, oracleConfig);
    }

    /**
     * @dev Removes a supported token
     * @param token The token address to remove
     */
    function removeSupportedToken(address token) external onlyOwner {
        if (!tokenConfigs[token].isEnabled) revert TokenNotSupported();

        delete tokenConfigs[token];
        delete tokenOracleConfigurations[token];
        emit TokenRemoved(token);
    }

    /**
     * @dev Updates the oracle configuration for a specific token
     * @param token The token address
     * @param newOracleConfig The new oracle configuration
     */
    function updateTokenOracleConfig(
        address token,
        IOracleHelper.TokenOracleConfig calldata newOracleConfig
    ) external onlyOwner {
        if (!tokenConfigs[token].isEnabled) revert TokenNotSupported();
        
        _updateTokenOracleConfig(token, newOracleConfig);
        emit TokenOracleConfigUpdated(token, newOracleConfig);
    }

    /**
     * @dev Updates the fee markup for a specific token
     * @param token The token address to update
     * @param newFeeMarkup The new fee markup value
     */
    function updateTokenFeeMarkup(address token, uint48 newFeeMarkup) external onlyOwner {
        if (!tokenConfigs[token].isEnabled) revert TokenNotSupported();
        if (newFeeMarkup > MAX_FEE_MARKUP) revert FeeMarkupTooHigh();
        
        tokenConfigs[token].feeMarkup = newFeeMarkup;
        emit TokenFeeMarkupUpdated(token, newFeeMarkup);
    }

    /**
     * @dev Checks if a token is supported and enabled
     * @param token The token address to check
     * @return bool True if token is supported and enabled
     */
    function isTokenSupported(address token) external view returns (bool) {
        return tokenConfigs[token].isEnabled;
    }

    /**
     * @dev Gets the fee markup for a specific token
     * @param token The token address
     * @return uint48 The fee markup value
     */
    function getTokenFeeMarkup(address token) external view returns (uint48) {
        return tokenConfigs[token].feeMarkup;
    }
}
