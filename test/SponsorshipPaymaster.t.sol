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
    uint256 constant WITHDRAWAL_DELAY = 10;

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

    function test_RequestWithdrawal() external {
        uint256 depositAmount = 5 ether;
        vm.prank(sponsorAccount);
        paymaster.depositFor{value: depositAmount}(sponsorAccount);

        vm.prank(sponsorAccount);
        paymaster.requestWithdrawal(3 ether);

        assertEq(paymaster.withdrawalRequests(sponsorAccount), 3 ether);
        assertEq(paymaster.lastWithdrawalTimestamp(sponsorAccount), block.timestamp);
    }

    function test_RevertIf_ExecuteWithdrawalWithNoRequest() external {
        // Expect `NoWithdrawalRequest` custom error with the user's address as parameter
        vm.expectRevert(
            abi.encodeWithSelector(ISponsorshipPaymasterEventsAndErrors.NoWithdrawalRequest.selector, sponsorAccount)
        );
        vm.prank(sponsorAccount);
        paymaster.executeWithdrawal(sponsorAccount);
    }

    function test_RevertIf_RequestWithdrawalTooSoon() external {
        uint256 depositAmount = 5 ether;
        uint256 withdrawalAmount = 3 ether;
        uint256 withdrawalDelay = 10;

        // Set withdrawal delay in the contract
        vm.prank(paymasterOwner);
        paymaster.setWithdrawalDelay(withdrawalDelay);

        // Sponsor deposits funds
        vm.prank(sponsorAccount);
        paymaster.depositFor{value: depositAmount}(sponsorAccount);

        assertEq(paymaster.getBalance(sponsorAccount), depositAmount);

        // Sponsor requests withdrawal
        vm.prank(sponsorAccount);
        paymaster.requestWithdrawal(withdrawalAmount);

        // Ensure withdrawal request is set
        assertEq(paymaster.withdrawalRequests(sponsorAccount), withdrawalAmount);
        uint256 requestTime = block.timestamp;
        assertEq(paymaster.lastWithdrawalTimestamp(sponsorAccount), requestTime);

        // Attempt to withdraw too soon
        vm.expectRevert(
            abi.encodeWithSelector(
                ISponsorshipPaymasterEventsAndErrors.WithdrawalTooSoon.selector,
                sponsorAccount,
                requestTime + withdrawalDelay
            )
        );

        vm.prank(sponsorAccount);
        paymaster.executeWithdrawal(sponsorAccount);
    }

    function testExecuteWithdrawal() external {
        uint256 depositAmount = 5 ether;
        uint256 withdrawalAmount = 3 ether;
        uint256 withdrawalDelay = 10;
        // Sponsor deposits funds
        vm.prank(sponsorAccount);
        paymaster.depositFor{value: depositAmount}(sponsorAccount);

        assertEq(paymaster.getBalance(sponsorAccount), depositAmount); // Ensure deposit success
        // Sponsor requests withdrawal
        vm.prank(sponsorAccount);
        paymaster.requestWithdrawal(withdrawalAmount);
        assertEq(paymaster.withdrawalRequests(sponsorAccount), 3 ether); // Ensure withdrawal request is set
        assertEq(paymaster.lastWithdrawalTimestamp(sponsorAccount), block.timestamp); // Ensure withdrawal timestamp is set

        vm.warp(block.timestamp + withdrawalDelay + 200);

        uint256 sponsorBalanceBefore = sponsorAccount.balance;

        // Execute withdrawal
        vm.prank(sponsorAccount);
        paymaster.executeWithdrawal(sponsorAccount);

        // Ensure withdrawal request is cleared
        assertEq(paymaster.withdrawalRequests(sponsorAccount), 0);

        // Ensure withdrawal timestamp is cleared
        assertEq(paymaster.lastWithdrawalTimestamp(sponsorAccount), 0);

        // Ensure user's balance is reduced
        assertEq(paymaster.getBalance(sponsorAccount), depositAmount - withdrawalAmount);

        // Ensure funds were received by sponsor
        assertEq(sponsorAccount.balance, sponsorBalanceBefore + withdrawalAmount);
    }

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
