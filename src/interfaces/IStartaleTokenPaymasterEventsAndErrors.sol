// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {IPaymaster} from "@account-abstraction/contracts/interfaces/IPaymaster.sol";
import {IOracleHelper} from "./IOracleHelper.sol";

interface IStartaleTokenPaymasterEventsAndErrors {
    // Events
    event EthWithdrawn(address indexed recipient, uint256 indexed amount);

    event Received(address indexed sender, uint256 value);

    event TokensWithdrawn(address indexed token, address indexed to, address indexed actor, uint256 amount);

    event TokenFeeMarkupUpdated(address indexed token, uint48 newFeeMarkup);

    event TokenAdded(address indexed token, uint48 feeMarkup, IOracleHelper.TokenOracleConfig oracleConfig);

    event TokenRemoved(address indexed token);

    event TokenOracleConfigUpdated(address indexed token, IOracleHelper.TokenOracleConfig newConfig);

    // Todo: Review what we need to emit in event below
    event PaidGasInTokens(
        address indexed user, address indexed token, uint256 tokenCharge, uint48 appliedMarkup, uint256 exchangeRate
    );

    // Errors
    /// @notice The paymaster data length is invalid.
    error PaymasterAndDataLengthInvalid();

    /// @notice The paymaster data mode is invalid. The mode should be 0 or 1.
    error PaymasterModeInvalid();

    error PaymasterSignatureLengthInvalid();

    error UnaccountedGasTooHigh();

    error InvalidWithdrawalAddress();

    error WithdrawalFailed();

    error FeeMarkupTooHigh();

    error ArrayLengthMismatch();

    error InvalidTokenAddress();

    error TokenAlreadySupported();

    error TokenNotSupported(address token);

    error InvalidPaymasterMode();

    error PostOpGasLimitTooLow();

    error InvalidIndependentModeSpecificData();

    error FailedToChargeTokens(address user, address token, uint256 tokenAmount);
}
