// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {IPaymaster} from "@account-abstraction/contracts/interfaces/IPaymaster.sol";

interface ISponsorshipPaymasterEventsAndErrors {
    // Events

    // Errors
    /// @notice The paymaster data length is invalid.
    error PaymasterAndDataLengthInvalid();

    /// @notice The paymaster data mode is invalid. The mode should be 0 or 1.
    error PaymasterModeInvalid();
}