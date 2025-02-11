// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IEntryPoint} from "@account-abstraction/contracts/interfaces/IEntryPoint.sol";

/**
 * Helper class for creating a contract with multiple valid signers for sponsorship paymaster data.
 */
abstract contract MultiSigners {
    /// @notice Emitted when a signer is added.
    event SignerAdded(address signer);

    /// @notice Emitted when a signer is removed.
    event SignerRemoved(address signer);

    /// @notice Mapping of valid signers.
    mapping(address account => bool isValidSigner) public signers;

    constructor(address[] memory _initialSigners) {
        // cheaper
        uint256 length = _initialSigners.length;
        for (uint256 i; i < length;) {
            signers[_initialSigners[i]] = true;
            unchecked {
                ++i;
            }
        }
    }

    function _removeSigner(address _signer) internal virtual {
        delete signers[_signer];
        emit SignerRemoved(_signer);
    }

    function _addSigner(address _signer) internal virtual {
        signers[_signer] = true;
        emit SignerAdded(_signer);
    }

    function isSigner(address _signer) external view returns (bool) {
        return signers[_signer];
    }
}
