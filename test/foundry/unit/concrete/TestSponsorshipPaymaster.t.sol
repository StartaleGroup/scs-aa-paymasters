// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.28;

import "../../TestBase.sol";
import {ISponsorshipPaymaster} from "../../../../src/interfaces/ISponsorshipPaymaster.sol";
import {SponsorshipPaymaster} from "../../../../src/sponsorship/SponsorshipPaymaster.sol";
import {ISponsorshipPaymasterEventsAndErrors} from "../../../../src/interfaces/ISponsorshipPaymasterEventsAndErrors.sol";
import "@account-abstraction/contracts/interfaces/IStakeManager.sol";
import {MultiSigners} from "../../../../src/sponsorship/MultiSigners.sol";
import {TestCounter} from "../../TestCounter.sol";
import {MockToken} from "../../mock/MockToken.sol";

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

    function test_RevertIf_TriesWithdrawToWithoutRequest() external prankModifier(SPONSOR_ACCOUNT.addr) {
        vm.expectRevert(abi.encodeWithSelector(ISponsorshipPaymasterEventsAndErrors.SubmitRequestInstead.selector));
        sponsorshipPaymaster.withdrawTo(payable(BOB_ADDRESS), 1 ether);
    }

    function test_submitWithdrawalRequest_Fails_with_ZeroAmount() external prankModifier(SPONSOR_ACCOUNT.addr) {
        vm.expectRevert(abi.encodeWithSelector(ISponsorshipPaymasterEventsAndErrors.CanNotWithdrawZeroAmount.selector));
        sponsorshipPaymaster.requestWithdrawal(BOB_ADDRESS, 0 ether);
    }

    function test_submitWithdrawalRequest_Fails_with_ZeroAddress() external prankModifier(SPONSOR_ACCOUNT.addr) {
        vm.expectRevert(abi.encodeWithSelector(ISponsorshipPaymasterEventsAndErrors.InvalidWithdrawalAddress.selector));
        sponsorshipPaymaster.requestWithdrawal(address(0), 1 ether);
    }

    function test_submitWithdrawalRequest_Fails_If_not_enough_balance() external prankModifier(SPONSOR_ACCOUNT.addr) {
        uint256 depositAmount = 1 ether;
        sponsorshipPaymaster.depositFor{value: depositAmount}(SPONSOR_ACCOUNT.addr);
        vm.expectRevert(
            abi.encodeWithSelector(
                ISponsorshipPaymasterEventsAndErrors.InsufficientFunds.selector,
                SPONSOR_ACCOUNT.addr,
                sponsorshipPaymaster.getBalance(SPONSOR_ACCOUNT.addr),
                depositAmount + 1
            )
        );
        sponsorshipPaymaster.requestWithdrawal(BOB_ADDRESS, depositAmount + 1);
    }

    function test_executeWithdrawalRequest_Fails_with_NoRequestSubmitted()
        external
        prankModifier(SPONSOR_ACCOUNT.addr)
    {
        vm.expectRevert(
            abi.encodeWithSelector(
                ISponsorshipPaymasterEventsAndErrors.NoWithdrawalRequestSubmitted.selector, SPONSOR_ACCOUNT.addr
            )
        );
        sponsorshipPaymaster.executeWithdrawal(SPONSOR_ACCOUNT.addr);
    }

    function test_submitWithdrawalRequest_Happy_Scenario() external prankModifier(SPONSOR_ACCOUNT.addr) {
        uint256 depositAmount = 1 ether;
        sponsorshipPaymaster.depositFor{value: depositAmount}(SPONSOR_ACCOUNT.addr);
        sponsorshipPaymaster.requestWithdrawal(BOB_ADDRESS, depositAmount);
        vm.warp(block.timestamp + WITHDRAWAL_DELAY + 1);
        uint256 dappPaymasterBalanceBefore = sponsorshipPaymaster.getBalance(SPONSOR_ACCOUNT.addr);
        uint256 bobBalanceBefore = BOB_ADDRESS.balance;
        sponsorshipPaymaster.executeWithdrawal(SPONSOR_ACCOUNT.addr);
        uint256 dappPaymasterBalanceAfter = sponsorshipPaymaster.getBalance(SPONSOR_ACCOUNT.addr);
        uint256 bobBalanceAfter = BOB_ADDRESS.balance;
        assertEq(dappPaymasterBalanceAfter, dappPaymasterBalanceBefore - depositAmount);
        assertEq(bobBalanceAfter, bobBalanceBefore + depositAmount);
        // can not withdraw again
        vm.expectRevert(
            abi.encodeWithSelector(
                ISponsorshipPaymasterEventsAndErrors.NoWithdrawalRequestSubmitted.selector, SPONSOR_ACCOUNT.addr
            )
        );
        sponsorshipPaymaster.executeWithdrawal(SPONSOR_ACCOUNT.addr);
    }

    // try to use balance while request is cleared
    function test_executeWithdrawalRequest_Withdraws_WhateverIsLeft() external prankModifier(SPONSOR_ACCOUNT.addr) {
        uint256 depositAmount = 1 ether;
        sponsorshipPaymaster.depositFor{value: depositAmount}(SPONSOR_ACCOUNT.addr);
        sponsorshipPaymaster.requestWithdrawal(BOB_ADDRESS, depositAmount);

        //use balance of the paymaster
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        (PackedUserOperation memory userOp,) =
            createUserOpWithSponsorshipPaymaster(ALICE, sponsorshipPaymaster, 1e6, 55_000);
        ops[0] = userOp;
        startPrank(BUNDLER.addr);
        ENTRYPOINT.handleOps(ops, payable(BUNDLER.addr));
        stopPrank();

        uint256 dappPaymasterBalanceAfter = sponsorshipPaymaster.getBalance(SPONSOR_ACCOUNT.addr);
        assertLt(dappPaymasterBalanceAfter, depositAmount);
        uint256 bobBalanceBeforeWithdrawal = BOB_ADDRESS.balance;

        vm.warp(block.timestamp + WITHDRAWAL_DELAY + 1);
        sponsorshipPaymaster.executeWithdrawal(SPONSOR_ACCOUNT.addr);
        uint256 bobBalanceAfterWithdrawal = BOB_ADDRESS.balance;
        assertEq(bobBalanceAfterWithdrawal, bobBalanceBeforeWithdrawal + dappPaymasterBalanceAfter);
        assertEq(sponsorshipPaymaster.getBalance(SPONSOR_ACCOUNT.addr), 0 ether);
    }

    function test_RevertIf_ValidatePaymasterUserOpWithIncorrectSignatureLength() external {
        sponsorshipPaymaster.depositFor{value: 10 ether}(SPONSOR_ACCOUNT.addr);
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        PackedUserOperation memory userOp = buildUserOpWithCalldata(ALICE, "", 0, 0);

        uint32 priceMarkup = 1e6;

        SponsorshipPaymasterData memory pmData = SponsorshipPaymasterData({
            validationGasLimit: 100_000,
            postOpGasLimit: uint128(55_000),
            sponsorAccount: SPONSOR_ACCOUNT.addr,
            validUntil: uint48(block.timestamp + 1 days),
            validAfter: uint48(block.timestamp),
            feeMarkup: priceMarkup
        });

        (userOp.paymasterAndData,) =
            generateAndSignSponsorshipPaymasterData(userOp, PAYMASTER_SIGNER_A, sponsorshipPaymaster, pmData);
        userOp.signature = signUserOp(ALICE, userOp);

        userOp.paymasterAndData = excludeLastNBytes(userOp.paymasterAndData, 2);
        ops[0] = userOp;
        vm.expectRevert();
        // cast sig PaymasterSignatureLengthInvalid()
        // FailedOpWithRevert(0, "AA33 reverted", 0x90bc2302)
        ENTRYPOINT.handleOps(ops, payable(BUNDLER.addr));
    }

    function test_RevertIf_ValidatePaymasterUserOpWithInvalidPriceMarkUp() external {
        sponsorshipPaymaster.depositFor{value: 10 ether}(SPONSOR_ACCOUNT.addr);
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        PackedUserOperation memory userOp = buildUserOpWithCalldata(ALICE, "", 0, 0);

        uint32 priceMarkup = 3e6;

        SponsorshipPaymasterData memory pmData = SponsorshipPaymasterData({
            validationGasLimit: 100_000,
            postOpGasLimit: uint128(55_000),
            sponsorAccount: SPONSOR_ACCOUNT.addr,
            validUntil: uint48(block.timestamp + 1 days),
            validAfter: uint48(block.timestamp),
            feeMarkup: priceMarkup
        });

        (userOp.paymasterAndData,) =
            generateAndSignSponsorshipPaymasterData(userOp, PAYMASTER_SIGNER_A, sponsorshipPaymaster, pmData);
        userOp.signature = signUserOp(ALICE, userOp);
        ops[0] = userOp;
        vm.expectRevert();
        // cast sig InvalidPriceMarkup()
        // FailedOpWithRevert(0, "AA33 reverted", 0x280b6fdc)
        ENTRYPOINT.handleOps(ops, payable(BUNDLER.addr));
    }

    function test_RevertIf_ValidatePaymasterUserOpWithInsufficientDeposit() external {
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        PackedUserOperation memory userOp = buildUserOpWithCalldata(ALICE, "", 0, 0);
        uint32 priceMarkup = 1e6;
        SponsorshipPaymasterData memory pmData = SponsorshipPaymasterData({
            validationGasLimit: 100_000,
            postOpGasLimit: uint128(55_000),
            sponsorAccount: SPONSOR_ACCOUNT.addr,
            validUntil: uint48(block.timestamp + 1 days),
            validAfter: uint48(block.timestamp),
            feeMarkup: priceMarkup
        });
        (userOp.paymasterAndData,) =
            generateAndSignSponsorshipPaymasterData(userOp, PAYMASTER_SIGNER_A, sponsorshipPaymaster, pmData);
        userOp.signature = signUserOp(ALICE, userOp);
        ops[0] = userOp;
        vm.expectRevert();
        // FailedOp(0, "AA31 paymaster deposit too low")
        ENTRYPOINT.handleOps(ops, payable(BUNDLER.addr));
    }

    function test_depositFor_RevertsIf_DepositIsLessThanMinDeposit() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                ISponsorshipPaymasterEventsAndErrors.LowDeposit.selector, MIN_DEPOSIT - 1, MIN_DEPOSIT
            )
        );
        sponsorshipPaymaster.depositFor{value: MIN_DEPOSIT - 1}(SPONSOR_ACCOUNT.addr);
    }

    function test_Receive() external prankModifier(ALICE_ADDRESS) {
        uint256 initialPaymasterBalance = address(sponsorshipPaymaster).balance;
        uint256 sendAmount = 10 ether;

        (bool success,) = address(sponsorshipPaymaster).call{value: sendAmount}("");

        assert(success);
        uint256 resultingPaymasterBalance = address(sponsorshipPaymaster).balance;
        assertEq(resultingPaymasterBalance, initialPaymasterBalance + sendAmount);
    }

    function test_WithdrawEth() external prankModifier(PAYMASTER_OWNER.addr) {
        uint256 initialAliceBalance = ALICE_ADDRESS.balance;
        uint256 ethAmount = 10 ether;
        vm.deal(address(sponsorshipPaymaster), ethAmount);

        sponsorshipPaymaster.withdrawEth(payable(ALICE_ADDRESS), ethAmount);
        vm.stopPrank();

        assertEq(ALICE_ADDRESS.balance, initialAliceBalance + ethAmount);
        assertEq(address(sponsorshipPaymaster).balance, 0 ether);
    }

    function test_RevertIf_WithdrawEthExceedsBalance() external prankModifier(PAYMASTER_OWNER.addr) {
        uint256 ethAmount = 10 ether;
        vm.expectRevert(abi.encodeWithSelector(ISponsorshipPaymasterEventsAndErrors.WithdrawalFailed.selector));
        sponsorshipPaymaster.withdrawEth(payable(ALICE_ADDRESS), ethAmount);
    }

    function test_WithdrawErc20() external prankModifier(PAYMASTER_OWNER.addr) {
        MockToken token = new MockToken("Token", "TKN");
        uint256 mintAmount = 10 * (10 ** token.decimals());
        token.mint(address(sponsorshipPaymaster), mintAmount);

        assertEq(token.balanceOf(address(sponsorshipPaymaster)), mintAmount);
        assertEq(token.balanceOf(ALICE_ADDRESS), 0);

        vm.expectEmit(true, true, true, true, address(sponsorshipPaymaster));
        emit ISponsorshipPaymasterEventsAndErrors.TokensWithdrawn(
            address(token), ALICE_ADDRESS, PAYMASTER_OWNER.addr, mintAmount
        );
        sponsorshipPaymaster.withdrawERC20(token, ALICE_ADDRESS, mintAmount);

        assertEq(token.balanceOf(address(sponsorshipPaymaster)), 0);
        assertEq(token.balanceOf(ALICE_ADDRESS), mintAmount);
    }

    function test_RevertIf_WithdrawErc20ToZeroAddress() external prankModifier(PAYMASTER_OWNER.addr) {
        MockToken token = new MockToken("Token", "TKN");
        uint256 mintAmount = 10 * (10 ** token.decimals());
        token.mint(address(sponsorshipPaymaster), mintAmount);

        vm.expectRevert(abi.encodeWithSelector(ISponsorshipPaymasterEventsAndErrors.InvalidWithdrawalAddress.selector));
        sponsorshipPaymaster.withdrawERC20(token, address(0), mintAmount);
    }

    function test_ParsePaymasterAndData() external view {
        PackedUserOperation memory userOp = buildUserOpWithCalldata(ALICE, "", 0, 0);

        uint32 priceMarkup = 1e6;

        SponsorshipPaymasterData memory pmData = SponsorshipPaymasterData({
            validationGasLimit: 100_000,
            postOpGasLimit: uint128(55_000),
            sponsorAccount: SPONSOR_ACCOUNT.addr,
            validUntil: uint48(block.timestamp + 1 days),
            validAfter: uint48(block.timestamp),
            feeMarkup: priceMarkup
        });

        (userOp.paymasterAndData,) =
            generateAndSignSponsorshipPaymasterData(userOp, PAYMASTER_SIGNER_A, sponsorshipPaymaster, pmData);
        userOp.signature = signUserOp(ALICE, userOp);

        (
            address parsedSponsorAccount,
            uint48 parsedValidUntil,
            uint48 parsedValidAfter,
            uint32 parsedFeeMarkup,
            uint128 parsedPaymasterValidationGasLimit,
            uint128 parsedPaymasterPostOpGasLimit,
            bytes memory parsedSignature
        ) = sponsorshipPaymaster.parsePaymasterAndData(userOp.paymasterAndData);

        assertEq(SPONSOR_ACCOUNT.addr, parsedSponsorAccount);
        assertEq(pmData.validUntil, parsedValidUntil);
        assertEq(pmData.validAfter, parsedValidAfter);
        assertEq(pmData.feeMarkup, parsedFeeMarkup);
        assertEq(pmData.validationGasLimit, parsedPaymasterValidationGasLimit);
        assertEq(pmData.postOpGasLimit, parsedPaymasterPostOpGasLimit);
        assertEq(parsedSignature.length, userOp.signature.length);
    }

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

    // test_ValidatePaymasterAndPostOpWithPriceMarkup
    // test_ValidatePaymasterAndPostOpWithPriceMarkup_NonEmptyCalldata

    function test_ValidatePaymasterAndPostOpWithoutPriceMarkup() external {
        assertEq(sponsorshipPaymaster.getBalance(PAYMASTER_FEE_COLLECTOR.addr), 0);
        // Compute the storage slot for sponsorBalances[PAYMASTER_FEE_COLLECTOR.addr]
        // 3 is the slot # for sponsorBalances
        bytes32 mappingSlot = keccak256(abi.encode(PAYMASTER_FEE_COLLECTOR.addr, uint256(3)));
        uint256 anyBalance = 10000;
        // This will ensure we are warming the fee collector slot and we are doing calculations right way
        vm.store(address(sponsorshipPaymaster), mappingSlot, bytes32(anyBalance));
        assertEq(sponsorshipPaymaster.getBalance(PAYMASTER_FEE_COLLECTOR.addr), anyBalance);

        sponsorshipPaymaster.depositFor{value: 10 ether}(SPONSOR_ACCOUNT.addr);
        startPrank(PAYMASTER_OWNER.addr);
        sponsorshipPaymaster.setUnaccountedGas(11_000);
        stopPrank();

        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        // fee markup of 1e6
        (PackedUserOperation memory userOp, bytes32 userOpHash) =
            createUserOpWithSponsorshipPaymaster(ALICE, sponsorshipPaymaster, 1e6, 20_000);
        ops[0] = userOp;

        uint256 initialBundlerBalance = BUNDLER.addr.balance;
        uint256 initialPaymasterEpBalance = sponsorshipPaymaster.getDeposit();
        uint256 initialSponsorAccountPaymasterBalance = sponsorshipPaymaster.getBalance(SPONSOR_ACCOUNT.addr);
        uint256 initialFeeCollectorBalance = sponsorshipPaymaster.getBalance(PAYMASTER_FEE_COLLECTOR.addr);

        // submit userops
        vm.expectEmit(true, false, false, false, address(sponsorshipPaymaster));
        emit ISponsorshipPaymasterEventsAndErrors.GasBalanceDeducted(
            SPONSOR_ACCOUNT.addr, 0, 0, IPaymaster.PostOpMode.opSucceeded
        );
        startPrank(BUNDLER.addr);
        ENTRYPOINT.handleOps(ops, payable(BUNDLER.addr));
        stopPrank();

        // calculateAndAssertAdjustments(...
        uint256 totalGasFeePaid = BUNDLER.addr.balance - initialBundlerBalance;
        uint256 gasPaidBySponsor =
            initialSponsorAccountPaymasterBalance - sponsorshipPaymaster.getBalance(SPONSOR_ACCOUNT.addr);
        uint256 premiumEarnedByFeeCollector =
            sponsorshipPaymaster.getBalance(PAYMASTER_FEE_COLLECTOR.addr) - initialFeeCollectorBalance; // actualMarkup
        // must be zero here as we didn't charge any markup
        assertEq(premiumEarnedByFeeCollector, 0);

        // Assert that what paymaster paid is the same as what the bundler received
        assertEq(totalGasFeePaid, initialPaymasterEpBalance - sponsorshipPaymaster.getDeposit());

        // Calculate and assert price markups and gas payments

        // Gas paid by dapp is higher than paymaster
        assertGt(gasPaidBySponsor, totalGasFeePaid);

        // Ensure that max 2% difference between total gas paid + the adjustment premium and gas paid by dapp (from
        // paymaster)
        assertApproxEqRel(totalGasFeePaid + premiumEarnedByFeeCollector, gasPaidBySponsor, 0.02e18);
    }

    function test_ValidatePaymasterAndPostOpWithPriceMarkup() external {
        assertEq(sponsorshipPaymaster.getBalance(PAYMASTER_FEE_COLLECTOR.addr), 0);
        // Compute the storage slot for sponsorBalances[PAYMASTER_FEE_COLLECTOR.addr]
        // 3 is the slot # for sponsorBalances
        bytes32 mappingSlot = keccak256(abi.encode(PAYMASTER_FEE_COLLECTOR.addr, uint256(3)));
        uint256 anyBalance = 10000;
        // This will ensure we are warming the fee collector slot and we are doing calculations right way
        vm.store(address(sponsorshipPaymaster), mappingSlot, bytes32(anyBalance));
        assertEq(sponsorshipPaymaster.getBalance(PAYMASTER_FEE_COLLECTOR.addr), anyBalance);

        sponsorshipPaymaster.depositFor{value: 10 ether}(SPONSOR_ACCOUNT.addr);
        startPrank(PAYMASTER_OWNER.addr);
        sponsorshipPaymaster.setUnaccountedGas(11_000);
        stopPrank();

        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        // fee markup of 1.1e6
        uint32 feeMarkup = 1.1e6;
        (PackedUserOperation memory userOp, bytes32 userOpHash) =
            createUserOpWithSponsorshipPaymaster(ALICE, sponsorshipPaymaster, feeMarkup, 20_000);
        ops[0] = userOp;

        uint256 initialBundlerBalance = BUNDLER.addr.balance;
        uint256 initialPaymasterEpBalance = sponsorshipPaymaster.getDeposit();
        uint256 initialSponsorAccountPaymasterBalance = sponsorshipPaymaster.getBalance(SPONSOR_ACCOUNT.addr);
        uint256 initialFeeCollectorBalance = sponsorshipPaymaster.getBalance(PAYMASTER_FEE_COLLECTOR.addr);

        // submit userops
        vm.expectEmit(true, false, false, false, address(sponsorshipPaymaster));
        emit ISponsorshipPaymasterEventsAndErrors.GasBalanceDeducted(
            SPONSOR_ACCOUNT.addr, 0, 0, IPaymaster.PostOpMode.opSucceeded
        );
        startPrank(BUNDLER.addr);
        ENTRYPOINT.handleOps(ops, payable(BUNDLER.addr));
        stopPrank();

        // calculateAndAssertAdjustments(...
        uint256 totalGasFeePaid = BUNDLER.addr.balance - initialBundlerBalance;
        uint256 gasPaidBySponsor =
            initialSponsorAccountPaymasterBalance - sponsorshipPaymaster.getBalance(SPONSOR_ACCOUNT.addr);
        uint256 premiumEarnedByFeeCollector =
            sponsorshipPaymaster.getBalance(PAYMASTER_FEE_COLLECTOR.addr) - initialFeeCollectorBalance; // actualMarkup
        // must be some premium earned
        assertGt(premiumEarnedByFeeCollector, 0);
        uint256 expectedPremium = gasPaidBySponsor * feeMarkup / 1e6;

        // Review
        // assertEq(expectedPremium, premiumEarnedByFeeCollector);

        // Assert that what paymaster paid is the same as what the bundler received
        assertEq(totalGasFeePaid, initialPaymasterEpBalance - sponsorshipPaymaster.getDeposit());
        assertGt(gasPaidBySponsor, totalGasFeePaid);
    }
}
