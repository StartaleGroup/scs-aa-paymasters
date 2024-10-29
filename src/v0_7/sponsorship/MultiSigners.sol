// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IEntryPoint} from "@account-abstraction/v0_7/contracts/interfaces/IEntryPoint.sol";

/**
 * Helper class for creating a contract with multiple valid signers for sponsorship paymaster data.
 */
abstract contract MultiSigners is Ownable {
    /// @notice Emitted when a signer is added.
    event SignerAdded(address signer);

    /// @notice Emitted when a signer is removed.
    event SignerRemoved(address signer);

    /// @notice Mapping of valid signers.
    mapping(address account => bool isValidSigner) public signers;

    constructor(address[] memory _initialSigners) {
        for (uint256 i = 0; i < _initialSigners.length; i++) {
            signers[_initialSigners[i]] = true;
        }
    }

    function removeSigner(address _signer) public onlyOwner {
        delete signers[_signer];
        emit SignerRemoved(_signer);
    }

    function addSigner(address _signer) public onlyOwner {
        signers[_signer] = true;
        emit SignerAdded(_signer);
    }
}
