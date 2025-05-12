// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {PackedUserOperation} from "@account-abstraction/contracts/core/UserOperationLib.sol";
import {IStartaleManagedPaymasterEventsAndErrors} from "./IStartaleManagedPaymasterEventsAndErrors.sol";

/**
 * @title IStartaleManagedPaymaster
 * @notice Interface for the StartaleManagedPaymaster that enables sponsored transactions
 * @dev Extends IStartaleManagedPaymasterEventsAndErrors to include main functionality
 */
interface IStartaleManagedPaymaster is IStartaleManagedPaymasterEventsAndErrors {
    /**
     * @notice Adds a new authorized signer for validating operations
     * @param _signer The address to add as a signer
     */
    function addSigner(address _signer) external payable;

    /**
     * @notice Removes an authorized signer
     * @param _signer The signer address to remove
     */
    function removeSigner(address _signer) external payable;

    /**
     * @notice Withdraws ERC20 tokens from the paymaster
     * @dev Can be used to recover accidentally sent tokens
     * @param _token The token contract to withdraw from
     * @param _target The recipient address
     * @param _amount The amount to withdraw
     */
    function withdrawERC20(IERC20 _token, address _target, uint256 _amount) external;

    /**
     * @notice Withdraws ETH from the paymaster
     * @param _recipient The recipient address
     * @param _amount The amount of ETH to withdraw
     */
    function withdrawEth(address payable _recipient, uint256 _amount) external payable;

    /**
     * @notice Generates a hash of the given UserOperation to be signed by the paymaster
     * @param _userOp The UserOperation structure
     * @param _validUntil The timestamp until which the operation is valid
     * @param _validAfter The timestamp after which the operation is valid
     * @return The hashed UserOperation data
     */
    function getHash(PackedUserOperation calldata _userOp, uint48 _validUntil, uint48 _validAfter)
        external
        view
        returns (bytes32);

    /**
     * @notice Parses the paymaster data to extract relevant information
     * @param _paymasterAndData The encoded paymaster data
     * @return validUntil The timestamp until which the operation is valid
     * @return validAfter The timestamp after which the operation is valid
     * @return signature The signature validating the operation
     */
    function parsePaymasterAndData(bytes calldata _paymasterAndData)
        external
        pure
        returns (uint48 validUntil, uint48 validAfter, bytes calldata signature);
}
