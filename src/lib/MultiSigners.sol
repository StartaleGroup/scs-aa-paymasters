// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/**
 * @title MultiSigners
 * @notice Helper contract for creating a contract with multiple valid signers for sponsorship paymaster data
 * @dev Provides functionality to manage authorized signers for an account abstraction contract
 */
abstract contract MultiSigners {
    // Events
    /// @notice Emitted when a signer is added
    event SignerAdded(address indexed signer);

    /// @notice Emitted when a signer is removed
    event SignerRemoved(address indexed signer);

    // Custom errors
    /// @notice Error when no signers are provided during contract deployment
    error NoInitialSigners();

    /// @notice Error when a signer address is zero
    error SignerAddressCannotBeZero();

    /// @notice Error when a signer address is a contract
    error SignerAddressCannotBeContract();

    /// @notice Error when a signer is not added
    error SignerNotAdded(address signer);

    /// @notice Error when a signer is already added
    error SignerAlreadyAdded(address signer);

    // State variables
    /// @notice Mapping of valid signers
    mapping(address account => bool isValidSigner) public signers;

    /**
     * @notice Constructor to initialize the contract with a set of signers
     * @param _initialSigners Array of initial signer addresses
     */
    constructor(address[] memory _initialSigners) {
        uint256 length = _initialSigners.length;
        if (length == 0) {
            revert NoInitialSigners();
        }

        for (uint256 i; i < length; ++i) {
            if (_initialSigners[i] == address(0)) {
                revert SignerAddressCannotBeZero();
            }
            if (_isSmartContract(_initialSigners[i])) {
                revert SignerAddressCannotBeContract();
            }

            signers[_initialSigners[i]] = true;
            emit SignerAdded(_initialSigners[i]);
        }
    }

    // External view functions
    /**
     * @notice Checks if an address is a registered signer
     * @param _signer Address to check
     * @return True if the address is a registered signer, false otherwise
     */
    function isSigner(address _signer) external view returns (bool) {
        return signers[_signer];
    }

    // Internal state-modifying functions
    /**
     * @notice Removes a signer from the list of authorized signers
     * @dev Emits a SignerRemoved event
     * @param _signer Address of the signer to remove
     */
    function _removeSigner(address _signer) internal {
        if (!signers[_signer]) {
            revert SignerNotAdded(_signer);
        }
        delete signers[_signer];
        emit SignerRemoved(_signer);
    }

    /**
     * @notice Adds a signer to the list of authorized signers
     * @dev Validates the signer address and emits a SignerAdded event
     * @param _signer Address of the signer to add
     */
    function _addSigner(address _signer) internal {
        if (signers[_signer]) {
            revert SignerAlreadyAdded(_signer);
        }
        if (_signer == address(0)) {
            revert SignerAddressCannotBeZero();
        }
        if (_isSmartContract(_signer)) {
            revert SignerAddressCannotBeContract();
        }

        signers[_signer] = true;
        emit SignerAdded(_signer);
    }

    // Private view functions
    /**
     * @notice Checks if an address is a smart contract
     * @dev Uses assembly to check code size at the address
     * @param addr Address to check
     * @return True if the address is a contract, false otherwise
     */
    function _isSmartContract(address addr) private view returns (bool) {
        uint256 size;
        assembly ("memory-safe") {
            size := extcodesize(addr)
        }
        return size > 0;
    }
}
