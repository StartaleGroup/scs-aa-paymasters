// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {IOracle} from "../../interfaces/IOracle.sol";
import {IOracleHelper} from "../../interfaces/IOracleHelper.sol";

abstract contract PriceOracleHelper {
    IOracle public nativeAssetToUsdOracle; // ETH -> USD price oracle
    IOracleHelper.NativeOracleConfig public nativeOracleConfig;
    mapping(address => IOracleHelper.TokenOracleConfig) public tokenOracleConfigurations;

    constructor(
        address _nativeAssetToUsdOracle,
        IOracleHelper.NativeOracleConfig memory _nativeOracleConfig,
        address[] memory _tokens,
        IOracleHelper.TokenOracleConfig[] memory _tokenOracleConfigs
    ) {
        if (_tokens.length != _tokenOracleConfigs.length) revert IOracleHelper.ArrayLengthMismatch();
        
        nativeAssetToUsdOracle = IOracle(_nativeAssetToUsdOracle);
        nativeOracleConfig = _nativeOracleConfig;

        for (uint256 i = 0; i < _tokens.length; i++) {
            _setTokenOracleConfig(_tokens[i], _tokenOracleConfigs[i]);
        }
    }

    /**
     * @dev Updates the oracle configuration for a specific token
     * @param token The token address
     * @param newConfig The new oracle configuration
     */
    function _updateTokenOracleConfig(
        address token,
        IOracleHelper.TokenOracleConfig memory newConfig
    ) internal {
        _setTokenOracleConfig(token, newConfig);
        emit IOracleHelper.TokenOracleConfigUpdated(token, newConfig);
    }

    /**
     * @dev Updates the native token oracle configuration
     * @param newConfig The new oracle configuration
     */
    function _updateNativeOracleConfig(
        IOracleHelper.NativeOracleConfig calldata newConfig
    ) internal {
        nativeOracleConfig = newConfig;
        emit IOracleHelper.NativeOracleConfigUpdated(IOracleHelper.TokenOracleConfig({
            tokenOracle: nativeAssetToUsdOracle,
            maxOracleRoundAge: newConfig.maxOracleRoundAge
        }));
    }

    /**
     * @dev Sets the oracle configuration for a specific token
     * @param token The token address
     * @param config The oracle configuration
     */
    function _setTokenOracleConfig(
        address token,
        IOracleHelper.TokenOracleConfig memory config
    ) private {
        if (address(config.tokenOracle) == address(0)) revert IOracleHelper.InvalidOracleAddress();
        if (config.maxOracleRoundAge == 0) revert IOracleHelper.InvalidMaxOracleRoundAge();
        
        tokenOracleConfigurations[token] = config;
    }

    /**
     * @dev Gets the oracle configuration for a specific token
     * @param token The token address
     * @return The oracle configuration
     */
    function getTokenOracleConfig(address token) external view returns (IOracleHelper.TokenOracleConfig memory) {
        return tokenOracleConfigurations[token];
    }
}
