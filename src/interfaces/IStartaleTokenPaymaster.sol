// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "@account-abstraction/contracts/core/UserOperationLib.sol";
import { IOracle } from "./IOracle.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IStartaleTokenPaymasterEventsAndErrors } from "./IStartaleTokenPaymasterEventsAndErrors.sol";

interface IStartaleTokenPaymaster is IStartaleTokenPaymasterEventsAndErrors {
    // Modes that paymaster can be used in
    enum PaymasterMode {
        SPONSORED_POSTPAID, // User operation is sponsored by paymaster. Paymaster pays for gas and sponsor pays via a credit card
        EXTERNAL, // Price provided by external service. Authenticated using signature from verifyingSigner/s
        INDEPENDENT // Price queried from oracle. No signature needed from external service.
        // RESERVED, // maybe
        // INDEPENDENT_WITH_PERMIT
    }

    struct TokenOracleConfig {
        // TokenToUSD oracle
        IOracle tokenOracle;

        // The maximum acceptable age of the price oracle round
        uint256 maxOracleRoundAge;

        // decimals

        // caching logic related state variables
    }

    // Struct for storing information about the token
    struct TokenInfo {
        // Review type for feeMarkup
        uint32 feeMarkup;
        TokenOracleConfig oracleConfig;   
    }

    // addSigner
    function addSigner(address signer) external payable;

    // removeSigner
    function removeSigner(address signer) external payable;

    function setUnaccountedGas(uint256 value) external payable;

    function withdrawERC20(IERC20 token, address target, uint256 amount) external;

    function withdrawEth(address payable recipient, uint256 amount) external payable;
}
