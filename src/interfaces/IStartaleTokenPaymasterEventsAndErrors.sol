// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {IPaymaster} from "@account-abstraction/contracts/interfaces/IPaymaster.sol";
import {IOracleHelper} from "./IOracleHelper.sol";

/**
 * @title IStartaleTokenPaymasterEventsAndErrors
 * @notice Interface defining events and errors for the StartaleTokenPaymaster
 * @dev This interface consolidates all events and errors for better organization and reusability
 */
interface IStartaleTokenPaymasterEventsAndErrors {
    // Events

    /**
     * @notice Emitted when ETH is withdrawn from the paymaster
     * @param recipient The address receiving the withdrawn ETH
     * @param amount The amount of ETH withdrawn
     */
    event EthWithdrawn(address indexed recipient, uint256 indexed amount);

    /**
     * @notice Emitted when ETH is received by the contract
     * @param sender The address that sent ETH
     * @param value The amount of ETH received
     */
    event Received(address indexed sender, uint256 value);

    /**
     * @notice Emitted when ERC20 tokens are withdrawn from the paymaster
     * @param token The address of the token being withdrawn
     * @param to The recipient address
     * @param actor The address that initiated the withdrawal
     * @param amount The amount of tokens withdrawn
     */
    event TokensWithdrawn(address indexed token, address indexed to, address indexed actor, uint256 amount);

    /**
     * @notice Emitted when a token's fee markup is updated
     * @param token The address of the token
     * @param newFeeMarkup The new fee markup value
     */
    event TokenFeeMarkupUpdated(address indexed token, uint48 newFeeMarkup);

    /**
     * @notice Emitted when a new token is added to the supported tokens list
     * @param token The address of the token being added
     * @param feeMarkup The fee markup for the token
     * @param oracleConfig The oracle configuration for the token
     */
    event TokenAdded(address indexed token, uint48 feeMarkup, IOracleHelper.TokenOracleConfig oracleConfig);

    /**
     * @notice Emitted when a token is removed from the supported tokens list
     * @param token The address of the token being removed
     */
    event TokenRemoved(address indexed token);

    /**
     * @notice Emitted when a token's oracle configuration is updated
     * @param token The address of the token
     * @param newConfig The new oracle configuration
     */
    event TokenOracleConfigUpdated(address indexed token, IOracleHelper.TokenOracleConfig newConfig);

    /**
     * @notice Emitted when a user's gas fees are paid in tokens
     * @param user The address of the user who executed the operation
     * @param token The token used to pay for gas
     * @param tokenCharge The amount of tokens charged
     * @param appliedMarkup The fee markup applied
     * @param exchangeRate The exchange rate used to calculate the token charge
     */
    event PaidGasInTokens(
        address indexed user, address indexed token, uint256 tokenCharge, uint48 appliedMarkup, uint256 exchangeRate
    );

    // Errors

    /**
     * @notice Error thrown when the paymaster data has an invalid length
     */
    error PaymasterAndDataLengthInvalid();

    /**
     * @notice Error thrown when the paymaster mode is invalid
     * @dev The mode should be 0 (Independent) or 1 (External)
     */
    error PaymasterModeInvalid();

    /**
     * @notice Error thrown when the paymaster signature has an invalid length
     * @dev Signature length should be 64 or 65 bytes
     */
    error PaymasterSignatureLengthInvalid();

    /**
     * @notice Error thrown when the unaccounted gas limit exceeds the maximum allowed value
     */
    error UnaccountedGasTooHigh();

    /**
     * @notice Error thrown when attempting to withdraw to an invalid address
     */
    error InvalidWithdrawalAddress();

    /**
     * @notice Error thrown when a withdrawal transaction fails
     */
    error WithdrawalFailed();

    /**
     * @notice Error thrown when the fee markup exceeds the maximum allowed value
     */
    error FeeMarkupTooHigh();

    /**
     * @notice Error thrown when the lengths of input arrays don't match
     */
    error ArrayLengthMismatch();

    /**
     * @notice Error thrown when an invalid token address is provided
     */
    error InvalidTokenAddress();

    /**
     * @notice Error thrown when attempting to add a token that is already supported
     */
    error TokenAlreadySupported();

    /**
     * @notice Error thrown when attempting to use a token that is not supported
     * @param token The address of the unsupported token
     */
    error TokenNotSupported(address token);

    /**
     * @notice Error thrown when the token price feed fails to provide a valid price
     * @param token The address of the token with the failed price feed
     */
    error TokenPriceFeedErrored(address token);

    /**
     * @notice Error thrown when an invalid paymaster mode is specified
     */
    error InvalidPaymasterMode();

    /**
     * @notice Error thrown when the post-operation gas limit is too low
     */
    error PostOpGasLimitTooLow();

    /**
     * @notice Error thrown when the independent mode specific data is invalid
     */
    error InvalidIndependentModeSpecificData();

    /**
     * @notice Error thrown when token charging fails
     * @param user The user who was being charged
     * @param token The token that was being used
     * @param tokenAmount The amount of tokens that failed to be charged
     */
    error FailedToChargeTokens(address user, address token, uint256 tokenAmount);

    /**
     * @notice Error thrown when an invalid token fees treasury address is provided
     */
    error InvalidTokenFeesTreasury();

    /**
     * @notice Error thrown when an invalid exchange rate is provided
     * @param tokenAddress The address of the token with the invalid exchange rate
     */
    error InvalidExchangeRate(address tokenAddress);
}
