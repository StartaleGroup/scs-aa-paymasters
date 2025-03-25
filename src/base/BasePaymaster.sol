// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {SoladyOwnable} from "../utils/SoladyOwnable.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IPaymaster} from "@account-abstraction/contracts/interfaces/IPaymaster.sol";
import {IEntryPoint} from "@account-abstraction/contracts/interfaces/IEntryPoint.sol";
import {UserOperationLib, PackedUserOperation} from "@account-abstraction/contracts/core/UserOperationLib.sol";

/**
 * @title BasePaymaster
 * @notice Helper class for creating a paymaster with standard functionality
 * @dev Provides helper methods for staking and validates that postOp is called only by the entryPoint
 */
abstract contract BasePaymaster is IPaymaster, SoladyOwnable {
    // Immutable state variables
    /// @notice The EntryPoint contract reference
    IEntryPoint public immutable entryPoint;

    // Constants
    /// @dev Offset to paymaster validation gas in the UserOperation
    uint256 internal constant PAYMASTER_VALIDATION_GAS_OFFSET = UserOperationLib.PAYMASTER_VALIDATION_GAS_OFFSET;

    /// @dev Offset to paymaster post-op gas in the UserOperation
    uint256 internal constant PAYMASTER_POSTOP_GAS_OFFSET = UserOperationLib.PAYMASTER_POSTOP_GAS_OFFSET;

    /// @dev Offset to paymaster data in the UserOperation
    uint256 internal constant PAYMASTER_DATA_OFFSET = UserOperationLib.PAYMASTER_DATA_OFFSET;

    /**
     * @notice Initializes the BasePaymaster with owner and EntryPoint
     * @param _ownerArg The address that will own the paymaster
     * @param _entryPointArg The EntryPoint contract address
     */
    constructor(address _ownerArg, IEntryPoint _entryPointArg) SoladyOwnable(_ownerArg) {
        _validateEntryPointInterface(_entryPointArg);
        entryPoint = _entryPointArg;
    }

    // External non-view functions

    /**
     * @notice Validates a user operation before it's executed
     * @dev Called by EntryPoint, enforced by _requireFromEntryPoint
     * @param userOp The user operation to validate
     * @param userOpHash The hash of the user operation
     * @param maxCost The maximum cost of the user operation
     * @return context Context for post-operation handling
     * @return validationData Packed validation data for the EntryPoint
     */
    function validatePaymasterUserOp(PackedUserOperation calldata userOp, bytes32 userOpHash, uint256 maxCost)
        external
        override
        returns (bytes memory context, uint256 validationData)
    {
        _requireFromEntryPoint();
        return _validatePaymasterUserOp(userOp, userOpHash, maxCost);
    }

    /**
     * @notice Handles post-operation processing
     * @dev Called by EntryPoint after operation execution, enforced by _requireFromEntryPoint
     * @param mode Operation mode (succeeded, reverted)
     * @param context Context from validatePaymasterUserOp
     * @param actualGasCost Actual gas cost of the operation
     * @param actualUserOpFeePerGas The gas price this operation pays
     */
    function postOp(PostOpMode mode, bytes calldata context, uint256 actualGasCost, uint256 actualUserOpFeePerGas)
        external
        override
    {
        _requireFromEntryPoint();
        _postOp(mode, context, actualGasCost, actualUserOpFeePerGas);
    }

    /**
     * @notice Add a deposit for this paymaster, used for paying for transaction fees
     * @dev Forwards funds to the EntryPoint contract
     */
    function deposit() external payable virtual {
        entryPoint.depositTo{value: msg.value}(address(this));
    }

    /**
     * @notice Withdraw value from the deposit
     * @param _withdrawAddress Target address to send funds to
     * @param _amount Amount to withdraw
     */
    function withdrawTo(address payable _withdrawAddress, uint256 _amount) external virtual onlyOwner {
        entryPoint.withdrawTo(_withdrawAddress, _amount);
    }

    /**
     * @notice Add stake for this paymaster
     * @dev This method can also carry ETH value to add to the current stake
     * @param _unstakeDelaySec The unstake delay for this paymaster (can only be increased)
     */
    function addStake(uint32 _unstakeDelaySec) external payable onlyOwner {
        entryPoint.addStake{value: msg.value}(_unstakeDelaySec);
    }

    /**
     * @notice Unlock the stake, in order to withdraw it
     * @dev The paymaster can't serve requests once unlocked, until it calls addStake again
     */
    function unlockStake() external onlyOwner {
        entryPoint.unlockStake();
    }

    /**
     * @notice Withdraw the entire paymaster's stake
     * @dev Stake must be unlocked first (and then wait for the unstakeDelay to be over)
     * @param _withdrawAddress The address to send withdrawn value
     */
    function withdrawStake(address payable _withdrawAddress) external onlyOwner {
        entryPoint.withdrawStake(_withdrawAddress);
    }

    // External view functions

    /**
     * @notice Return current paymaster's deposit on the entryPoint
     * @return The balance of this paymaster in the EntryPoint
     */
    function getDeposit() public view returns (uint256) {
        return entryPoint.balanceOf(address(this));
    }

    // Internal non-view functions (none that modify state)

    // Internal view functions

    /**
     * @notice Validate a user operation
     * @dev Must be implemented by derived contracts
     * @param _userOp The user operation
     * @param _userOpHash The hash of the user operation
     * @param _maxCost The maximum cost of the user operation
     * @return context Context for post-operation handling
     * @return validationData Packed validation data for the EntryPoint
     */
    function _validatePaymasterUserOp(PackedUserOperation calldata _userOp, bytes32 _userOpHash, uint256 _maxCost)
        internal
        virtual
        returns (bytes memory context, uint256 validationData);

    /**
     * @notice Post-operation handler
     * @dev Must be implemented by derived contracts that return non-empty context
     * @param _mode Operation mode (succeeded, reverted)
     * @param _context Context from validatePaymasterUserOp
     * @param _actualGasCost Actual gas cost of the operation
     * @param _actualUserOpFeePerGas The gas price this operation pays
     */
    function _postOp(PostOpMode _mode, bytes calldata _context, uint256 _actualGasCost, uint256 _actualUserOpFeePerGas)
        internal
        virtual
    {
        (_mode, _context, _actualGasCost, _actualUserOpFeePerGas); // unused params
        revert("BasePaymaster: _postOp must be overridden");
    }

    /**
     * @notice Validate the call is made from the EntryPoint
     * @dev Reverts if caller is not the EntryPoint
     */
    function _requireFromEntryPoint() internal virtual {
        require(msg.sender == address(entryPoint), "Caller is not EntryPoint");
    }

    /**
     * @notice Validate that EntryPoint implements the correct interface
     * @dev Sanity check: make sure EntryPoint was compiled against the same IEntryPoint
     * @param _entryPoint The EntryPoint contract to validate
     */
    function _validateEntryPointInterface(IEntryPoint _entryPoint) internal virtual {
        require(
            IERC165(address(_entryPoint)).supportsInterface(type(IEntryPoint).interfaceId),
            "IEntryPoint interface mismatch"
        );
    }

    /**
     * @notice Check if an address is a contract
     * @param _addr The address to check
     * @return True if the address contains code (is a contract)
     */
    function _isContract(address _addr) internal view returns (bool) {
        uint256 size;
        assembly ("memory-safe") {
            size := extcodesize(_addr)
        }
        return size > 0;
    }
}
