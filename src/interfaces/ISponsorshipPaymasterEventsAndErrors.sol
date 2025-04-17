// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {IPaymaster} from "@account-abstraction/contracts/interfaces/IPaymaster.sol";

/**
 * @title ISponsorshipPaymasterEventsAndErrors
 * @notice Interface defining all events and errors for the SponsorshipPaymaster
 * @dev This interface is used to standardize error and event definitions across implementations
 */
interface ISponsorshipPaymasterEventsAndErrors {
    // Errors

    /**
     * @notice Error thrown when the paymaster signature has an invalid length
     * @dev Signature length should be 64 or 65 bytes
     */
    error PaymasterSignatureLengthInvalid();

    /**
     * @notice Error thrown when a user has insufficient funds for an operation
     * @param user The address with insufficient funds
     * @param balance The user's current balance
     * @param required The amount required for the operation
     */
    error InsufficientFunds(address user, uint256 balance, uint256 required);

    /**
     * @notice Error thrown when attempting to execute a withdrawal without a prior request
     * @param user The user address for which no withdrawal request exists
     */
    error NoWithdrawalRequestSubmitted(address user);

    /**
     * @notice Error thrown when attempting to execute a withdrawal before the delay period has passed
     * @param user The user address attempting the early withdrawal
     * @param nextAllowedTime The timestamp when withdrawal will be allowed
     */
    error WithdrawalTooSoon(address user, uint256 nextAllowedTime);

    /**
     * @notice Error thrown when a deposit is below the minimum required amount
     * @param provided The amount provided in the deposit
     * @param required The minimum required deposit amount
     */
    error LowDeposit(uint256 provided, uint256 required);

    /**
     * @notice Error thrown when trying to use the standard deposit function
     * @dev Users should use depositFor() instead of deposit()
     */
    error UseDepositForInstead();

    /**
     * @notice Error thrown when trying to withdraw directly without a request
     * @dev Users should submit a withdrawal request first
     */
    error SubmitRequestInstead();

    /**
     * @notice Error thrown when the unaccounted gas exceeds the maximum limit
     */
    error UnaccountedGasTooHigh();

    /**
     * @notice Error thrown when attempting to withdraw zero amount
     */
    error CanNotWithdrawZeroAmount();

    /**
     * @notice Error thrown when an invalid price markup is provided
     * @dev Markup should typically be between 1e6 (100%, no markup) and 2e6 (200%, maximum)
     */
    error InvalidPriceMarkup();

    /**
     * @notice Error thrown when an invalid withdrawal address is provided
     * @dev Typically occurs when the address is zero
     */
    error InvalidWithdrawalAddress();

    /**
     * @notice Error thrown when attempting to set the fee collector to the zero address
     */
    error FeeCollectorCanNotBeZero();

    /**
     * @notice Error thrown when attempting to set the fee collector to a contract address
     */
    error FeeCollectorCanNotBeContract();

    /**
     * @notice Error thrown when the post-operation gas limit is too low
     */
    error PostOpGasLimitTooLow();

    /**
     * @notice Error thrown when an invalid deposit address is provided
     * @dev Typically occurs when the address is zero
     */
    error InvalidDepositAddress();

    /**
     * @notice Error thrown when ETH withdrawal fails
     */
    error WithdrawalFailed();

    /**
     * @notice Error thrown when the minimum deposit is set to zero
     */
    error MinDepositCanNotBeZero();

    /**
     * @notice Error thrown when the withdrawal delay is set to a value greater than 1 day
     */
    error WithdrawalDelayTooLong();

    /**
     * @notice Error thrown when a potentially malformed signature is detected
     */
    error PotentiallyMalformedSignature();

    /**
     * @notice Error thrown when a user has insufficient funds for a withdrawal
     * @param balance The user's current balance
     * @param amount The amount requested for withdrawal
     * @param minDeposit current minimum deposit
     */
    error RequiredToWithdrawFullBalanceOrKeepMinDeposit(uint256 balance, uint256 amount, uint256 minDeposit);

    // Events

    /**
     * @notice Emitted when a user operation is sponsored
     * @param userOpHash The hash of the sponsored user operation
     * @param user The address of the user whose operation is sponsored
     */
    event UserOperationSponsored(bytes32 indexed userOpHash, address indexed user);

    /**
     * @notice Emitted when a user adds a deposit
     * @param user The address that added the deposit
     * @param amount The amount deposited
     */
    event DepositAdded(address indexed user, uint256 amount);

    /**
     * @notice Emitted when gas balance is deducted from a sponsor
     * @param user The sponsor address
     * @param amount The amount of gas cost deducted
     * @param premium The premium amount (markup) applied
     * @param mode The post-operation mode
     */
    event GasBalanceDeducted(address indexed user, uint256 amount, uint256 premium, IPaymaster.PostOpMode mode);

    /**
     * @notice Emitted when a withdrawal request is submitted
     * @param sponsorAddress The address of the sponsor requesting withdrawal
     * @param withdrawAddress The address where funds should be sent
     * @param amount The amount requested for withdrawal
     */
    event WithdrawalRequested(address indexed sponsorAddress, address indexed withdrawAddress, uint256 amount);

    /**
     * @notice Emitted when a withdrawal is executed
     * @param sponsorAddress The address of the sponsor
     * @param withdrawAddress The address receiving the funds
     * @param amount The amount withdrawn
     */
    event WithdrawalExecuted(address indexed sponsorAddress, address indexed withdrawAddress, uint256 amount);

    /**
     * @notice Emitted when the fee collector address is changed
     * @param oldFeeCollector The previous fee collector address
     * @param newFeeCollector The new fee collector address
     */
    event FeeCollectorChanged(address indexed oldFeeCollector, address indexed newFeeCollector);

    /**
     * @notice Emitted when the minimum deposit requirement is changed
     * @param oldMinDeposit The previous minimum deposit value
     * @param newMinDeposit The new minimum deposit value
     */
    event MinDepositChanged(uint256 oldMinDeposit, uint256 newMinDeposit);

    /**
     * @notice Emitted when excess funds are refunded after an operation
     * @param user The address receiving the refund
     * @param amount The amount refunded
     */
    event RefundProcessed(address indexed user, uint256 amount);

    /**
     * @notice Emitted when ETH is withdrawn from the contract
     * @param recipient The address receiving the withdrawn ETH
     * @param amount The amount withdrawn
     */
    event EthWithdrawn(address indexed recipient, uint256 amount);

    /**
     * @notice Emitted when the unaccounted gas value is changed
     * @param oldUnaccountedGas The previous unaccounted gas value
     * @param newUnaccountedGas The new unaccounted gas value
     */
    event UnaccountedGasChanged(uint256 oldUnaccountedGas, uint256 newUnaccountedGas);

    /**
     * @notice Emitted when tokens are withdrawn from the contract
     * @param token The address of the token being withdrawn
     * @param to The recipient address
     * @param actor The address that initiated the withdrawal
     * @param amount The amount of tokens withdrawn
     */
    event TokensWithdrawn(address indexed token, address indexed to, address indexed actor, uint256 amount);

    /**
     * @notice Emitted when a withdrawal request is cancelled
     * @param sponsorAccount The address of the sponsor who cancelled the withdrawal request
     */
    event WithdrawalRequestCancelledFor(address sponsorAccount);
}
