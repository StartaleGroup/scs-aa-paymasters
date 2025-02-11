// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Ownable} from "solady/auth/Ownable.sol";

/**
 * @title SoladyOwnable
 * @author vectorized
 * @notice Allows us to pass desired owner address as solday version does NOT auto-initialize the owner to `msg.sender`
 * @dev This contract is a copy of the Solady Ownable contract with the constructor modified to accept an owner address.
 * @dev More gas efficient and has helpers to enable 2 step ownership transfer.
 */
contract SoladyOwnable is Ownable {
    constructor(address _owner) Ownable() {
        assembly {
            if iszero(shl(96, _owner)) {
                mstore(0x00, 0x7448fbae) // `NewOwnerIsZeroAddress()`.
                revert(0x1c, 0x04)
            }
        }
        _initializeOwner(_owner);
    }
}
