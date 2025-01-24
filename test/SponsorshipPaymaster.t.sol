// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {
    SimpleAccountFactory, SimpleAccount
} from "@account-abstraction/v0_7/contracts/samples/SimpleAccountFactory.sol";
import {PackedUserOperation} from "@account-abstraction/v0_7/contracts/interfaces/PackedUserOperation.sol";
import {EntryPoint} from "@account-abstraction/v0_7/contracts/core/EntryPoint.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {SponsorshipPaymaster} from "../src/sponsorship/SponsorshipPaymaster.sol";
import {TestCounter} from "./TestCounter.sol";

struct PaymasterData {
    address paymasterAddress;
    uint128 preVerificationGas;
    uint128 postOpGas;
    uint48 validUntil;
    uint48 validAfter;
}

contract SponsorshipPaymasterTest is Test {
    SponsorshipPaymaster paymaster;
    SimpleAccountFactory accountFactory;
    SimpleAccount account;
    EntryPoint entryPoint;
    TestCounter counter;

    address payable beneficiary;
    address paymasterOwner;
    address paymasterSigner;
    uint256 paymasterSignerKey;
    uint256 unauthorizedSignerKey;
    address user;
    uint256 userKey;

    function setUp() external {
        counter = new TestCounter();

        beneficiary = payable(makeAddr("beneficiary"));
        paymasterOwner = makeAddr("paymasterOwner");
        (paymasterSigner, paymasterSignerKey) = makeAddrAndKey("paymasterSigner");
        (, unauthorizedSignerKey) = makeAddrAndKey("unauthorizedSigner");
        (user, userKey) = makeAddrAndKey("user");

        entryPoint = new EntryPoint();
        accountFactory = new SimpleAccountFactory(entryPoint);
        account = accountFactory.createAccount(user, 0);

        // Set paymasterOwner as the msg.sender of next call, ensuring owner of Paymaster is set to paymasterOwner.
        vm.prank(paymasterOwner);
        paymaster = new SponsorshipPaymaster(address(entryPoint), new address[](0));
        paymaster.deposit{value: 10000e18}();

        vm.prank(paymasterOwner);
        paymaster.addSigner(paymasterSigner);
    }

    function testDeployment() external {
        vm.prank(paymasterOwner);
        SponsorshipPaymaster deployedPaymaster = new SponsorshipPaymaster(address(entryPoint), new address[](0));
        vm.prank(paymasterOwner);
        deployedPaymaster.addSigner(paymasterSigner);

        assertEq(deployedPaymaster.owner(), paymasterOwner);
        assertTrue(deployedPaymaster.signers(paymasterSigner));
    }

    function testSponsorshipSuccess() external {
        address sender = address(account);
        bytes memory callData = abi.encodeWithSelector(
            SimpleAccount.execute.selector, address(counter), 0, abi.encodeWithSelector(TestCounter.count.selector)
        );

        PackedUserOperation memory op = prepareUserOp(sender, callData);
        op.paymasterAndData = getSignedPaymasterData(op);
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
            validUntil: 0, // 0 means no time limit
            validAfter: 0
        });

        userOp.paymasterAndData = abi.encodePacked(
            data.paymasterAddress, data.preVerificationGas, data.postOpGas, data.validUntil, data.validAfter
        );

        // Calling paymaster contract public function to get hash.
        bytes32 hash = paymaster.getHash(userOp);
        bytes memory sig = getSignature(hash, paymasterSignerKey);

        // Just added sig to the end of paymasterAndData.
        return abi.encodePacked(
            data.paymasterAddress, data.preVerificationGas, data.postOpGas, data.validUntil, data.validAfter, sig
        );
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
