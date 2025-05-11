// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {UserOperationLib} from "@account-abstraction/contracts/core/UserOperationLib.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IStartaleTokenPaymasterEventsAndErrors} from "./IStartaleTokenPaymasterEventsAndErrors.sol";
import {IOracleHelper} from "./IOracleHelper.sol";

/**
 * @title IStartaleTokenPaymaster
 * @notice Interface for the Startale Token Paymaster that supports multiple ERC20 tokens
 * @dev Extends IStartaleTokenPaymasterEventsAndErrors to include main functionality
 */
interface IStartaleTokenPaymaster is IStartaleTokenPaymasterEventsAndErrors {
    // Structs

    /**
     * @notice Configuration for a supported token
     * @dev Holds fee markup and enabled status
     * @param feeMarkup The fee markup applied when using this token for gas payments
     * @param isEnabled Whether the token is currently enabled for use
     */
    struct TokenConfig {
        uint48 feeMarkup;
        bool isEnabled;
    }

    /**
     * @notice Operating modes of the paymaster
     * @param EXTERNAL Price provided by external service, authenticated using signature from verifying signers
     * @param INDEPENDENT Price queried from oracle directly, no signature needed from external service
     */
    enum PaymasterMode {
        EXTERNAL,
        INDEPENDENT
    }

    /**
     * @notice Adds a new authorized signer for validating external mode operations
     * @param _signer The address to add as a signer
     */
    function addSigner(address _signer) external payable;

    /**
     * @notice Removes an authorized signer
     * @param _signer The signer address to remove
     */
    function removeSigner(address _signer) external payable;

    /**
     * @notice Sets the unaccounted gas value used for post-operation calculations
     * @param _value The new unaccounted gas value
     */
    function setUnaccountedGas(uint256 _value) external payable;

    /**
     * @notice Withdraws ERC20 tokens from the paymaster
     * @dev Can be used to recover accidentally sent tokens
     * @param _token The token contract to withdraw from
     * @param _target The recipient address
     * @param _amount The amount to withdraw
     */
    function withdrawERC20(IERC20 _token, address _target, uint256 _amount) external;

    /**
     * @notice Withdraws ETH from the paymaster
     * @param _recipient The recipient address
     * @param _amount The amount of ETH to withdraw
     */
    function withdrawEth(address payable _recipient, uint256 _amount) external payable;

    /**
     * @notice Updates the fee markup for a supported token
     * @param _token The token address
     * @param _newFeeMarkup The new fee markup value
     */
    function updateTokenFeeMarkup(address _token, uint48 _newFeeMarkup) external;

    /**
     * @notice Gets the current fee markup for a token
     * @param _token The token address
     * @return The fee markup value
     */
    function getTokenFeeMarkup(address _token) external view returns (uint48);

    /**
     * @notice Adds a new token to the list of supported tokens
     * @param _token The token address to add
     * @param _feeMarkup The fee markup for the token
     * @param _oracleConfig The oracle configuration for the token
     */
    function addSupportedToken(
        address _token,
        uint48 _feeMarkup,
        IOracleHelper.TokenOracleConfig calldata _oracleConfig
    ) external;

    /**
     * @notice Removes a token from the list of supported tokens
     * @param _token The token address to remove
     */
    function removeSupportedToken(address _token) external;

    /**
     * @notice Updates the oracle configuration for a token
     * @param _token The token address
     * @param _newOracleConfig The new oracle configuration
     */
    function updateTokenOracleConfig(address _token, IOracleHelper.TokenOracleConfig calldata _newOracleConfig)
        external;

    /**
     * @notice Checks if a token is supported and enabled
     * @param _token The token address to check
     * @return True if the token is supported and enabled, false otherwise
     */
    function isTokenSupported(address _token) external view returns (bool);
}
