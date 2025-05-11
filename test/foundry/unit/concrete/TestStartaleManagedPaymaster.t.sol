// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.28;

import "../../TestBase.sol";
import {IStartaleManagedPaymaster} from "../../../../src/interfaces/IStartaleManagedPaymaster.sol";
import {StartaleManagedPaymaster} from "../../../../src/sponsorship/StartaleManagedPaymaster.sol";
import {IStartaleManagedPaymasterEventsAndErrors} from
    "../../../../src/interfaces/IStartaleManagedPaymasterEventsAndErrors.sol";
import "@account-abstraction/contracts/interfaces/IStakeManager.sol";
import {MultiSigners} from "../../../../src/lib/MultiSigners.sol";
import {TestCounter} from "../../TestCounter.sol";
import {MockToken} from "../../mock/MockToken.sol";
import {BasePaymaster} from "../../../../src/base/BasePaymaster.sol";

contract TestStartaleManagedPaymaster is TestBase {
    StartaleManagedPaymaster public startaleManagedPaymaster;

    function setUp() public {
        setupPaymasterTestEnvironment();
        // Deploy Sponsorship Paymaster
        address[] memory signers = new address[](2);
        signers[0] = PAYMASTER_SIGNER_A.addr;
        signers[1] = PAYMASTER_SIGNER_B.addr;
        startaleManagedPaymaster = new StartaleManagedPaymaster({
            _owner: PAYMASTER_OWNER.addr,
            _entryPoint: address(ENTRYPOINT),
            _signers: signers
        });
    }

    function test_Deploy() external {
        address[] memory signers = new address[](2);
        signers[0] = PAYMASTER_SIGNER_A.addr;
        signers[1] = PAYMASTER_SIGNER_B.addr;
        StartaleManagedPaymaster testArtifact =
            new StartaleManagedPaymaster(PAYMASTER_OWNER.addr, address(ENTRYPOINT), signers);
        assertEq(testArtifact.owner(), PAYMASTER_OWNER.addr);
        assertEq(address(testArtifact.entryPoint()), ENTRYPOINT_ADDRESS);
    }

    function test_RevertIf_DeployWithSignerSetToZero() external {
        address[] memory signers = new address[](2);
        signers[0] = PAYMASTER_SIGNER_A.addr;
        signers[1] = address(0);
        vm.expectRevert(abi.encodeWithSelector(MultiSigners.SignerAddressCannotBeZero.selector));
        new StartaleManagedPaymaster(PAYMASTER_OWNER.addr, address(ENTRYPOINT), signers);
    }

    function test_RevertIf_DeployWithSignerAsContract() external {
        address[] memory signers = new address[](2);
        signers[0] = PAYMASTER_SIGNER_A.addr;
        signers[1] = address(new TestCounter());
        vm.expectRevert(abi.encodeWithSelector(MultiSigners.SignerAddressCannotBeContract.selector));
        new StartaleManagedPaymaster(PAYMASTER_OWNER.addr, address(ENTRYPOINT), signers);
    }

    function test_CheckInitialPaymasterState() external view {
        assertEq(startaleManagedPaymaster.owner(), PAYMASTER_OWNER.addr);
        assertEq(address(startaleManagedPaymaster.entryPoint()), address(ENTRYPOINT));
        assertEq(startaleManagedPaymaster.isSigner(PAYMASTER_SIGNER_A.addr), true);
        assertEq(startaleManagedPaymaster.isSigner(PAYMASTER_SIGNER_B.addr), true);
    }

    function test_Revert_DirectOwnershipTransfer() external prankModifier(PAYMASTER_OWNER.addr) {
        vm.expectRevert(abi.encodeWithSelector(BasePaymaster.OneStepOwnershipTransferNotAllowed.selector));
        startaleManagedPaymaster.transferOwnership(BOB_ADDRESS);
    }

    function test_Success_TwoStepOwnershipTransfer() external {
        assertEq(startaleManagedPaymaster.owner(), PAYMASTER_OWNER.addr);
        // BOB will request ownership transfer
        vm.startPrank(BOB_ADDRESS);
        vm.expectEmit(true, true, false, true, address(startaleManagedPaymaster));
        emit OwnershipHandoverRequested(BOB_ADDRESS);
        startaleManagedPaymaster.requestOwnershipHandover();
        vm.stopPrank();

        // Paymaster owner will accept the ownership transfer
        vm.startPrank(PAYMASTER_OWNER.addr);
        // Owner can also cancel it. but if passed with pendingOwner address within 48 hours it will be performed.
        vm.expectEmit(true, true, false, true, address(startaleManagedPaymaster));
        emit OwnershipTransferred(PAYMASTER_OWNER.addr, BOB_ADDRESS);
        startaleManagedPaymaster.completeOwnershipHandover(BOB_ADDRESS);
        vm.stopPrank();

        assertEq(startaleManagedPaymaster.owner(), BOB_ADDRESS);
    }

    function test_Failure_TwoStepOwnershipTransferWithdrawn() external {
        assertEq(startaleManagedPaymaster.owner(), PAYMASTER_OWNER.addr);
        // BOB will request ownership transfer
        vm.startPrank(BOB_ADDRESS);
        vm.expectEmit(true, true, false, true, address(startaleManagedPaymaster));
        emit OwnershipHandoverRequested(BOB_ADDRESS);
        startaleManagedPaymaster.requestOwnershipHandover();

        // BOB decides to cancel the ownership transfer
        startaleManagedPaymaster.cancelOwnershipHandover();
        vm.stopPrank();

        // Now if owner tries to complete it doesn't work
        vm.startPrank(PAYMASTER_OWNER.addr);
        vm.expectRevert(abi.encodeWithSelector(NoHandoverRequest.selector));
        startaleManagedPaymaster.completeOwnershipHandover(BOB_ADDRESS);
        vm.stopPrank();

        assertEq(startaleManagedPaymaster.owner(), PAYMASTER_OWNER.addr);
    }

    function test_Failure_TwoStepOwnershipTransferExpired() external {
        assertEq(startaleManagedPaymaster.owner(), PAYMASTER_OWNER.addr);
        // BOB will request ownership transfer
        vm.startPrank(BOB_ADDRESS);
        vm.expectEmit(true, true, false, true, address(startaleManagedPaymaster));
        emit OwnershipHandoverRequested(BOB_ADDRESS);
        startaleManagedPaymaster.requestOwnershipHandover();
        vm.stopPrank();

        // More than 48 hours passed
        vm.warp(block.timestamp + 49 hours);

        // Now if owner tries to complete it doesn't work
        vm.startPrank(PAYMASTER_OWNER.addr);
        // Reverts now
        vm.expectRevert(abi.encodeWithSelector(NoHandoverRequest.selector));
        startaleManagedPaymaster.completeOwnershipHandover(BOB_ADDRESS);
        vm.stopPrank();

        // Stil owner is the same
        assertEq(startaleManagedPaymaster.owner(), PAYMASTER_OWNER.addr);
    }

    function test_RevertIf_UnauthorizedOwnershipTransfer() external {
        vm.expectRevert(abi.encodeWithSelector(Unauthorized.selector));
        startaleManagedPaymaster.transferOwnership(BOB_ADDRESS);
    }

    function test_AddVerifyingSigner() external prankModifier(PAYMASTER_OWNER.addr) {
        assertEq(startaleManagedPaymaster.isSigner(PAYMASTER_SIGNER_A.addr), true);
        assertEq(startaleManagedPaymaster.isSigner(PAYMASTER_SIGNER_B.addr), true);
        address newSigner = address(0x123);
        assertEq(startaleManagedPaymaster.isSigner(newSigner), false);
        vm.expectEmit(true, true, false, true, address(startaleManagedPaymaster));
        emit MultiSigners.SignerAdded(newSigner);
        startaleManagedPaymaster.addSigner(newSigner);
        assertEq(startaleManagedPaymaster.isSigner(newSigner), true);
    }

    function test_RemoveVerifyingSigner() external prankModifier(PAYMASTER_OWNER.addr) {
        assertEq(startaleManagedPaymaster.isSigner(PAYMASTER_SIGNER_A.addr), true);
        assertEq(startaleManagedPaymaster.isSigner(PAYMASTER_SIGNER_B.addr), true);
        vm.expectEmit(true, true, false, true, address(startaleManagedPaymaster));
        emit MultiSigners.SignerRemoved(PAYMASTER_SIGNER_B.addr);
        startaleManagedPaymaster.removeSigner(PAYMASTER_SIGNER_B.addr);
        assertEq(startaleManagedPaymaster.isSigner(PAYMASTER_SIGNER_B.addr), false);
    }

    function test_RevertIf_AddVerifyingSignerToZeroAddress() external prankModifier(PAYMASTER_OWNER.addr) {
        assertEq(startaleManagedPaymaster.isSigner(PAYMASTER_SIGNER_A.addr), true);
        assertEq(startaleManagedPaymaster.isSigner(PAYMASTER_SIGNER_B.addr), true);
        vm.expectRevert(abi.encodeWithSelector(MultiSigners.SignerAddressCannotBeZero.selector));
        startaleManagedPaymaster.addSigner(address(0));
    }

    // Todo
    // Should be able to deposit and withdraw (onlyOwner)

    function test_RevertIf_ValidatePaymasterUserOpWithIncorrectSignatureLength() external {
        startaleManagedPaymaster.deposit{value: 10 ether}();
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        PackedUserOperation memory userOp = buildUserOpWithCalldata(ALICE, "", 0, 0);

        StartaleManagedPaymasterData memory pmData = StartaleManagedPaymasterData({
            validationGasLimit: 100_000,
            postOpGasLimit: uint128(55_000),
            validUntil: uint48(block.timestamp + 1 days),
            validAfter: uint48(block.timestamp)
        });

        (userOp.paymasterAndData,) =
            generateAndSignStartaleManagedPaymasterData(userOp, PAYMASTER_SIGNER_A, startaleManagedPaymaster, pmData);
        userOp.signature = signUserOp(ALICE, userOp);

        userOp.paymasterAndData = excludeLastNBytes(userOp.paymasterAndData, 2);
        ops[0] = userOp;
        vm.expectRevert();
        // cast sig PaymasterSignatureLengthInvalid()
        // FailedOpWithRevert(0, "AA33 reverted", 0x90bc2302)
        ENTRYPOINT.handleOps(ops, payable(BUNDLER.addr));
    }

    function test_RevertIf_ValidatePaymasterUserOpWithInsufficientDeposit() external {
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        PackedUserOperation memory userOp = buildUserOpWithCalldata(ALICE, "", 0, 0);
        StartaleManagedPaymasterData memory pmData = StartaleManagedPaymasterData({
            validationGasLimit: 100_000,
            postOpGasLimit: uint128(55_000),
            validUntil: uint48(block.timestamp + 1 days),
            validAfter: uint48(block.timestamp)
        });
        (userOp.paymasterAndData,) =
            generateAndSignStartaleManagedPaymasterData(userOp, PAYMASTER_SIGNER_A, startaleManagedPaymaster, pmData);
        userOp.signature = signUserOp(ALICE, userOp);
        ops[0] = userOp;
        vm.expectRevert();
        // FailedOp(0, "AA31 paymaster deposit too low")
        ENTRYPOINT.handleOps(ops, payable(BUNDLER.addr));
    }

    function test_Receive() external prankModifier(ALICE_ADDRESS) {
        uint256 initialPaymasterBalance = address(startaleManagedPaymaster).balance;
        uint256 sendAmount = 10 ether;

        (bool success,) = address(startaleManagedPaymaster).call{value: sendAmount}("");

        assert(success);
        uint256 resultingPaymasterBalance = address(startaleManagedPaymaster).balance;
        assertEq(resultingPaymasterBalance, initialPaymasterBalance + sendAmount);
    }

    function test_WithdrawEth() external prankModifier(PAYMASTER_OWNER.addr) {
        uint256 initialAliceBalance = ALICE_ADDRESS.balance;
        uint256 ethAmount = 10 ether;
        vm.deal(address(startaleManagedPaymaster), ethAmount);

        startaleManagedPaymaster.withdrawEth(payable(ALICE_ADDRESS), ethAmount);
        vm.stopPrank();

        assertEq(ALICE_ADDRESS.balance, initialAliceBalance + ethAmount);
        assertEq(address(startaleManagedPaymaster).balance, 0 ether);
    }

    function test_RevertIf_WithdrawEthExceedsBalance() external prankModifier(PAYMASTER_OWNER.addr) {
        uint256 ethAmount = 10 ether;
        vm.expectRevert(abi.encodeWithSelector(IStartaleManagedPaymasterEventsAndErrors.WithdrawalFailed.selector));
        startaleManagedPaymaster.withdrawEth(payable(ALICE_ADDRESS), ethAmount);
    }

    function test_WithdrawErc20() external prankModifier(PAYMASTER_OWNER.addr) {
        MockToken token = new MockToken("Token", "TKN");
        uint256 mintAmount = 10 * (10 ** token.decimals());
        token.mint(address(startaleManagedPaymaster), mintAmount);

        assertEq(token.balanceOf(address(startaleManagedPaymaster)), mintAmount);
        assertEq(token.balanceOf(ALICE_ADDRESS), 0);

        vm.expectEmit(true, true, true, true, address(startaleManagedPaymaster));
        emit IStartaleManagedPaymasterEventsAndErrors.TokensWithdrawn(
            address(token), ALICE_ADDRESS, PAYMASTER_OWNER.addr, mintAmount
        );
        startaleManagedPaymaster.withdrawERC20(token, ALICE_ADDRESS, mintAmount);

        assertEq(token.balanceOf(address(startaleManagedPaymaster)), 0);
        assertEq(token.balanceOf(ALICE_ADDRESS), mintAmount);
    }

    function test_RevertIf_WithdrawErc20ToZeroAddress() external prankModifier(PAYMASTER_OWNER.addr) {
        MockToken token = new MockToken("Token", "TKN");
        uint256 mintAmount = 10 * (10 ** token.decimals());
        token.mint(address(startaleManagedPaymaster), mintAmount);

        vm.expectRevert(
            abi.encodeWithSelector(IStartaleManagedPaymasterEventsAndErrors.InvalidWithdrawalAddress.selector)
        );
        startaleManagedPaymaster.withdrawERC20(token, address(0), mintAmount);
    }

    function test_ParsePaymasterAndData() external view {
        PackedUserOperation memory userOp = buildUserOpWithCalldata(ALICE, "", 0, 0);

        uint32 priceMarkup = 1e6;

        StartaleManagedPaymasterData memory pmData = StartaleManagedPaymasterData({
            validationGasLimit: 100_000,
            postOpGasLimit: uint128(55_000),
            validUntil: uint48(block.timestamp + 1 days),
            validAfter: uint48(block.timestamp)
        });

        (userOp.paymasterAndData,) =
            generateAndSignStartaleManagedPaymasterData(userOp, PAYMASTER_SIGNER_A, startaleManagedPaymaster, pmData);
        userOp.signature = signUserOp(ALICE, userOp);

        (uint48 parsedValidUntil, uint48 parsedValidAfter, bytes memory parsedSignature) =
            startaleManagedPaymaster.parsePaymasterAndData(userOp.paymasterAndData);

        assertEq(pmData.validUntil, parsedValidUntil);
        assertEq(pmData.validAfter, parsedValidAfter);
        assertEq(parsedSignature.length, userOp.signature.length);
    }

    function getGasLimit(PackedUserOperation calldata userOp) public pure returns (uint256) {
        uint256 PAYMASTER_POSTOP_GAS_OFFSET = 36;
        uint256 PAYMASTER_DATA_OFFSET = 52;
        return uint128(uint256(userOp.accountGasLimits))
            + uint128(bytes16(userOp.paymasterAndData[PAYMASTER_POSTOP_GAS_OFFSET:PAYMASTER_DATA_OFFSET]));
    }

    function test_ValidatePaymasterEntireOp() external {
        startaleManagedPaymaster.deposit{value: 10 ether}();

        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        // fee markup of 1e6
        (PackedUserOperation memory userOp, bytes32 userOpHash) =
            createUserOpWithStartaleManagedPaymaster(ALICE, startaleManagedPaymaster, 20_000);
        ops[0] = userOp;

        uint256 initialBundlerBalance = BUNDLER.addr.balance;
        uint256 initialPaymasterEpBalance = startaleManagedPaymaster.getDeposit();
        // submit userops
        vm.expectEmit(true, false, false, false, address(startaleManagedPaymaster));
        emit StartaleManagedPaymaster.UserOperationSponsored(userOpHash, address(ALICE_ADDRESS));
        startPrank(BUNDLER.addr);
        ENTRYPOINT.handleOps(ops, payable(BUNDLER.addr));
        stopPrank();

        // calculateAndAssertAdjustments(...
        uint256 totalGasFeePaid = BUNDLER.addr.balance - initialBundlerBalance;

        // Assert that what paymaster paid is the same as what the bundler received
        assertEq(totalGasFeePaid, initialPaymasterEpBalance - startaleManagedPaymaster.getDeposit());
    }
}
