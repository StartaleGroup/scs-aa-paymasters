// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

// Note: Can import whole ISponsorshipPaymasterEventsAndErrors.sol

contract BaseEventsAndErrors {
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    event OwnershipHandoverRequested(address indexed pendingOwner);

    event SignerAdded(address indexed signer);
    event SignerRemoved(address indexed signer);

    error NewOwnerIsZeroAddress();
    error NoHandoverRequest();
    error Unauthorized();
}
