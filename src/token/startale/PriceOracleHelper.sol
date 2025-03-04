// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {IOracle} from "../../interfaces/IOracle.sol";

abstract contract PriceOracleHelper {
    struct NativeOracleConfig {
        // The maximum acceptable age of the price oracle round (price expiry)
        uint256 maxOracleRoundAge;
        // Number of decimals for the native asset price
        uint8 nativeAssetDecimals;
    }

    struct TokenOracleConfig {
        // TokenToUSD oracle
        IOracle tokenOracle;

        // The maximum acceptable age of the price oracle round
        uint256 maxOracleRoundAge;

        // decimals

        // caching logic related state variables
    }

    IOracle public nativeAssetToUsdOracle; // ETH -> USD price oracle
    NativeOracleConfig public nativeOracleConfig;
    mapping (address => TokenOracleConfig) public tokenOracleConfigurations;


    constructor(
        address _nativeAssetToUsdOracle,
        uint256 _nativeAssetMaxOracleRoundAge,
        uint8 _nativeAssetDecimals,
        address[] memory _tokens,
        TokenOracleConfig[] memory _tokenOracleConfigs
    ) {
        nativeAssetToUsdOracle = IOracle(_nativeAssetToUsdOracle);
        
        nativeOracleConfig = NativeOracleConfig({
            maxOracleRoundAge: _nativeAssetMaxOracleRoundAge,
            nativeAssetDecimals: _nativeAssetDecimals
        });

        for (uint256 i = 0; i < _tokens.length; i++) {
            // Todo: _validateTokenInfo
            tokenOracleConfigurations[_tokens[i]] = _tokenOracleConfigs[i];
        }
    }

}