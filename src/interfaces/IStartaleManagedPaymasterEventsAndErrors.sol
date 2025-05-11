// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IPaymaster} from "@account-abstraction/contracts/interfaces/IPaymaster.sol";

/**
 * @title IStartaleManagedPaymasterEventsAndErrors
 * @notice Interface defining events and errors for the StartaleManagedPaymaster
 * @dev This interface consolidates all events and errors for better organization and reusability
 */
interface IStartaleManagedPaymasterEventsAndErrors {
    // Errors

    /**
     * @notice Error thrown when the paymaster signature has an invalid length
     * @dev Signature length should be 64 or 65 bytes
     */
    error PaymasterSignatureLengthInvalid();

    /**
     * @notice Error thrown when the signature is potentially malformed
     * @dev This error indicates that the signature is not valid
     */
    error PotentiallyMalformedSignature();

    /**
     * @notice Error thrown when the withdrawal address is invalid
     * @dev The address cannot be the zero address
     */
    error InvalidWithdrawalAddress();

    /**
     * @notice Error thrown when the withdrawal fails
     * @dev The withdrawal cannot be completed
     */
    error WithdrawalFailed();

    // Events

    /**
     * @notice Emitted when ETH is withdrawn from the contract
     * @param recipient The address receiving the withdrawn ETH
     * @param amount The amount withdrawn
     */
    event EthWithdrawn(address indexed recipient, uint256 amount);

    /**
     * @notice Emitted when tokens are withdrawn from the contract
     * @param token The address of the token being withdrawn
     * @param to The recipient address
     * @param actor The address that initiated the withdrawal
     * @param amount The amount of tokens withdrawn
     */
    event TokensWithdrawn(address indexed token, address indexed to, address indexed actor, uint256 amount);
}
