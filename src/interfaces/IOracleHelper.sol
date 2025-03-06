// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {IOracle} from "./IOracle.sol";

interface IOracleHelper {
    // Structs
    struct TokenOracleConfig {
        // TokenToUSD oracle
        IOracle tokenOracle;
        // The maximum acceptable age of the price oracle round
        uint48 maxOracleRoundAge;
    }
    // Review
    // We could add token oracle decimals here

    // If we add caching logic then cacheTimeToLive goes here.
    // But cachedPrice will go in different storage.

    struct NativeOracleConfig {
        // The maximum acceptable age of the price oracle round (price expiry)
        uint48 maxOracleRoundAge;
        // Number of decimals for the native asset price
        // Note: could be deciamls or 10^^decimals. // TBD
        uint8 nativeAssetDecimals;
    }

    // Events
    event TokenOracleConfigUpdated(address indexed token, TokenOracleConfig newConfig);
    event NativeOracleConfigUpdated(TokenOracleConfig newConfig);

    // Errors
    error ArrayLengthMismatch();
    error InvalidOracleAddress();
    error InvalidMaxOracleRoundAge();
}
