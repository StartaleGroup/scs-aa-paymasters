// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.28;

import "../../TestBase.sol";
import {ISponsorshipPaymaster} from "../../../../src/interfaces/ISponsorshipPaymaster.sol";
import {SponsorshipPaymaster} from "../../../../src/sponsorship/SponsorshipPaymaster.sol";
import {ISponsorshipPaymasterEventsAndErrors} from "../../../../src/interfaces/ISponsorshipPaymasterEventsAndErrors.sol";
import "@account-abstraction/contracts/interfaces/IStakeManager.sol";
import {MultiSigners} from "../../../../src/sponsorship/MultiSigners.sol";
import {TestCounter} from "../../TestCounter.sol";

contract TestSponsorshipPaymaster is TestBase {
    SponsorshipPaymaster public sponsorshipPaymaster;

    uint256 public constant WITHDRAWAL_DELAY = 3600;
    uint256 public constant MIN_DEPOSIT = 1e15;
    uint256 public constant UNACCOUNTED_GAS = 50e3;

    function setUp() public {
        setupPaymasterTestEnvironment();
        // Deploy Sponsorship Paymaster
        address[] memory signers = new address[](2);
        signers[0] = PAYMASTER_SIGNER_A.addr;
        signers[1] = PAYMASTER_SIGNER_B.addr;
        sponsorshipPaymaster = new SponsorshipPaymaster({
            _owner: PAYMASTER_OWNER.addr,
            _entryPoint: address(ENTRYPOINT),
            _signers: signers,
            _feeCollector: PAYMASTER_FEE_COLLECTOR.addr,
            _minDeposit: MIN_DEPOSIT,
            _withdrawalDelay: WITHDRAWAL_DELAY,
            _unaccountedGas: UNACCOUNTED_GAS
        });
    }

    function test_Deploy() external {
        address[] memory signers = new address[](2);
        signers[0] = PAYMASTER_SIGNER_A.addr;
        signers[1] = PAYMASTER_SIGNER_B.addr;
        SponsorshipPaymaster testArtifact = new SponsorshipPaymaster(
            PAYMASTER_OWNER.addr, address(ENTRYPOINT), signers, PAYMASTER_FEE_COLLECTOR.addr, 1e15, 3600, 50e3
        );
        assertEq(testArtifact.owner(), PAYMASTER_OWNER.addr);
        assertEq(address(testArtifact.entryPoint()), ENTRYPOINT_ADDRESS);
        assertEq(testArtifact.feeCollector(), PAYMASTER_FEE_COLLECTOR.addr);
        assertEq(testArtifact.unaccountedGas(), 50e3);
    }

    function test_RevertIf_DeployWithSignerSetToZero() external {
        address[] memory signers = new address[](2);
        signers[0] = PAYMASTER_SIGNER_A.addr;
        signers[1] = address(0);
        vm.expectRevert(abi.encodeWithSelector(MultiSigners.SignerAddressCannotBeZero.selector));
        new SponsorshipPaymaster(
            PAYMASTER_OWNER.addr, address(ENTRYPOINT), signers, PAYMASTER_FEE_COLLECTOR.addr, 1e15, 3600, 50e3
        );
    }

    function test_RevertIf_DeployWithSignerAsContract() external {
        address[] memory signers = new address[](2);
        signers[0] = PAYMASTER_SIGNER_A.addr;
        signers[1] = address(new TestCounter());
        vm.expectRevert(abi.encodeWithSelector(MultiSigners.SignerAddressCannotBeContract.selector));
        new SponsorshipPaymaster(
            PAYMASTER_OWNER.addr, address(ENTRYPOINT), signers, PAYMASTER_FEE_COLLECTOR.addr, 1e15, 3600, 50e3
        );
    }

    function test_RevertIf_DeployWithFeeCollectorSetToZero() external {
        address[] memory signers = new address[](2);
        signers[0] = PAYMASTER_SIGNER_A.addr;
        signers[1] = PAYMASTER_SIGNER_B.addr;
        vm.expectRevert(abi.encodeWithSelector(ISponsorshipPaymasterEventsAndErrors.FeeCollectorCanNotBeZero.selector));
        new SponsorshipPaymaster(PAYMASTER_OWNER.addr, address(ENTRYPOINT), signers, address(0), 1e15, 3600, 50e3);
    }

    function test_RevertIf_DeployWithFeeCollectorAsContract() external {
        TestCounter testCounter = new TestCounter();
        address[] memory signers = new address[](2);
        signers[0] = PAYMASTER_SIGNER_A.addr;
        signers[1] = PAYMASTER_SIGNER_B.addr;
        vm.expectRevert(
            abi.encodeWithSelector(ISponsorshipPaymasterEventsAndErrors.FeeCollectorCanNotBeContract.selector)
        );
        new SponsorshipPaymaster(
            PAYMASTER_OWNER.addr, address(ENTRYPOINT), signers, address(testCounter), 1e15, 3600, 50e3
        );
    }

    function test_RevertIf_DeployWithUnaccountedGasCostTooHigh() external {
        address[] memory signers = new address[](2);
        signers[0] = PAYMASTER_SIGNER_A.addr;
        signers[1] = PAYMASTER_SIGNER_B.addr;
        vm.expectRevert(abi.encodeWithSelector(ISponsorshipPaymasterEventsAndErrors.UnaccountedGasTooHigh.selector));
        new SponsorshipPaymaster(
            PAYMASTER_OWNER.addr, address(ENTRYPOINT), signers, PAYMASTER_FEE_COLLECTOR.addr, 1e15, 3600, 200e3
        );
    }

    function test_CheckInitialPaymasterState() external view {
        assertEq(sponsorshipPaymaster.owner(), PAYMASTER_OWNER.addr);
        assertEq(address(sponsorshipPaymaster.entryPoint()), address(ENTRYPOINT));
        assertEq(sponsorshipPaymaster.isSigner(PAYMASTER_SIGNER_A.addr), true);
        assertEq(sponsorshipPaymaster.isSigner(PAYMASTER_SIGNER_B.addr), true);
        assertEq(sponsorshipPaymaster.feeCollector(), PAYMASTER_FEE_COLLECTOR.addr);
        assertEq(sponsorshipPaymaster.unaccountedGas(), UNACCOUNTED_GAS);
    }

    function test_OwnershipTransfer() external prankModifier(PAYMASTER_OWNER.addr) {
        vm.expectEmit(true, true, false, true, address(sponsorshipPaymaster));
        emit OwnershipTransferred(PAYMASTER_OWNER.addr, BOB_ADDRESS);
        sponsorshipPaymaster.transferOwnership(BOB_ADDRESS);
        assertEq(sponsorshipPaymaster.owner(), BOB_ADDRESS);
    }

    function test_RevertIf_OwnershipTransferToZeroAddress() external prankModifier(PAYMASTER_OWNER.addr) {
        vm.expectRevert(abi.encodeWithSelector(NewOwnerIsZeroAddress.selector));
        sponsorshipPaymaster.transferOwnership(address(0));
    }

    function test_Success_TwoStepOwnershipTransfer() external {
        assertEq(sponsorshipPaymaster.owner(), PAYMASTER_OWNER.addr);
        // BOB will request ownership transfer
        vm.startPrank(BOB_ADDRESS);
        vm.expectEmit(true, true, false, true, address(sponsorshipPaymaster));
        emit OwnershipHandoverRequested(BOB_ADDRESS);
        sponsorshipPaymaster.requestOwnershipHandover();
        vm.stopPrank();

        // Paymaster owner will accept the ownership transfer
        vm.startPrank(PAYMASTER_OWNER.addr);
        // Owner can also cancel it. but if passed with pendingOwner address within 48 hours it will be performed.
        vm.expectEmit(true, true, false, true, address(sponsorshipPaymaster));
        emit OwnershipTransferred(PAYMASTER_OWNER.addr, BOB_ADDRESS);
        sponsorshipPaymaster.completeOwnershipHandover(BOB_ADDRESS);
        vm.stopPrank();

        assertEq(sponsorshipPaymaster.owner(), BOB_ADDRESS);
    }

    function test_Failure_TwoStepOwnershipTransferWithdrawn() external {
        assertEq(sponsorshipPaymaster.owner(), PAYMASTER_OWNER.addr);
        // BOB will request ownership transfer
        vm.startPrank(BOB_ADDRESS);
        vm.expectEmit(true, true, false, true, address(sponsorshipPaymaster));
        emit OwnershipHandoverRequested(BOB_ADDRESS);
        sponsorshipPaymaster.requestOwnershipHandover();

        // BOB decides to cancel the ownership transfer
        sponsorshipPaymaster.cancelOwnershipHandover();
        vm.stopPrank();

        // Now if owner tries to complete it doesn't work
        vm.startPrank(PAYMASTER_OWNER.addr);
        vm.expectRevert(abi.encodeWithSelector(NoHandoverRequest.selector));
        sponsorshipPaymaster.completeOwnershipHandover(BOB_ADDRESS);
        vm.stopPrank();

        assertEq(sponsorshipPaymaster.owner(), PAYMASTER_OWNER.addr);
    }

    function test_Failure_TwoStepOwnershipTransferExpired() external {
        assertEq(sponsorshipPaymaster.owner(), PAYMASTER_OWNER.addr);
        // BOB will request ownership transfer
        vm.startPrank(BOB_ADDRESS);
        vm.expectEmit(true, true, false, true, address(sponsorshipPaymaster));
        emit OwnershipHandoverRequested(BOB_ADDRESS);
        sponsorshipPaymaster.requestOwnershipHandover();
        vm.stopPrank();

        // More than 48 hours passed
        vm.warp(block.timestamp + 49 hours);

        // Now if owner tries to complete it doesn't work
        vm.startPrank(PAYMASTER_OWNER.addr);
        // Reverts now
        vm.expectRevert(abi.encodeWithSelector(NoHandoverRequest.selector));
        sponsorshipPaymaster.completeOwnershipHandover(BOB_ADDRESS);
        vm.stopPrank();

        // Stil owner is the same
        assertEq(sponsorshipPaymaster.owner(), PAYMASTER_OWNER.addr);
    }

    function test_RevertIf_UnauthorizedOwnershipTransfer() external {
        vm.expectRevert(abi.encodeWithSelector(Unauthorized.selector));
        sponsorshipPaymaster.transferOwnership(BOB_ADDRESS);
    }

    function test_AddVerifyingSigner() external prankModifier(PAYMASTER_OWNER.addr) {
        assertEq(sponsorshipPaymaster.isSigner(PAYMASTER_SIGNER_A.addr), true);
        assertEq(sponsorshipPaymaster.isSigner(PAYMASTER_SIGNER_B.addr), true);
        address newSigner = address(0x123);
        assertEq(sponsorshipPaymaster.isSigner(newSigner), false);
        vm.expectEmit(true, true, false, true, address(sponsorshipPaymaster));
        emit MultiSigners.SignerAdded(newSigner);
        sponsorshipPaymaster.addSigner(newSigner);
        assertEq(sponsorshipPaymaster.isSigner(newSigner), true);
    }

    function test_RemoveVerifyingSigner() external prankModifier(PAYMASTER_OWNER.addr) {
        assertEq(sponsorshipPaymaster.isSigner(PAYMASTER_SIGNER_A.addr), true);
        assertEq(sponsorshipPaymaster.isSigner(PAYMASTER_SIGNER_B.addr), true);
        vm.expectEmit(true, true, false, true, address(sponsorshipPaymaster));
        emit MultiSigners.SignerRemoved(PAYMASTER_SIGNER_B.addr);
        sponsorshipPaymaster.removeSigner(PAYMASTER_SIGNER_B.addr);
        assertEq(sponsorshipPaymaster.isSigner(PAYMASTER_SIGNER_B.addr), false);
    }

    function test_RevertIf_AddVerifyingSignerToZeroAddress() external prankModifier(PAYMASTER_OWNER.addr) {
        assertEq(sponsorshipPaymaster.isSigner(PAYMASTER_SIGNER_A.addr), true);
        assertEq(sponsorshipPaymaster.isSigner(PAYMASTER_SIGNER_B.addr), true);
        vm.expectRevert(abi.encodeWithSelector(MultiSigners.SignerAddressCannotBeZero.selector));
        sponsorshipPaymaster.addSigner(address(0));
    }

    function test_SetFeeCollector() external prankModifier(PAYMASTER_OWNER.addr) {
        address newFeeCollector = address(0x456);
        vm.expectEmit(true, true, false, true, address(sponsorshipPaymaster));
        emit ISponsorshipPaymasterEventsAndErrors.FeeCollectorChanged(PAYMASTER_FEE_COLLECTOR.addr, newFeeCollector);
        sponsorshipPaymaster.setFeeCollector(newFeeCollector);
        // Assert that the new fee collector is set.
        assertEq(sponsorshipPaymaster.feeCollector(), newFeeCollector);
    }

    function test_RevertIf_SetFeeCollectorToZeroAddress() external prankModifier(PAYMASTER_OWNER.addr) {
        vm.expectRevert(abi.encodeWithSelector(ISponsorshipPaymasterEventsAndErrors.FeeCollectorCanNotBeZero.selector));
        sponsorshipPaymaster.setFeeCollector(address(0));
    }

    function test_RevertIf_UnauthorizedSetFeeCollector() external {
        vm.startPrank(address(0x789)); // Impersonate an unauthorized address.
        vm.expectRevert(abi.encodeWithSelector(Unauthorized.selector));
        sponsorshipPaymaster.setFeeCollector(address(0x456));
        vm.stopPrank();
    }

    function test_RevertIf_SetUnaccountedGasToHigh() external prankModifier(PAYMASTER_OWNER.addr) {
        uint256 highGasLimit = 100_000_000; // Assuming this is higher than the maximum allowed.
        vm.expectRevert(abi.encodeWithSelector(ISponsorshipPaymasterEventsAndErrors.UnaccountedGasTooHigh.selector));
        sponsorshipPaymaster.setUnaccountedGas(highGasLimit);
    }

    function test_RevertIf_DepositForZeroAddress() external {
        vm.expectRevert(abi.encodeWithSelector(ISponsorshipPaymasterEventsAndErrors.InvalidDepositAddress.selector));
        sponsorshipPaymaster.depositFor{value: 1 ether}(address(0));
    }

    function test_RevertIf_DepositForZeroValue() external {
        vm.expectRevert(
            abi.encodeWithSelector(ISponsorshipPaymasterEventsAndErrors.LowDeposit.selector, 0, MIN_DEPOSIT)
        );
        sponsorshipPaymaster.depositFor{value: 0}(address(0x123));
    }

    function test_RevertIf_DepositCalled() external {
        vm.expectRevert(abi.encodeWithSelector(ISponsorshipPaymasterEventsAndErrors.UseDepositForInstead.selector));
        sponsorshipPaymaster.deposit();
    }

    // test_RevertIf_TriesWithdrawToWithoutRequest
    // test_submitWithdrawalRequest_Fails_with_ZeroAmount
    // test_submitWithdrawalRequest_Fails_with_ZeroAddress
    // test_submitWithdrawalRequest_Fails_If_not_enough_balance
    // test_executeWithdrawalRequest_Fails_with_NoRequestSubmitted
    // test_cancelWithdrawalRequest_Success
    // test_submitWithdrawalRequest_Happy_Scenario
    // test_executeWithdrawalRequest_Withdraws_WhateverIsLeft
    // test_depositFor_RevertsIf_DepositIsLessThanMinDeposit

    // test_ValidatePaymasterAndPostOpWithPriceMarkup
    // test_ValidatePaymasterAndPostOpWithPriceMarkup_NonEmptyCalldata
    // test_RevertIf_ValidatePaymasterUserOpWithIncorrectSignatureLength
    // test_RevertIf_ValidatePaymasterUserOpWithInvalidPriceMarkUp
    // test_RevertIf_ValidatePaymasterUserOpWithInsufficientDeposit

    // test_Receive
    // test_WithdrawEth

    // test_RevertIf_WithdrawEthExceedsBalance
    // test_WithdrawErc20
    // test_RevertIf_WithdrawErc20ToZeroAddress
    // test_ParsePaymasterAndData

    function test_SetUnaccountedGas() external prankModifier(PAYMASTER_OWNER.addr) {
        uint256 initialUnaccountedGas = sponsorshipPaymaster.unaccountedGas();
        uint256 newUnaccountedGas = 80_000;
        vm.expectEmit(true, true, false, true, address(sponsorshipPaymaster));
        emit ISponsorshipPaymasterEventsAndErrors.UnaccountedGasChanged(initialUnaccountedGas, newUnaccountedGas);
        sponsorshipPaymaster.setUnaccountedGas(newUnaccountedGas);
        uint256 resultingUnaccountedGas = sponsorshipPaymaster.unaccountedGas();
        assertEq(resultingUnaccountedGas, newUnaccountedGas);
    }

    function test_DepositFor() external {
        uint256 sponsorAccountBalance = sponsorshipPaymaster.getBalance(SPONSOR_ACCOUNT.addr);
        uint256 depositAmount = 10 ether;
        assertEq(sponsorAccountBalance, 0 ether);
        vm.expectEmit(true, true, false, true, address(sponsorshipPaymaster));
        emit ISponsorshipPaymasterEventsAndErrors.DepositAdded(SPONSOR_ACCOUNT.addr, depositAmount);
        sponsorshipPaymaster.depositFor{value: depositAmount}(SPONSOR_ACCOUNT.addr);
        sponsorAccountBalance = sponsorshipPaymaster.getBalance(SPONSOR_ACCOUNT.addr);
        assertEq(sponsorAccountBalance, depositAmount);
    }

    function getGasLimit(PackedUserOperation calldata userOp) public pure returns (uint256) {
        uint256 PAYMASTER_POSTOP_GAS_OFFSET = 36;
        uint256 PAYMASTER_DATA_OFFSET = 52;
        return uint128(uint256(userOp.accountGasLimits))
            + uint128(bytes16(userOp.paymasterAndData[PAYMASTER_POSTOP_GAS_OFFSET:PAYMASTER_DATA_OFFSET]));
    }

    function test_ValidatePaymasterAndPostOpWithoutPriceMarkup() external {
        sponsorshipPaymaster.depositFor{value: 10 ether}(SPONSOR_ACCOUNT.addr);

        startPrank(PAYMASTER_OWNER.addr);
        sponsorshipPaymaster.setUnaccountedGas(50_000);
        stopPrank();

        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        // fee markup of 1e6
        (PackedUserOperation memory userOp, bytes32 userOpHash) =
            createUserOpWithSponsorshipPaymaster(ALICE, sponsorshipPaymaster, 1e6, 55_000);
        ops[0] = userOp;

        uint256 initialBundlerBalance = BUNDLER.addr.balance;
        uint256 initialPaymasterEpBalance = sponsorshipPaymaster.getDeposit();
        uint256 initialDappPaymasterBalance = sponsorshipPaymaster.getBalance(SPONSOR_ACCOUNT.addr);
        uint256 initialFeeCollectorBalance = sponsorshipPaymaster.getBalance(PAYMASTER_FEE_COLLECTOR.addr);

        // submit userops
        vm.expectEmit(true, false, false, false, address(sponsorshipPaymaster));
        emit ISponsorshipPaymasterEventsAndErrors.GasBalanceDeducted(
            SPONSOR_ACCOUNT.addr, 0, 0, IPaymaster.PostOpMode.opSucceeded
        );
        startPrank(BUNDLER.addr);
        ENTRYPOINT.handleOps(ops, payable(BUNDLER.addr));
        stopPrank();

        // Calculate and assert price markups and gas payments
        // calculateAndAssertAdjustments(...
    }
}
