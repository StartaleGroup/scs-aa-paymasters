// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.28;

import "../../TestBase.sol";
import { ISponsorshipPaymaster } from "../../../../src/interfaces/ISponsorshipPaymaster.sol";
import { SponsorshipPaymaster } from "../../../../src/sponsorship/SponsorshipPaymaster.sol";
import { ISponsorshipPaymasterEventsAndErrors } from "../../../../src/interfaces/ISponsorshipPaymasterEventsAndErrors.sol";
import "@account-abstraction/contracts/interfaces/IStakeManager.sol";

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

    // TODO
    // test_RevertIf_DeployWithSignerSetToZero
    // test_RevertIf_DeployWithSignerAsContract
    // test_RevertIf_DeployWithFeeCollectorSetToZero
    // test_RevertIf_DeployWithFeeCollectorAsContract
    // test_RevertIf_DeployWithUnaccountedGasCostTooHigh
    // test_CheckInitialPaymasterState
    // test_OwnershipTransfer
    // test_RevertIf_OwnershipTransferToZeroAddress
    // test_RevertIf_OwnershipTransferTwoStep
    // test_RevertIf_UnauthorizedOwnershipTransfer
    // test_AddVerifyingSigner
    // test_RemoveVerifyingSigner
    // test_RevertIf_AddVerifyingSignerToZeroAddress
    // test_SetFeeCollector
    // test_RevertIf_SetFeeCollectorToZeroAddress
    // test_RevertIf_UnauthorizedSetFeeCollector
    // test_RevertIf_SetUnaccountedGasToHigh
    // test_RevertIf_DepositForZeroAddress
    // test_RevertIf_DepositForZeroValue
    // test_RevertIf_DepositCalled
    // test_RevertIf_TriesWithdrawToWithoutRequest
    // test_submitWithdrawalRequest_Fails_with_ZeroAmount
    // test_submitWithdrawalRequest_Fails_with_ZeroAddress
    // test_submitWithdrawalRequest_Fails_If_not_enough_balance
    // test_executeWithdrawalRequest_Fails_with_NoRequestSubmitted
    // test_cancelWithdrawalRequest_Success
    // test_submitWithdrawalRequest_Happy_Scenario
    // test_executeWithdrawalRequest_Withdraws_WhateverIsLeft 
    // test_depositFor_RevertsIf_DepositIsLessThanMinDeposit

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
        sponsorshipPaymaster.depositFor{ value: depositAmount }(SPONSOR_ACCOUNT.addr);
        sponsorAccountBalance = sponsorshipPaymaster.getBalance(SPONSOR_ACCOUNT.addr);
        assertEq(sponsorAccountBalance, depositAmount);
    }

    function getGasLimit(PackedUserOperation calldata userOp) public pure returns (uint256) {
        uint256 PAYMASTER_POSTOP_GAS_OFFSET = 36;
        uint256 PAYMASTER_DATA_OFFSET = 52;
        return uint128(uint256(userOp.accountGasLimits)) +
            uint128(bytes16(userOp.paymasterAndData[PAYMASTER_POSTOP_GAS_OFFSET : PAYMASTER_DATA_OFFSET]));
   }

   function test_ValidatePaymasterAndPostOpWithoutPriceMarkup() external {
        sponsorshipPaymaster.depositFor{ value: 10 ether }(SPONSOR_ACCOUNT.addr);

        startPrank(PAYMASTER_OWNER.addr);
        sponsorshipPaymaster.setUnaccountedGas(50_000);
        stopPrank();

        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        // fee markup of 1e6
        (PackedUserOperation memory userOp, bytes32 userOpHash) = createUserOpWithSponsorshipPaymaster(ALICE, sponsorshipPaymaster, 1e6, 55_000);
        ops[0] = userOp;

        uint256 initialBundlerBalance = BUNDLER.addr.balance;
        uint256 initialPaymasterEpBalance = sponsorshipPaymaster.getDeposit();
        uint256 initialDappPaymasterBalance = sponsorshipPaymaster.getBalance(SPONSOR_ACCOUNT.addr);
        uint256 initialFeeCollectorBalance = sponsorshipPaymaster.getBalance(PAYMASTER_FEE_COLLECTOR.addr);

        // submit userops
        vm.expectEmit(true, false, false, false, address(sponsorshipPaymaster));
        emit ISponsorshipPaymasterEventsAndErrors.GasBalanceDeducted(SPONSOR_ACCOUNT.addr, 0, 0, IPaymaster.PostOpMode.opSucceeded);
        startPrank(BUNDLER.addr);
        ENTRYPOINT.handleOps(ops, payable(BUNDLER.addr));
        stopPrank();

        // Calculate and assert price markups and gas payments
        // calculateAndAssertAdjustments(...
    }

    // Todo: 
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
}

