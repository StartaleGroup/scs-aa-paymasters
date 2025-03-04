    // SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {IOracle} from "../../../interfaces/IOracle.sol";

contract CommonStructs {
    struct TokenOracleConfig {
        // TokenToUSD oracle
        IOracle tokenOracle;
        // The maximum acceptable age of the price oracle round
        uint256 maxOracleRoundAge;
    }

    // decimals

    // caching logic related state variables

    // Struct for storing information about the token
    struct TokenInfo {
        // Review type for feeMarkup
        uint32 feeMarkup;
        TokenOracleConfig oracleConfig;
    }
}
