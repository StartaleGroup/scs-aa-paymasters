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

    /// @notice Error when no signers are provided during contract deployment.
    error NoInitialSigners();

    /// @notice Error when a signer address is zero.
    error SignerAddressCannotBeZero();

    /// @notice Error when a signer address is a contract.
    error SignerAddressCannotBeContract();

    /// @notice Mapping of valid signers.
    mapping(address account => bool isValidSigner) public signers;

    constructor(address[] memory _initialSigners) {
        // cheaper
        uint256 length = _initialSigners.length;
        if (length == 0) revert NoInitialSigners();
        for (uint256 i; i < length;) {
            if (_initialSigners[i] == address(0)) revert SignerAddressCannotBeZero();
            if (_isSmartContract(_initialSigners[i])) revert SignerAddressCannotBeContract();
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
        if (_signer == address(0)) revert SignerAddressCannotBeZero();
        if (_isSmartContract(_signer)) revert SignerAddressCannotBeContract();
        signers[_signer] = true;
        emit SignerAdded(_signer);
    }

    /**
     * Check if address is a contract
     */
    function _isSmartContract(address addr) private view returns (bool) {
        uint256 size;
        assembly ("memory-safe") {
            size := extcodesize(addr)
        }
        return size > 0;
    }

    function isSigner(address _signer) external view returns (bool) {
        return signers[_signer];
    }
}
