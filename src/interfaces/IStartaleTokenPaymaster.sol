// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "@account-abstraction/contracts/core/UserOperationLib.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IStartaleTokenPaymasterEventsAndErrors} from "./IStartaleTokenPaymasterEventsAndErrors.sol";
import {IOracleHelper} from "./IOracleHelper.sol";

interface IStartaleTokenPaymaster is IStartaleTokenPaymasterEventsAndErrors {
    // Structs
    struct TokenConfig {
        // Fee related configurations
        uint48 feeMarkup;
        bool isEnabled;
    }

    // Modes that paymaster can be used in
    enum PaymasterMode {
        SPONSORED_POSTPAID, // User operation is sponsored by paymaster. Paymaster pays for gas and sponsor pays via a credit card
        EXTERNAL, // Price provided by external service. Authenticated using signature from verifyingSigner/s
        INDEPENDENT // Price queried from oracle. No signature needed from external service.
            // RESERVED, // maybe
            // INDEPENDENT_WITH_PERMIT

    }

    // addSigner
    function addSigner(address signer) external payable;

    // removeSigner
    function removeSigner(address signer) external payable;

    function setUnaccountedGas(uint256 value) external payable;

    function withdrawERC20(IERC20 token, address target, uint256 amount) external;

    function withdrawEth(address payable recipient, uint256 amount) external payable;

    function updateTokenFeeMarkup(address token, uint48 newFeeMarkup) external;

    function getTokenFeeMarkup(address token) external view returns (uint48);

    function addSupportedToken(
        address token,
        uint48 feeMarkup,
        IOracleHelper.TokenOracleConfig calldata oracleConfig
    ) external;

    function removeSupportedToken(address token) external;

    function updateTokenOracleConfig(
        address token,
        IOracleHelper.TokenOracleConfig calldata newOracleConfig
    ) external;

    function isTokenSupported(address token) external view returns (bool);
}
