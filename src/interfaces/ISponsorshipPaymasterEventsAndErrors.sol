// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {IPaymaster} from "@account-abstraction/contracts/interfaces/IPaymaster.sol";

// Todo: review indexed fields. make as many indexed
interface ISponsorshipPaymasterEventsAndErrors {
    error PaymasterSignatureLengthInvalid();
    error InsufficientFunds(address user, uint256 balance, uint256 required);
    error NoWithdrawalRequestSubmitted(address user);
    error WithdrawalTooSoon(address user, uint256 nextAllowedTime);
    error LowDeposit(uint256 provided, uint256 required);
    error UseDepositForInstead();
    error SubmitRequestInstead();
    error UnaccountedGasTooHigh();
    error CanNotWithdrawZeroAmount();
    error InvalidPriceMarkup();
    error InvalidWithdrawalAddress();

    event UserOperationSponsored(bytes32 indexed userOpHash, address indexed user);
    event DepositAdded(address indexed user, uint256 amount);
    event GasBalanceDeducted(address indexed user, uint256 amount, uint256 premium, IPaymaster.PostOpMode mode);
    event WithdrawalRequested(address indexed sponsorAddress, address indexed withdrawAddress, uint256 indexed amount);
    event WithdrawalExecuted(address indexed sponsorAddress, address indexed withdrawAddress, uint256 indexed amount);
    event FeeCollectorChanged(address indexed oldFeeCollector, address indexed newFeeCollector);
    event MinDepositChanged(uint256 oldMinDeposit, uint256 newMinDeposit);
    event RefundProcessed(address indexed user, uint256 amount);
}
