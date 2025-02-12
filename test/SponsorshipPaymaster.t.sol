// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {EntryPoint} from "@account-abstraction/contracts/core/EntryPoint.sol";
import {PackedUserOperation} from "@account-abstraction/contracts/interfaces/PackedUserOperation.sol";
import {SponsorshipPaymaster} from "../src/sponsorship/SponsorshipPaymaster.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {TestCounter} from "./TestCounter.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {SimpleAccountFactory, SimpleAccount} from "@account-abstraction/contracts/samples/SimpleAccountFactory.sol";
import {ISponsorshipPaymasterEventsAndErrors} from "../src/interfaces/ISponsorshipPaymasterEventsAndErrors.sol";

contract SponsorshipPaymasterTest is Test {
    SponsorshipPaymaster paymaster;
    EntryPoint entryPoint;
    TestCounter counter;
    SimpleAccountFactory accountFactory;
    SimpleAccount account;

    address payable beneficiary;
    address paymasterOwner;
    address paymasterSigner;
    uint256 paymasterSignerKey;
    address user;
    uint256 userKey;
    address sponsorAccount;
    uint256 public constant WITHDRAWAL_DELAY = 3600;

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
        uint32 feeMarkup;
    }

    function setUp() external {
        counter = new TestCounter();
        beneficiary = payable(makeAddr("beneficiary"));
        paymasterOwner = makeAddr("paymasterOwner");
        (paymasterSigner, paymasterSignerKey) = makeAddrAndKey("paymasterSigner");
        (user, userKey) = makeAddrAndKey("user");
        sponsorAccount = makeAddr("sponsorAccount");

        entryPoint = new EntryPoint();
        accountFactory = new SimpleAccountFactory(entryPoint);
        account = accountFactory.createAccount(user, 0);

        address[] memory signers = new address[](1);
        signers[0] = paymasterSigner;

        paymaster = new SponsorshipPaymaster(
            paymasterOwner, address(entryPoint), signers, beneficiary, 1 ether, WITHDRAWAL_DELAY, 100000
        );
        vm.deal(sponsorAccount, 10 ether);
    }

    function test_addNewSigner() external prankModifier(paymasterOwner) {
        address newSigner = makeAddr("newSigner");
        paymaster.addSigner(newSigner);
        assert(paymaster.isSigner(newSigner));
    }

    function test_removeSigner() external {
        address newSigner = makeAddr("newSigner");
        vm.startPrank(paymasterOwner);
        paymaster.addSigner(newSigner);
        assert(paymaster.isSigner(newSigner));
        paymaster.removeSigner(newSigner);
        assertEq(paymaster.isSigner(newSigner), false);
        vm.stopPrank();
    }

    function test_DepositFor() external {
        uint256 depositAmount = 10 ether;
        vm.prank(sponsorAccount);
        paymaster.depositFor{value: depositAmount}(sponsorAccount);
        assertEq(paymaster.getBalance(sponsorAccount), depositAmount);
    }

    function test_RevertIf_DepositIsZero() external {
        // Expect `LowDeposit(0, minDeposit)` custom error with correct parameters
        vm.expectRevert(abi.encodeWithSelector(ISponsorshipPaymasterEventsAndErrors.LowDeposit.selector, 0, 1 ether));
        vm.prank(sponsorAccount); // not necessary though. anyone can deposit
        paymaster.depositFor{value: 0}(sponsorAccount);
    }

    function test_RevertIf_TriesWithdrawToWithoutRequest() external prankModifier(sponsorAccount) {
        address withdrawAddress = makeAddr("withdrawAddress");
        vm.expectRevert(abi.encodeWithSelector(ISponsorshipPaymasterEventsAndErrors.SubmitRequestInstead.selector));
        paymaster.withdrawTo(payable(withdrawAddress), 1 ether);
    }

    function test_submitWithdrawalRequest_Fails_with_ZeroAmount() external prankModifier(sponsorAccount) {
        address withdrawAddress = makeAddr("withdrawAddress");
        vm.expectRevert(abi.encodeWithSelector(ISponsorshipPaymasterEventsAndErrors.CanNotWithdrawZeroAmount.selector));
        paymaster.requestWithdrawal(withdrawAddress, 0 ether);
    }

    function test_submitWithdrawalRequest_Fails_with_ZeroAddress() external prankModifier(sponsorAccount) {
        vm.expectRevert(abi.encodeWithSelector(ISponsorshipPaymasterEventsAndErrors.InvalidWithdrawalAddress.selector));
        paymaster.requestWithdrawal(address(0), 1 ether);
    }

    function test_executeWithdrawalRequest_Fails_with_NoRequestSubmitted() external prankModifier(sponsorAccount) {
        vm.expectRevert(abi.encodeWithSelector(ISponsorshipPaymasterEventsAndErrors.NoWithdrawalRequestSubmitted.selector, sponsorAccount));
        paymaster.executeWithdrawal(sponsorAccount);
    }

    function test_executeWithdrawalRequest_Reverts_If_Withdraws_TooSoon() external {
        uint256 withdrawalDelay = 10;

        vm.startPrank(paymasterOwner);
        paymaster.setWithdrawalDelay(withdrawalDelay);
        vm.stopPrank();

        uint256 depositAmount = 1 ether;
        uint256 withdrawAmount = 0.5 ether;

        paymaster.depositFor{ value: depositAmount }(sponsorAccount);
        assertEq(paymaster.getBalance(sponsorAccount), depositAmount);

        address withdrawAddress = makeAddr("withdrawAddress");
        
        vm.startPrank(sponsorAccount);
        paymaster.requestWithdrawal(withdrawAddress, withdrawAmount);
        uint256 requestTime = block.timestamp;
        vm.stopPrank();

        // Attempt to withdraw too soon
        vm.expectRevert(
            abi.encodeWithSelector(
                ISponsorshipPaymasterEventsAndErrors.WithdrawalTooSoon.selector,
                sponsorAccount,
                requestTime + withdrawalDelay
            )
        );

        paymaster.executeWithdrawal(sponsorAccount);
    }

    function test_executeWithdrawalRequest_Happy_Scenario() external {
        uint256 depositAmount = 1 ether;
        paymaster.depositFor{ value: depositAmount }(sponsorAccount);
        assertEq(paymaster.getBalance(sponsorAccount), depositAmount);

        address withdrawAddress = makeAddr("withdrawAddress");
        
        vm.startPrank(sponsorAccount);
        paymaster.requestWithdrawal(withdrawAddress, depositAmount);
        vm.stopPrank();

        vm.warp(block.timestamp + WITHDRAWAL_DELAY + 1);
        uint256 sponsorAccountPaymasterBalanceBefore = paymaster.getBalance(sponsorAccount);
        uint256 withdrawAddressBalanceBefore = withdrawAddress.balance;
        paymaster.executeWithdrawal(sponsorAccount);
        uint256 sponsorAccountPaymasterBalanceAfter = paymaster.getBalance(sponsorAccount);
        uint256 withdrawAddressBalanceAfter = withdrawAddress.balance;
        assertEq(sponsorAccountPaymasterBalanceAfter, sponsorAccountPaymasterBalanceBefore - depositAmount);
        assertEq(withdrawAddressBalanceAfter, withdrawAddressBalanceBefore + depositAmount);
        // can not withdraw again
        vm.expectRevert(abi.encodeWithSelector(ISponsorshipPaymasterEventsAndErrors.NoWithdrawalRequestSubmitted.selector, sponsorAccount));
        paymaster.executeWithdrawal(sponsorAccount);
    }

    // Note: If we send an userOp between submit request (full amount withdraw) and execute request then it will withdraw whatever is left.
    // TODO: test_executeWithdrawalRequest_Withdraws_WhateverIsLeft

    function test_SetUnaccountedGas() external prankModifier(paymasterOwner) {
        uint256 newUnaccountedGas = 80_000;
        paymaster.setUnaccountedGas(newUnaccountedGas);
        assertEq(paymaster.unaccountedGas(), newUnaccountedGas);
    }

    function test_RevertIf_SetUnaccountedGasTooHigh() external prankModifier(paymasterOwner) {
        vm.expectRevert(ISponsorshipPaymasterEventsAndErrors.UnaccountedGasTooHigh.selector);
        paymaster.setUnaccountedGas(250_000);
    }

    function testSponsorshipSuccess() external {
        vm.prank(sponsorAccount);
        paymaster.depositFor{value: 10 ether}(sponsorAccount);

        address sender = address(account);
        bytes memory callData = abi.encodeWithSelector(
            SimpleAccount.execute.selector, address(counter), 0, abi.encodeWithSelector(TestCounter.count.selector)
        );

        // Prepare user operation
        PackedUserOperation memory op = prepareUserOp(sender, callData);
        // Get signed paymaster data
        bytes memory paymasterData = getSignedPaymasterData(op);
        // Set paymaster data
        op.paymasterAndData = paymasterData;
        // Sign user operation
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
            feeMarkup: 1000_000
        });

        userOp.paymasterAndData = abi.encodePacked(
            data.paymasterAddress,
            data.preVerificationGas,
            data.postOpGas,
            data.sponsorAccount,
            data.validUntil,
            data.validAfter,
            data.feeMarkup
        );

        // Get hash of paymaster data
        bytes32 hash = paymaster.getHash(userOp, sponsorAccount, 0, 0, 1000_000);
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
