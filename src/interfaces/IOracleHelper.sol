// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {IOracle} from "./IOracle.sol";

/**
 * @title IOracleHelper
 * @notice Interface for managing token and native asset oracle configurations
 * @dev Provides structures and events for price oracle handling
 */
interface IOracleHelper {
    // Structs

    /**
     * @notice Configuration for a token's price oracle
     * @param tokenOracle The oracle contract for token to USD price
     * @param maxOracleRoundAge The maximum acceptable age (in seconds) of the price oracle round
     */
    struct TokenOracleConfig {
        IOracle tokenOracle;
        uint48 maxOracleRoundAge;
    }
    // @dev If we add caching logic then cacheTimeToLive would go here. But cachedPrice itself would go in different storage.

    /**
     * @notice Configuration for the native asset's price oracle
     * @param maxOracleRoundAge The maximum acceptable age (in seconds) of the price oracle round
     * @param nativeAssetDecimals Number of decimals for the native asset (usually 18)
     */
    struct NativeOracleConfig {
        uint48 maxOracleRoundAge;
        uint8 nativeAssetDecimals;
    }

    // Events

    /**
     * @notice Emitted when a token's oracle configuration is updated
     * @param token The address of the token whose oracle configuration was updated
     * @param newConfig The new oracle configuration
     */
    event TokenOracleConfigUpdated(address indexed token, TokenOracleConfig newConfig);

    /**
     * @notice Emitted when the native asset's oracle configuration is updated
     * @param newConfig The new oracle configuration
     */
    event NativeOracleConfigUpdated(NativeOracleConfig newConfig);

    /**
     * @notice Emitted when the native asset to USD oracle is updated
     * @param newNativeAssetToUsdOracle The new native asset to USD oracle address
     */
    event NativeAssetToUsdOracleUpdated(address newNativeAssetToUsdOracle);

    // Errors

    /**
     * @notice Error thrown when array lengths don't match in initialization or updates
     * @dev Typically occurs when token addresses and configurations arrays have different lengths
     */
    error ArrayLengthMismatch();

    /**
     * @notice Error thrown when an invalid oracle address is provided
     * @dev Typically occurs when the oracle address is the zero address
     */
    error InvalidOracleAddress();

    /**
     * @notice Error thrown when an invalid maximum oracle round age is provided
     * @dev Typically occurs when the value is zero or unreasonably large
     */
    error InvalidMaxOracleRoundAge();
}
