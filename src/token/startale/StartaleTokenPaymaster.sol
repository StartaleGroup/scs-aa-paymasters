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
import {CommonStructs} from "./common/CommonStructs.sol";
import {IStartaleTokenPaymaster} from "../../interfaces/IStartaleTokenPaymaster.sol";
import {IStartaleTokenPaymasterEventsAndErrors} from "../../interfaces/IStartaleTokenPaymasterEventsAndErrors.sol";
import {IOracle} from "../../interfaces/IOracle.sol";
import {IWETH} from "@uniswap/swap-router-contracts/contracts/interfaces/IWETH.sol";
// import SwapRoputer

// Maybe add PrinceOracleHelper base
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

    mapping(address => uint48) public independentTokenFeeMarkup;

    constructor(
        address _owner,
        address _entryPoint,
        address[] memory _signers,
        address _tokenFeesTreasury,
        uint256 _unaccountedGas,
        address _nativeAssetToUsdOracle, // IOracle
        uint256 _nativeAssetmaxOracleRoundAge,
        uint8 _nativeAssetDecimals,
        address[] memory _independentTokens,
        TokenInfo[] memory _independentTokenConfigs // Consists of fee markup and oracle config
    )
        BasePaymaster(_owner, IEntryPoint(_entryPoint))
        MultiSigners(_signers)
        PriceOracleHelper(
            _nativeAssetToUsdOracle,
            _nativeAssetmaxOracleRoundAge,
            _nativeAssetDecimals,
            _independentTokens,
            _independentTokenConfigs
        )
    {
        // Todo: Check constructor args
        tokenFeesTreasury = _tokenFeesTreasury;
        unaccountedGas = _unaccountedGas;

        // put these in oracle helper config
        // _nativeAssetToUsdOracle, _nativeAssetPriceExpiryDuration, _nativeAssetDecimals

        for (uint256 i = 0; i < _independentTokens.length; i++) {
            // Todo: validations
            independentTokenFeeMarkup[_independentTokens[i]] = _independentTokenConfigs[i].feeMarkup;
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
}
