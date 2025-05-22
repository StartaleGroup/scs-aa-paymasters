// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {PackedUserOperation} from "@account-abstraction/contracts/core/UserOperationLib.sol";
import {ISponsorshipPaymasterEventsAndErrors} from "./ISponsorshipPaymasterEventsAndErrors.sol";

/**
 * @title ISponsorshipPaymaster
 * @notice Interface for the SponsorshipPaymaster that enables sponsored transactions
 * @dev Extends ISponsorshipPaymasterEventsAndErrors to include main functionality
 */
interface ISponsorshipPaymaster is ISponsorshipPaymasterEventsAndErrors {
    /**
     * @notice Structure representing a withdrawal request
     * @param amount The amount requested for withdrawal
     * @param to The address where funds should be sent
     * @param requestSubmittedTimestamp The timestamp when the request was submitted
     */
    struct WithdrawalRequest {
        uint256 amount;
        address to;
        uint256 requestSubmittedTimestamp;
    }

    /**
     * @notice Allows depositing funds for a specific sponsor account
     * @param _sponsorAccount The address of the sponsor account to deposit for
     */
    function depositFor(address _sponsorAccount) external payable;

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
     * @notice Sets a new fee collector address
     * @dev The fee collector receives the premium from fee markups
     * @param _newFeeCollector The new fee collector address
     */
    function setFeeCollector(address _newFeeCollector) external payable;

    /**
     * @notice Sets the unaccounted gas value used for post-operation calculations
     * @param _value The new unaccounted gas value
     */
    function setUnaccountedGas(uint256 _value) external payable;

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
     * @notice Gets the current balance of a sponsor account
     * @param _sponsorAccount The sponsor account address to check
     * @return balance The current balance of the sponsor account
     */
    function getBalance(address _sponsorAccount) external view returns (uint256 balance);

    /**
     * @notice Generates a hash of the given UserOperation to be signed by the paymaster
     * @param _userOp The UserOperation structure
     * @param _sponsorAccount The sponsor account address
     * @param _validUntil The timestamp until which the operation is valid
     * @param _validAfter The timestamp after which the operation is valid
     * @param _feeMarkup The fee markup for the operation
     * @return The hashed UserOperation data
     */
    function getHash(
        PackedUserOperation calldata _userOp,
        address _sponsorAccount,
        uint48 _validUntil,
        uint48 _validAfter,
        uint32 _feeMarkup
    ) external view returns (bytes32);

    /**
     * @notice Parses the paymaster data to extract relevant information
     * @param _paymasterAndData The encoded paymaster data
     * @return sponsorAccount The sponsor account address
     * @return validUntil The timestamp until which the operation is valid
     * @return validAfter The timestamp after which the operation is valid
     * @return feeMarkup The fee markup for the operation
     * @return paymasterValidationGasLimit The gas limit for paymaster validation
     * @return paymasterPostOpGasLimit The gas limit for post-operation
     * @return signature The signature validating the operation
     */
    function parsePaymasterAndData(bytes calldata _paymasterAndData)
        external
        pure
        returns (
            address sponsorAccount,
            uint48 validUntil,
            uint48 validAfter,
            uint32 feeMarkup,
            uint128 paymasterValidationGasLimit,
            uint128 paymasterPostOpGasLimit,
            bytes calldata signature
        );
}
