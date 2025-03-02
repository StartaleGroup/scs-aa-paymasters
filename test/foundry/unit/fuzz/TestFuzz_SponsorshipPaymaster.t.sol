// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.28;

import "../../TestBase.sol";
import {ISponsorshipPaymaster} from "../../../../src/interfaces/ISponsorshipPaymaster.sol";
import {SponsorshipPaymaster} from "../../../../src/sponsorship/SponsorshipPaymaster.sol";
import {ISponsorshipPaymasterEventsAndErrors} from "../../../../src/interfaces/ISponsorshipPaymasterEventsAndErrors.sol";
import "@account-abstraction/contracts/interfaces/IStakeManager.sol";

contract TestFuzz_SponsorshipPaymaster is TestBase {
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

    function testFuzz_DepositFor(uint256 depositAmount) external {
        vm.assume(depositAmount <= 1000 ether && depositAmount > 1e15);
        vm.deal(SPONSOR_ACCOUNT.addr, depositAmount);
        uint256 dappPaymasterBalance = sponsorshipPaymaster.getBalance(SPONSOR_ACCOUNT.addr);
        assertEq(dappPaymasterBalance, 0 ether);
        vm.expectEmit(true, true, false, true, address(sponsorshipPaymaster));
        emit ISponsorshipPaymasterEventsAndErrors.DepositAdded(SPONSOR_ACCOUNT.addr, depositAmount);
        sponsorshipPaymaster.depositFor{value: depositAmount}(SPONSOR_ACCOUNT.addr);
        dappPaymasterBalance = sponsorshipPaymaster.getBalance(SPONSOR_ACCOUNT.addr);
        assertEq(dappPaymasterBalance, depositAmount);
    }
}
