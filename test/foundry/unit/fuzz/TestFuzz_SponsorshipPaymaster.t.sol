// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.29;

import "../../TestBase.sol";
import {ISponsorshipPaymaster} from "../../../../src/interfaces/ISponsorshipPaymaster.sol";
import {SponsorshipPaymaster} from "../../../../src/sponsorship/SponsorshipPaymaster.sol";
import {ISponsorshipPaymasterEventsAndErrors} from "../../../../src/interfaces/ISponsorshipPaymasterEventsAndErrors.sol";
import "@account-abstraction/contracts/interfaces/IStakeManager.sol";
import {MockToken} from "../../mock/MockToken.sol";

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

    function testFuzz_Receive(uint256 ethAmount) external prankModifier(ALICE_ADDRESS) {
        vm.assume(ethAmount <= 1000 ether && ethAmount > 0 ether);
        uint256 initialPaymasterBalance = address(sponsorshipPaymaster).balance;
        (bool success,) = address(sponsorshipPaymaster).call{value: ethAmount}("");
        assert(success);
        uint256 resultingPaymasterBalance = address(sponsorshipPaymaster).balance;
        assertEq(resultingPaymasterBalance, initialPaymasterBalance + ethAmount);
    }

    function testFuzz_WithdrawEth(uint256 ethAmount) external prankModifier(PAYMASTER_OWNER.addr) {
        vm.assume(ethAmount <= 1000 ether && ethAmount > 0 ether);
        vm.deal(address(sponsorshipPaymaster), ethAmount);
        uint256 initialAliceBalance = ALICE_ADDRESS.balance;
        sponsorshipPaymaster.withdrawEth(payable(ALICE_ADDRESS), ethAmount);
        assertEq(ALICE_ADDRESS.balance, initialAliceBalance + ethAmount);
        assertEq(address(sponsorshipPaymaster).balance, 0 ether);
    }

    function testFuzz_WithdrawErc20(address target, uint256 amount) external prankModifier(PAYMASTER_OWNER.addr) {
        vm.assume(target != address(0) && amount <= 1_000_000 * (10 ** 18));
        MockToken token = new MockToken("Token", "TKN");
        uint256 mintAmount = amount;
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
}
