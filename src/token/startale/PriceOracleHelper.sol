// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {IOracle} from "../../interfaces/IOracle.sol";
import {IOracleHelper} from "../../interfaces/IOracleHelper.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/**
 * @title PriceOracleHelper
 * @notice Abstract contract providing price oracle functionality for tokens
 * @dev Manages oracle configurations and provides price conversion utilities
 */
abstract contract PriceOracleHelper {
    // Custom errors
    error NoOracleConfiguredForToken(address token);
    error PriceShouldBePositive();
    error IncompleteRound();
    error StalePrice();
    error OracleDecimalsMismatch();
    error SequencerDown();
    error GracePeriodNotOver();

    uint256 private constant GRACE_PERIOD_TIME = 3600;

    // State variables
    IOracle public nativeAssetToUsdOracle; // ETH -> USD price oracle
    IOracle public sequencerUptimeOracle; // Sequencer uptime oracle
    uint8 internal nativeAssetToUsdOracleDecimals;
    IOracleHelper.NativeOracleConfig public nativeOracleConfig;
    mapping(address => IOracleHelper.TokenOracleConfig) public tokenOracleConfigurations;

    /**
     * @notice Initializes the oracle helper with native and token oracle configurations
     * @param _nativeAssetToUsdOracle Address of the native asset to USD oracle
     * @param _sequencerUptimeOracle Address of the sequencer uptime oracle
     * @param _nativeOracleConfig Configuration for the native asset oracle
     * @param _tokens Array of token addresses to configure
     * @param _tokenOracleConfigs Array of token oracle configurations
     */
    constructor(
        address _nativeAssetToUsdOracle,
        address _sequencerUptimeOracle,
        IOracleHelper.NativeOracleConfig memory _nativeOracleConfig,
        address[] memory _tokens,
        IOracleHelper.TokenOracleConfig[] memory _tokenOracleConfigs
    ) {
        if (_tokens.length != _tokenOracleConfigs.length) {
            revert IOracleHelper.ArrayLengthMismatch();
        }

        nativeAssetToUsdOracle = IOracle(_nativeAssetToUsdOracle);
        sequencerUptimeOracle = IOracle(_sequencerUptimeOracle);
        nativeOracleConfig = _nativeOracleConfig;
        nativeAssetToUsdOracleDecimals = nativeAssetToUsdOracle.decimals();

        for (uint256 i = 0; i < _tokens.length; i++) {
            _setTokenOracleConfig(_tokens[i], _tokenOracleConfigs[i]);
        }
    }

    // External functions first (no state-modifying external functions in this contract)

    // External view functions
    /**
     * @notice Gets the oracle configuration for a specific token
     * @param _token The token address
     * @return The oracle configuration
     */
    function getTokenOracleConfig(address _token) external view returns (IOracleHelper.TokenOracleConfig memory) {
        return tokenOracleConfigurations[_token];
    }

    // Public functions next (no state-modifying public functions in this contract)

    // Public view functions
    /**
     * @notice Calculates the exchange rate of a token to the native asset
     * @dev Returns the number of tokens per one native token (in wei)
     * @param _token The token address
     * @return exchangeRate The exchange rate of the token to the native asset
     */
    function getExchangeRate(address _token) public view returns (uint256 exchangeRate) {
        IOracleHelper.TokenOracleConfig memory config = tokenOracleConfigurations[_token];

        if (address(config.tokenOracle) == address(0)) {
            revert NoOracleConfiguredForToken(_token);
        }

        uint8 tokenOracleDecimals = IOracle(config.tokenOracle).decimals();

        // If it is set to zero(which is allowed), we don't need to check the sequencer uptime because it is not L2 like arbitrum, optimism, base or soneium.
        if (sequencerUptimeOracle != IOracle(address(0))) {
            (
                /*uint80 roundID*/
                ,
                int256 answer,
                uint256 startedAt,
                /*uint256 updatedAt*/
                ,
                /*uint80 answeredInRound*/
            ) = sequencerUptimeOracle.latestRoundData();

            // Answer == 0: Sequencer is up
            // Answer == 1: Sequencer is down
            bool isSequencerUp = answer == 0;
            if (!isSequencerUp) {
                revert SequencerDown();
            }

            // Make sure the grace period has passed after the
            // sequencer is back up.
            uint256 timeSinceUp = block.timestamp - startedAt;
            if (timeSinceUp <= GRACE_PERIOD_TIME) {
                revert GracePeriodNotOver();
            }
        }

        uint256 tokenPrice = fetchPrice(config.tokenOracle, config.maxOracleRoundAge);
        uint256 nativePrice = fetchPrice(nativeAssetToUsdOracle, nativeOracleConfig.maxOracleRoundAge);

        if (tokenOracleDecimals > nativeAssetToUsdOracleDecimals) {
            nativePrice *= 10 ** (tokenOracleDecimals - nativeAssetToUsdOracleDecimals);
        } else if (tokenOracleDecimals < nativeAssetToUsdOracleDecimals) {
            tokenPrice *= 10 ** (nativeAssetToUsdOracleDecimals - tokenOracleDecimals);
        }

        // Calculate: (nativePrice * 10^tokenDecimals) / tokenPrice
        exchangeRate = (nativePrice * 10 ** IERC20Metadata(_token).decimals()) / tokenPrice;
    }

    // Internal functions next, state-modifying first

    /**
     * @notice Updates the oracle configuration for a specific token
     * @dev Emits TokenOracleConfigUpdated event
     * @param _token The token address
     * @param _newConfig The new oracle configuration
     */
    function _updateTokenOracleConfig(address _token, IOracleHelper.TokenOracleConfig memory _newConfig) internal {
        _setTokenOracleConfig(_token, _newConfig);
        emit IOracleHelper.TokenOracleConfigUpdated(_token, _newConfig);
    }

    /**
     * @notice Updates the native token oracle configuration
     * @dev Emits NativeOracleConfigUpdated event
     * @param _newConfig The new oracle configuration
     */
    function _updateNativeOracleConfig(IOracleHelper.NativeOracleConfig calldata _newConfig) internal {
        nativeOracleConfig = _newConfig;
        emit IOracleHelper.NativeOracleConfigUpdated(_newConfig);
    }

    // Internal view functions
    /**
     * @notice Fetches the latest price from the given Oracle
     * @dev Validates price and freshness of the oracle data
     * @param _oracle The Oracle contract to fetch the price from
     * @param _maxOracleRoundAge The maximum acceptable age of the price oracle round
     * @return price The latest price fetched from the Oracle
     */
    function fetchPrice(IOracle _oracle, uint48 _maxOracleRoundAge) internal view returns (uint256 price) {
        (uint80 roundId, int256 answer,, uint256 updatedAt, uint80 answeredInRound) = _oracle.latestRoundData();

        if (answer <= 0) {
            revert PriceShouldBePositive();
        }
        if (updatedAt < block.timestamp - _maxOracleRoundAge) {
            revert IncompleteRound();
        }
        if (answeredInRound < roundId) {
            revert StalePrice();
        }

        price = uint256(answer);
    }

    // Private functions last, state-modifying first (this contract only has state-modifying private functions)

    /**
     * @notice Sets the oracle configuration for a specific token
     * @dev Validates the configuration before setting
     * @param _token The token address
     * @param _config The oracle configuration
     */
    function _setTokenOracleConfig(address _token, IOracleHelper.TokenOracleConfig memory _config) private {
        if (address(_config.tokenOracle) == address(0)) {
            revert IOracleHelper.InvalidOracleAddress();
        }
        if (_config.maxOracleRoundAge == 0) {
            revert IOracleHelper.InvalidMaxOracleRoundAge();
        }

        tokenOracleConfigurations[_token] = _config;
    }
}
