// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {EntryPoint} from "@account-abstraction/contracts/core/EntryPoint.sol";
import {PackedUserOperation} from "@account-abstraction/contracts/interfaces/PackedUserOperation.sol";
import {SponsorshipPaymaster} from "../src/sponsorship/SponsorshipPaymaster.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {TestCounter} from "./TestCounter.sol";


contract SponsorshipPaymasterTest is Test {
    SponsorshipPaymaster paymaster;
    EntryPoint entryPoint;
    TestCounter counter;
    
    address payable beneficiary;
    address paymasterOwner;
    address paymasterSigner;
    uint256 paymasterSignerKey;
    address user;
    uint256 userKey;
    address fundingID;

    function setUp() external {
        counter = new TestCounter();
        beneficiary = payable(makeAddr("beneficiary"));
        paymasterOwner = makeAddr("paymasterOwner");
        (paymasterSigner, paymasterSignerKey) = makeAddrAndKey("paymasterSigner");
        (user, userKey) = makeAddrAndKey("user");
        fundingID = makeAddr("fundingID");

        entryPoint = new EntryPoint();

        // Correctly initialize the signers array
        address[] memory signers = new address[](1);
        signers[0] = paymasterSigner;

        vm.prank(paymasterOwner);
        paymaster = new SponsorshipPaymaster(paymasterOwner, address(entryPoint), signers, beneficiary, 1 ether, 0, 100000);

        // Ensure signer is added
        vm.prank(paymasterOwner);
        paymaster.addSigner(paymasterSigner);
    }


    function testDepositForUser() external {
        vm.deal(user, 10 ether);
        vm.prank(user);
        paymaster.depositForUser{value: 5 ether}();
        assertEq(paymaster.getBalance(user), 5 ether); // Ensure correct address is checked
    }

    function testWithdrawFunds() external {
        vm.deal(user, 10 ether);
        vm.prank(user);
        paymaster.depositForUser{value: 5 ether}();

        vm.prank(user);
        paymaster.requestWithdrawal(3 ether);

        vm.warp(block.timestamp + 600); // Move forward in time
        vm.roll(block.number + 5); // Ensure blockchain state updates

        vm.prank(user);
        paymaster.executeWithdrawal(user);

        assertEq(paymaster.getBalance(user), 2 ether);
    }


    function testValidateUserOperation() external {
        vm.deal(paymasterOwner, 20 ether); // Ensure paymaster has ETH
        vm.prank(paymasterOwner);
        paymaster.depositForUser{value: 10 ether}();

        address sender = user;
        bytes memory callData = abi.encodeWithSelector(TestCounter.count.selector);

        PackedUserOperation memory op = prepareUserOp(sender, callData);
        bytes memory paymasterData = getSignedPaymasterData(op);

        require(paymasterData.length > 0, "PaymasterAndData is empty!"); // Debugging check

        op.paymasterAndData = paymasterData;
        op.signature = signUserOp(op, userKey);

        submitUserOp(op);
        assertEq(counter.counters(sender), 0);
    }


    function prepareUserOp(address sender, bytes memory callData) private view returns (PackedUserOperation memory op) {
        op.sender = sender;
        op.nonce = entryPoint.getNonce(sender, 0);
        op.callData = callData;
        op.accountGasLimits = bytes32(abi.encodePacked(bytes16(uint128(80000)), bytes16(uint128(50000))));
        op.preVerificationGas = 50000;
        op.gasFees = bytes32(abi.encodePacked(bytes16(uint128(100)), bytes16(uint128(1000000000))));
            // Construct paymasterAndData without the signature
        op.paymasterAndData = abi.encodePacked(
            address(paymaster),          // Paymaster address
            uint128(100_000),            // PreVerification Gas
            uint128(50_000),             // PostOp Gas
            fundingID,                   // Funding ID
            uint48(block.timestamp + 1 days), // validUntil
            uint48(block.timestamp),     // validAfter
            uint32(1_000_000)            // Price markup
        );

        return op;
    }

    function getSignedPaymasterData(PackedUserOperation memory userOp) private view returns (bytes memory) {
        bytes memory paymasterAndData = abi.encodePacked(
            address(paymaster),
            uint128(100_000), // PreVerification Gas
            uint128(50_000),  // PostOp Gas
            fundingID,
            uint48(block.timestamp + 1 days), // validUntil
            uint48(block.timestamp), // validAfter
            uint32(1_000_000) // Price markup
        );

        bytes32 hash = paymaster.getHash(userOp);
        bytes memory sig = getSignature(hash, paymasterSignerKey);
        bytes memory fullPaymasterData = abi.encodePacked(paymasterAndData, sig);

        return fullPaymasterData;
    }

    function getSignature(bytes32 hash, uint256 signingKey) private pure returns (bytes memory) {
        bytes32 digest = MessageHashUtils.toEthSignedMessageHash(hash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signingKey, digest);
        return abi.encodePacked(r, s, v);
    }

    function signUserOp(PackedUserOperation memory op, uint256 _key) private view returns (bytes memory signature) {
        bytes32 userOpHash = entryPoint.getUserOpHash(op);

        bytes32 messageHash = MessageHashUtils.toEthSignedMessageHash(userOpHash);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_key, messageHash); // Corrected this line
        signature = abi.encodePacked(r, s, v);
    }

    function submitUserOp(PackedUserOperation memory op) public {
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = op;

        entryPoint.handleOps(ops, beneficiary);
    }
}
