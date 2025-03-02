// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "solady/utils/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import { EntryPoint } from "account-abstraction/core/EntryPoint.sol";
import { IEntryPoint } from "account-abstraction/interfaces/IEntryPoint.sol";
import { PackedUserOperation } from "account-abstraction/interfaces/PackedUserOperation.sol";
import { SimpleAccountFactory, SimpleAccount } from "@account-abstraction/contracts/samples/SimpleAccountFactory.sol";
import "./CheatCodes.sol";

contract TestHelper is CheatCodes {

    // -----------------------------------------
    // State Variables
    // -----------------------------------------
    Vm.Wallet internal DEPLOYER;
    Vm.Wallet internal BOB;
    Vm.Wallet internal ALICE;
    Vm.Wallet internal CHARLIE;
    Vm.Wallet internal BUNDLER;
    Vm.Wallet internal FACTORY_OWNER; // If Applicable

    address internal BOB_ADDRESS;
    address internal ALICE_ADDRESS;
    address internal CHARLIE_ADDRESS;
    address payable internal BUNDLER_ADDRESS;


    SimpleAccount internal BOB_ACCOUNT;
    SimpleAccount internal ALICE_ACCOUNT;
    SimpleAccount internal CHARLIE_ACCOUNT;

    IEntryPoint internal ENTRYPOINT;
    SimpleAccountFactory internal FACTORY;


    // -----------------------------------------
    // Setup Functions
    // -----------------------------------------
    /// @notice Initializes the testing environment with wallets, contracts, and accounts
    function setupTestEnvironment() internal virtual {
        /// Initializes the testing environment
        setupPredefinedWallets();
        deployTestContracts();
        // deploySimpleAccountForPredefinedWallets();
    }

    function createAndFundWallet(string memory name, uint256 amount) internal returns (Vm.Wallet memory) {
        Vm.Wallet memory wallet = newWallet(name);
        vm.deal(wallet.addr, amount);
        return wallet;
    }

    function setupPredefinedWallets() internal {
        DEPLOYER = createAndFundWallet("DEPLOYER", 1000 ether);

        BOB = createAndFundWallet("BOB", 1000 ether);
        BOB_ADDRESS = BOB.addr;

        ALICE = createAndFundWallet("ALICE", 1000 ether);
        CHARLIE = createAndFundWallet("CHARLIE", 1000 ether);

        ALICE_ADDRESS = ALICE.addr;
        CHARLIE_ADDRESS = CHARLIE.addr;

        BUNDLER = createAndFundWallet("BUNDLER", 1000 ether);
        BUNDLER_ADDRESS = payable(BUNDLER.addr);

        FACTORY_OWNER = createAndFundWallet("FACTORY_OWNER", 1000 ether);
    }

    function deployTestContracts() internal {
        ENTRYPOINT = new EntryPoint();
        vm.etch(address(0x0000000071727De22E5E9d8BAf0edAc6f37da032), address(ENTRYPOINT).code);
        ENTRYPOINT = IEntryPoint(0x0000000071727De22E5E9d8BAf0edAc6f37da032);
        // ACCOUNT_IMPLEMENTATION = new Nexus(address(ENTRYPOINT));
        // FACTORY = new NexusAccountFactory(address(ACCOUNT_IMPLEMENTATION), address(FACTORY_OWNER.addr));
    }

    // -----------------------------------------
    // Utility Functions
    // -----------------------------------------

    // todo: calculateAccountAddress

    // todo: buildInitCode

    // todo: buildUserOpWithInitAndCalldata

    // Todo: buildUserOpWithCalldata

    // Todo: buildPackedUserOperation

    /// @notice Retrieves the nonce for a given account and validator
    /// @param account The account address
    function getNonce(address account) internal view returns (uint256 nonce) {
        uint192 key = makeNonceKey();
        nonce = ENTRYPOINT.getNonce(address(account), key);
    }

    /// @notice Composes the nonce key
    function makeNonceKey() internal virtual pure returns (uint192 key) {
       return 0; // for simple account
    }

    /// @notice Signs a user operation
    /// @param wallet The wallet to sign the operation
    /// @param userOp The user operation to sign
    /// @return The signed user operation
    function signUserOp(
        Vm.Wallet memory wallet,
        PackedUserOperation memory userOp
    )
        internal
        view
        returns (bytes memory)
    {
        bytes32 opHash = ENTRYPOINT.getUserOpHash(userOp);
        return signMessage(wallet, opHash);
    }

    // -----------------------------------------
    // Utility Functions
    // -----------------------------------------

    /// @notice Modifies the address of a deployed contract in a test environment
    /// @param originalAddress The original address of the contract
    /// @param newAddress The new address to replace the original
    function changeContractAddress(address originalAddress, address newAddress) internal {
        vm.etch(newAddress, originalAddress.code);
    }

    /// @notice Builds a user operation struct for account abstraction tests
    /// @param sender The sender address
    /// @param nonce The nonce
    /// @return userOp The built user operation
    function buildPackedUserOp(address sender, uint256 nonce) internal pure returns (PackedUserOperation memory) {
        return PackedUserOperation({
            sender: sender,
            nonce: nonce,
            initCode: "",
            callData: "",
            accountGasLimits: bytes32(abi.encodePacked(uint128(3e6), uint128(3e6))), // verification and call gas limit
            preVerificationGas: 3e5, // Adjusted preVerificationGas
            gasFees: bytes32(abi.encodePacked(uint128(3e6), uint128(3e6))), // maxFeePerGas and maxPriorityFeePerGas
            paymasterAndData: "",
            signature: ""
        });
    }

    /// @notice Signs a message and packs r, s, v into bytes
    /// @param wallet The wallet to sign the message
    /// @param messageHash The hash of the message to sign
    /// @return signature The packed signature
    function signMessage(Vm.Wallet memory wallet, bytes32 messageHash) internal pure returns (bytes memory signature) {
        bytes32 userOpHash = ECDSA.toEthSignedMessageHash(messageHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(wallet.privateKey, userOpHash);
        signature = abi.encodePacked(r, s, v);
    }

    // Todo: buildPackedUserOperation

    /// @dev Returns a random non-zero address.
    /// @notice Returns a random non-zero address
    /// @return result A random non-zero address
    function randomNonZeroAddress() internal returns (address result) {
        do {
            result = address(uint160(random()));
        } while (result == address(0));
    }

    /// @notice Checks if an address is a contract
    /// @param account The address to check
    /// @return True if the address is a contract, false otherwise
    function isContract(address account) internal view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(account)
        }
        return size > 0;
    }

    /// @dev credits: vectorized || solady
    /// @dev Returns a pseudorandom random number from [0 .. 2**256 - 1] (inclusive).
    /// For usage in fuzz tests, please ensure that the function has an unnamed uint256 argument.
    /// e.g. `testSomething(uint256) public`.
    function random() internal returns (uint256 r) {
        /// @solidity memory-safe-assembly
        assembly {
            // This is the keccak256 of a very long string I randomly mashed on my keyboard.
            let sSlot := 0xd715531fe383f818c5f158c342925dcf01b954d24678ada4d07c36af0f20e1ee
            let sValue := sload(sSlot)

            mstore(0x20, sValue)
            r := keccak256(0x20, 0x40)

            // If the storage is uninitialized, initialize it to the keccak256 of the calldata.
            if iszero(sValue) {
                sValue := sSlot
                let m := mload(0x40)
                calldatacopy(m, 0, calldatasize())
                r := keccak256(m, calldatasize())
            }
            sstore(sSlot, add(r, 1))

            // Do some biased sampling for more robust tests.
            // prettier-ignore
            for { } 1 { } {
                let d := byte(0, r)
                // With a 1/256 chance, randomly set `r` to any of 0,1,2.
                if iszero(d) {
                    r := and(r, 3)
                    break
                }
                // With a 1/2 chance, set `r` to near a random power of 2.
                if iszero(and(2, d)) {
                    // Set `t` either `not(0)` or `xor(sValue, r)`.
                    let t := xor(not(0), mul(iszero(and(4, d)), not(xor(sValue, r))))
                    // Set `r` to `t` shifted left or right by a random multiple of 8.
                    switch and(8, d)
                    case 0 {
                        if iszero(and(16, d)) { t := 1 }
                        r := add(shl(shl(3, and(byte(3, r), 0x1f)), t), sub(and(r, 7), 3))
                    }
                    default {
                        if iszero(and(16, d)) { t := shl(255, 1) }
                        r := add(shr(shl(3, and(byte(3, r), 0x1f)), t), sub(and(r, 7), 3))
                    }
                    // With a 1/2 chance, negate `r`.
                    if iszero(and(0x20, d)) { r := not(r) }
                    break
                }
                // Otherwise, just set `r` to `xor(sValue, r)`.
                r := xor(sValue, r)
                break
            }
        }
    }

    /// @notice Pre-funds a smart account and asserts success
    /// @param sa The smart account address
    /// @param prefundAmount The amount to pre-fund
    function prefundSmartAccountAndAssertSuccess(address sa, uint256 prefundAmount) internal {
        (bool res,) = sa.call{ value: prefundAmount }(""); // Pre-funding the account contract
        assertTrue(res, "Pre-funding account should succeed");
    }

    /// @notice Calculates the gas cost of the calldata
    /// @param data The calldata
    /// @return calldataGas The gas cost of the calldata
    function calculateCalldataCost(bytes memory data) internal pure returns (uint256 calldataGas) {
        for (uint256 i = 0; i < data.length; i++) {
            if (uint8(data[i]) == 0) {
                calldataGas += 4;
            } else {
                calldataGas += 16;
            }
        }
    }

    /// @notice Helper function to measure and log gas for simple EOA calls
    /// @param description The description for the log
    /// @param target The target contract address
    /// @param value The value to be sent with the call
    /// @param callData The calldata for the call
    function measureAndLogGasEOA(
        string memory description,
        address target,
        uint256 value,
        bytes memory callData
    )
        internal
    {
        uint256 calldataCost = 0;
        for (uint256 i = 0; i < callData.length; i++) {
            if (uint8(callData[i]) == 0) {
                calldataCost += 4;
            } else {
                calldataCost += 16;
            }
        }

        uint256 baseGas = 21_000;

        uint256 initialGas = gasleft();
        (bool res,) = target.call{ value: value }(callData);
        uint256 gasUsed = initialGas - gasleft() + baseGas + calldataCost;
        assertTrue(res);
        emit log_named_uint(description, gasUsed);
    }

    /// @notice Helper function to calculate calldata cost and log gas usage
    /// @param description The description for the log
    /// @param userOps The user operations to be executed
    function measureAndLogGas(string memory description, PackedUserOperation[] memory userOps) internal {
        bytes memory callData = abi.encodeWithSelector(ENTRYPOINT.handleOps.selector, userOps, payable(BUNDLER.addr));

        uint256 calldataCost = 0;
        for (uint256 i = 0; i < callData.length; i++) {
            if (uint8(callData[i]) == 0) {
                calldataCost += 4;
            } else {
                calldataCost += 16;
            }
        }

        uint256 baseGas = 21_000;

        uint256 initialGas = gasleft();
        ENTRYPOINT.handleOps(userOps, payable(BUNDLER.addr));
        uint256 gasUsed = initialGas - gasleft() + baseGas + calldataCost;
        emit log_named_uint(description, gasUsed);
    }

    /// @notice Handles a user operation and measures gas usage
    /// @param userOps The user operations to handle
    /// @param refundReceiver The address to receive the gas refund
    /// @return gasUsed The amount of gas used
    function handleUserOpAndMeasureGas(
        PackedUserOperation[] memory userOps,
        address refundReceiver
    )
        internal
        returns (uint256 gasUsed)
    {
        uint256 gasStart = gasleft();
        ENTRYPOINT.handleOps(userOps, payable(refundReceiver));
        gasUsed = gasStart - gasleft();
    }
}