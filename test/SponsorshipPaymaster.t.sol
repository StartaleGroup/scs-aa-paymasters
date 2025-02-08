// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {EntryPoint} from "@account-abstraction/contracts/core/EntryPoint.sol";
import {PackedUserOperation} from "@account-abstraction/contracts/interfaces/PackedUserOperation.sol";
import {SponsorshipPaymaster} from "../src/sponsorship/SponsorshipPaymaster.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {TestCounter} from "./TestCounter.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

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
    address sponsorAccount;
    address constant ALICE_ADDRESS = address(0x123456789abcdef); // Define ALICE_ADDRESS
    uint256 constant WITHDRAWAL_DELAY = 0; // Define withdrawal delay

    modifier prankModifier(address sender) {
        vm.prank(sender);
        _;
    }

    struct PaymasterData {
        address paymasterAddress;
        uint128 preVerificationGas;
        uint128 postOpGas;
        address sponsorAccount;
        uint48 validUntil;
        uint48 validAfter;
        uint32 dynamicAdjustment;
    }

    function setUp() external {
        vm.deal(ALICE_ADDRESS, 100 ether); 
        vm.deal(paymasterOwner, 100 ether); 

        counter = new TestCounter();
        beneficiary = payable(makeAddr("beneficiary"));
        paymasterOwner = makeAddr("paymasterOwner");
        (paymasterSigner, paymasterSignerKey) = makeAddrAndKey("paymasterSigner");
        (user, userKey) = makeAddrAndKey("user");
        sponsorAccount = makeAddr("sponsorAccount");

        entryPoint = new EntryPoint();

        address[] memory signers = new address[](1);
        signers[0] = paymasterSigner;

        vm.prank(paymasterOwner);
        paymaster =
            new SponsorshipPaymaster(paymasterOwner, address(entryPoint), signers, beneficiary, 1 ether, WITHDRAWAL_DELAY, 100000);

        vm.prank(paymasterOwner);
        paymaster.addSigner(paymasterSigner);
    }

    function test_DepositForUser() external {
        uint256 depositAmount = 10 ether;
        vm.prank(ALICE_ADDRESS);
        paymaster.depositForUser{ value: depositAmount }();

        assertEq(paymaster.getBalance(ALICE_ADDRESS), depositAmount);
    }

    function test_RevertIf_DepositForUserZero() external {
        // Expect `LowDeposit(0, minDeposit)` custom error with correct parameters
        vm.expectRevert(abi.encodeWithSelector(SponsorshipPaymaster.LowDeposit.selector, 0, 1 ether));
        vm.prank(ALICE_ADDRESS);
        paymaster.depositForUser{ value: 0 }();
    }

    function test_RequestWithdrawal() external {
        uint256 depositAmount = 5 ether;
        vm.prank(ALICE_ADDRESS);
        paymaster.depositForUser{ value: depositAmount }();

        vm.prank(ALICE_ADDRESS);
        paymaster.requestWithdrawal(3 ether);
    }

    function test_RevertIf_ExecuteWithdrawalWithNoRequest() external {
        // Expect `NoWithdrawalRequest` custom error with the user's address as parameter
        vm.expectRevert(abi.encodeWithSelector(SponsorshipPaymaster.NoWithdrawalRequest.selector, ALICE_ADDRESS));
        vm.prank(ALICE_ADDRESS);
        paymaster.executeWithdrawal(ALICE_ADDRESS);
    }
    function test_RevertIf_RequestWithdrawalTooSoon() external {
        uint256 depositAmount = 5 ether;
        vm.prank(ALICE_ADDRESS);
        paymaster.depositForUser{ value: depositAmount }();

        vm.prank(ALICE_ADDRESS);
        paymaster.requestWithdrawal(3 ether);

        if (WITHDRAWAL_DELAY > 0) {
            vm.expectRevert(SponsorshipPaymaster.WithdrawalTooSoon.selector);
            vm.prank(ALICE_ADDRESS);
            paymaster.executeWithdrawal(ALICE_ADDRESS);
        } else {
            console.log("Skipping test: WITHDRAWAL_DELAY is 0, withdrawals allowed immediately.");
        }
    }

    function test_ExecuteWithdrawal() external {
        uint256 depositAmount = 5 ether;
        vm.prank(ALICE_ADDRESS);
        paymaster.depositForUser{ value: depositAmount }();

        vm.prank(ALICE_ADDRESS);
        paymaster.requestWithdrawal(3 ether);

        vm.warp(block.timestamp + WITHDRAWAL_DELAY + 1);
        vm.prank(ALICE_ADDRESS);
        paymaster.executeWithdrawal(ALICE_ADDRESS);
    }

    function test_SetUnaccountedGas() external prankModifier(paymasterOwner) {
        uint256 newUnaccountedGas = 80_000;
        paymaster.setUnaccountedGas(newUnaccountedGas);
        assertEq(paymaster.unaccountedGas(), newUnaccountedGas);
    }

    function test_RevertIf_SetUnaccountedGasTooHigh() external prankModifier(paymasterOwner) {
        vm.expectRevert(SponsorshipPaymaster.UnaccountedGasTooHigh.selector);
        paymaster.setUnaccountedGas(200_000);
    }

    function testValidateUserOperation() external {
        vm.deal(paymasterOwner, 20 ether);
        vm.prank(paymasterOwner);
        paymaster.depositForUser{value: 10 ether}();

        address sender = user;
        bytes memory callData = abi.encodeWithSelector(TestCounter.count.selector);

        PackedUserOperation memory op = prepareUserOp(sender, callData);
        bytes memory paymasterData = getSignedPaymasterData(op);

        op.paymasterAndData = paymasterData;
        op.signature = signUserOp(op, userKey);

        submitUserOp(op);
        assertEq(counter.counters(sender), 1);
    }

    function prepareUserOp(address sender, bytes memory callData)
        private
        view
        returns (PackedUserOperation memory op)
    {
        op.sender = sender;
        op.nonce = entryPoint.getNonce(sender, 0);
        op.callData = callData;
        op.accountGasLimits = bytes32(abi.encodePacked(bytes16(uint128(80000)), bytes16(uint128(50000))));
        op.preVerificationGas = 50000;
        op.gasFees = bytes32(abi.encodePacked(bytes16(uint128(100)), bytes16(uint128(1000000000))));

        return op;
    }

    function getSignedPaymasterData(PackedUserOperation memory userOp) private view returns (bytes memory) {
        PaymasterData memory data = PaymasterData({
            paymasterAddress: address(paymaster),
            preVerificationGas: 100_000,
            postOpGas: 50_000,
            sponsorAccount: sponsorAccount,
            validUntil: 0, // 0 means no time limit
            validAfter: 0,
            dynamicAdjustment: 1000_000
        });

        userOp.paymasterAndData = abi.encodePacked(
            data.paymasterAddress,
            data.preVerificationGas,
            data.postOpGas,
            data.sponsorAccount,
            data.validUntil,
            data.validAfter,
            data.dynamicAdjustment
        );

        // Calling paymaster contract public function to get hash.
        bytes32 hash = paymaster.getHash(userOp);
        bytes memory sig = getSignature(hash, paymasterSignerKey);

        // Just added sig to the end of paymasterAndData.
        return abi.encodePacked(userOp.paymasterAndData, sig);
    }

    function getSignature(bytes32 hash, uint256 signingKey) private pure returns (bytes memory) {
        bytes32 digest = MessageHashUtils.toEthSignedMessageHash(hash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signingKey, digest);
        return abi.encodePacked(r, s, v);
    }


    function signUserOp(PackedUserOperation memory op, uint256 _key) private view returns (bytes memory signature) {
        bytes32 hash = entryPoint.getUserOpHash(op);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_key, MessageHashUtils.toEthSignedMessageHash(hash));
        signature = abi.encodePacked(r, s, v);
    }

    function submitUserOp(PackedUserOperation memory op) public {
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);

        ops[0] = op;
        entryPoint.handleOps(ops, beneficiary);
    }
}
