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
    // @notice If we add caching logic then cacheTimeToLive goes here. But cachedPrice itself will go in different storage.

    struct NativeOracleConfig {
        // The maximum acceptable age of the price oracle round (price expiry)
        uint48 maxOracleRoundAge;
        // Number of decimals for the native asset. Usually 18.
        uint8 nativeAssetDecimals;
    }

    // Events
    event TokenOracleConfigUpdated(address indexed token, TokenOracleConfig newConfig);
    event NativeOracleConfigUpdated(NativeOracleConfig newConfig);

    // Errors
    error ArrayLengthMismatch();
    error InvalidOracleAddress();
    error InvalidMaxOracleRoundAge();
}
