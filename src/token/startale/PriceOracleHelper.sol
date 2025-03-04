// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {IOracle} from "../../interfaces/IOracle.sol";
import {CommonStructs} from "./common/CommonStructs.sol";

abstract contract PriceOracleHelper is CommonStructs {
    struct NativeOracleConfig {
        // The maximum acceptable age of the price oracle round (price expiry)
        uint256 maxOracleRoundAge;
        // Number of decimals for the native asset price
        uint8 nativeAssetDecimals;
    }

    IOracle public nativeAssetToUsdOracle; // ETH -> USD price oracle
    NativeOracleConfig public nativeOracleConfig;
    mapping(address => TokenOracleConfig) public tokenOracleConfigurations;

    constructor(
        address _nativeAssetToUsdOracle,
        uint256 _nativeAssetMaxOracleRoundAge,
        uint8 _nativeAssetDecimals,
        // Above 3 can be combined to just accept one struct from child
        address[] memory _tokens,
        TokenInfo[] memory _tokenConfigs
    ) {
        nativeAssetToUsdOracle = IOracle(_nativeAssetToUsdOracle);

        nativeOracleConfig = NativeOracleConfig({
            maxOracleRoundAge: _nativeAssetMaxOracleRoundAge,
            nativeAssetDecimals: _nativeAssetDecimals
        });

        for (uint256 i = 0; i < _tokens.length; i++) {
            // Todo: _validateTokenInfo
            tokenOracleConfigurations[_tokens[i]] = _tokenConfigs[i].oracleConfig;
        }
    }
}
