// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.28;

import "../../TestBase.sol";
import {StartaleTokenPaymaster} from "../../../../src/token/startale/StartaleTokenPaymaster.sol";
import {IStartaleTokenPaymaster} from "../../../../src/interfaces/IStartaleTokenPaymaster.sol";
import {IStartaleTokenPaymasterEventsAndErrors} from
    "../../../../src/interfaces/IStartaleTokenPaymasterEventsAndErrors.sol";
import "@account-abstraction/contracts/interfaces/IStakeManager.sol";
import {MultiSigners} from "../../../../src/lib/MultiSigners.sol";
import {TestCounter} from "../../TestCounter.sol";
import {MockToken} from "../../mock/MockToken.sol";
import {MockOracle} from "../../mock/MockOracle.sol";
import {IOracle} from "../../../../src/interfaces/IOracle.sol";

contract TestTokenPaymaster is TestBase {
    uint256 public constant WITHDRAWAL_DELAY = 3600;
    uint256 public constant MIN_DEPOSIT = 1e15;
    uint256 public constant UNACCOUNTED_GAS = 50e3;
    uint48 public constant MAX_ORACLE_ROUND_AGE = 1000;

    StartaleTokenPaymaster public tokenPaymaster;
    MockOracle public nativeAssetToUsdOracle;
    MockOracle public tokenToUsdOracle;
    TestCounter public testCounter;
    MockToken public testToken;

    function setUp() public {
        setupPaymasterTestEnvironment();
        // Deploy Sponsorship Paymaster
        address[] memory signers = new address[](2);
        signers[0] = PAYMASTER_SIGNER_A.addr;
        signers[1] = PAYMASTER_SIGNER_B.addr;

        nativeAssetToUsdOracle = new MockOracle(100_000_000, 8); // Oracle with 8 decimals for ETH // ETH/USD
        nativeAssetToUsdOracle.setUpdatedAtDelay(500);
        // let's say this is WETH
        tokenToUsdOracle = new MockOracle(100_000_000, 8); // Oracle with 8 decimals for ERC20 token // TKN/USD
        tokenToUsdOracle.setUpdatedAtDelay(500);
        testToken = new MockToken("Test Token", "TKN");

        tokenPaymaster = new StartaleTokenPaymaster({
            _owner: PAYMASTER_OWNER.addr,
            _entryPoint: address(ENTRYPOINT),
            _signers: signers,
            _tokenFeesTreasury: PAYMASTER_FEE_COLLECTOR.addr,
            _unaccountedGas: UNACCOUNTED_GAS,
            _nativeAssetToUsdOracle: address(nativeAssetToUsdOracle),
            _nativeAssetMaxOracleRoundAge: MAX_ORACLE_ROUND_AGE,
            _nativeAssetDecimals: 18,
            _independentTokens: _toSingletonArray(address(testToken)),
            _feeMarkupsForIndependentTokens: _toSingletonArray(1e6),
            _tokenOracleConfigs: _toSingletonArray(
                IOracleHelper.TokenOracleConfig({tokenOracle: IOracle(address(tokenToUsdOracle)), maxOracleRoundAge: 1000})
            )
        });
    }

    function test_Deploy_STPM() external {
        address[] memory signers = new address[](2);
        signers[0] = PAYMASTER_SIGNER_A.addr;
        signers[1] = PAYMASTER_SIGNER_B.addr;
        // Deploy the token paymaster
        StartaleTokenPaymaster testArtifact = new StartaleTokenPaymaster(
            PAYMASTER_OWNER.addr,
            ENTRYPOINT_ADDRESS,
            signers,
            PAYMASTER_FEE_COLLECTOR.addr,
            UNACCOUNTED_GAS, // unaccounted gas
            address(nativeAssetToUsdOracle),
            MAX_ORACLE_ROUND_AGE,
            18, // native token decimals
            _toSingletonArray(address(testToken)),
            _toSingletonArray(1e6),
            _toSingletonArray(
                IOracleHelper.TokenOracleConfig({
                    tokenOracle: IOracle(address(tokenToUsdOracle)),
                    maxOracleRoundAge: MAX_ORACLE_ROUND_AGE
                })
            )
        );

        assertEq(testArtifact.owner(), PAYMASTER_OWNER.addr);
        assertEq(address(testArtifact.entryPoint()), ENTRYPOINT_ADDRESS);
        assertEq(testArtifact.isSigner(PAYMASTER_SIGNER_A.addr), true);
        assertEq(testArtifact.isSigner(PAYMASTER_SIGNER_B.addr), true);
        assertEq(address(testArtifact.nativeAssetToUsdOracle()), address(nativeAssetToUsdOracle));
        assertEq(testArtifact.unaccountedGas(), UNACCOUNTED_GAS);
    }

    function test_Deposit() external prankModifier(PAYMASTER_OWNER.addr) {
        uint256 depositAmount = 10 ether;
        assertEq(tokenPaymaster.getDeposit(), 0);

        tokenPaymaster.deposit{value: depositAmount}();
        assertEq(tokenPaymaster.getDeposit(), depositAmount);
    }

    function test_WithdrawTo() external prankModifier(PAYMASTER_OWNER.addr) {
        uint256 depositAmount = 10 ether;
        tokenPaymaster.deposit{value: depositAmount}();
        uint256 initialBalance = BOB_ADDRESS.balance;

        // Withdraw ETH to BOB_ADDRESS and verify the balance changes
        tokenPaymaster.withdrawTo(payable(BOB_ADDRESS), depositAmount);

        assertEq(BOB_ADDRESS.balance, initialBalance + depositAmount);
        assertEq(tokenPaymaster.getDeposit(), 0);
    }

    function test_WithdrawERC20() external prankModifier(PAYMASTER_OWNER.addr) {
        uint256 mintAmount = 10 * (10 ** testToken.decimals());
        testToken.mint(address(tokenPaymaster), mintAmount);

        // Ensure that the paymaster has the tokens
        assertEq(testToken.balanceOf(address(tokenPaymaster)), mintAmount);
        assertEq(testToken.balanceOf(ALICE_ADDRESS), 0);

        // Expect the `TokensWithdrawn` event to be emitted with the correct values
        vm.expectEmit(true, true, true, true, address(tokenPaymaster));
        emit IStartaleTokenPaymasterEventsAndErrors.TokensWithdrawn(
            address(testToken), ALICE_ADDRESS, PAYMASTER_OWNER.addr, mintAmount
        );

        // Withdraw tokens and validate balances
        tokenPaymaster.withdrawERC20(testToken, ALICE_ADDRESS, mintAmount);

        assertEq(testToken.balanceOf(address(tokenPaymaster)), 0);
        assertEq(testToken.balanceOf(ALICE_ADDRESS), mintAmount);
    }

    function test_Success_TokenPaymaster_ExternalMode_WithoutPremium() external {
        tokenPaymaster.deposit{value: 10 ether}();
        testToken.mint(address(ALICE_ACCOUNT), 100_000 * (10 ** testToken.decimals()));

        vm.startPrank(PAYMASTER_OWNER.addr);
        tokenPaymaster.setUnaccountedGas(70_000);
        vm.stopPrank();

        // Warm up the ERC20 balance slot for tokenFeeTreasury by making some tokens held initially
        testToken.mint(PAYMASTER_FEE_COLLECTOR.addr, 100_000 * (10 ** testToken.decimals()));

        uint256 initialBundlerBalance = BUNDLER.addr.balance;
        uint256 initialPaymasterEpBalance = tokenPaymaster.getDeposit();
        uint256 initialUserTokenBalance = testToken.balanceOf(address(ALICE_ACCOUNT));
        uint256 initialPaymasterTokenBalance = testToken.balanceOf(address(tokenPaymaster));
        uint256 initialTokenFeeTreasuryBalance = testToken.balanceOf(PAYMASTER_FEE_COLLECTOR.addr);

        PackedUserOperation[] memory ops = new PackedUserOperation[](1);

        uint48 validUntil = uint48(block.timestamp + 1 days);
        uint48 validAfter = uint48(block.timestamp);
        uint256 tokenPrice = 1e18; // Assume 1 token = 1 native token = 1 USD ?
        uint32 externalFeeMarkup = 1e6; // no premium

        // Good part of not doing pre-charge and only charging in postOp is we can give approval during the execution phase.
        // So we build a userOp with approve calldata.
        bytes memory userOpCalldata = abi.encodeWithSelector(
            SimpleAccount.execute.selector,
            address(testToken),
            0,
            abi.encodeWithSelector(testToken.approve.selector, address(tokenPaymaster), 1000 * 1e18)
        );

        // Generate and sign the token paymaster data
        (PackedUserOperation memory userOp, bytes32 userOpHash) = createUserOpWithTokenPaymasterAndExternalMode(
            ALICE, tokenPaymaster, address(testToken), 1e18, externalFeeMarkup, 100_000, userOpCalldata
        );

        ops[0] = userOp;

        vm.expectEmit(true, true, false, false, address(tokenPaymaster));
        emit IStartaleTokenPaymasterEventsAndErrors.PaidGasInTokens(
            address(ALICE_ACCOUNT), address(testToken), 0, 1e6, 0
        );

        // Execute the operation
        startPrank(BUNDLER.addr);
        uint256 gasValue = gasleft();
        ENTRYPOINT.handleOps(ops, payable(BUNDLER.addr));
        gasValue = gasValue - gasleft();
        stopPrank();

        uint256 gasPaidBySAInERC20 = initialUserTokenBalance - testToken.balanceOf(address(ALICE_ACCOUNT));

        uint256 gasCollectedInERC20ByFeeCollector =
            testToken.balanceOf(PAYMASTER_FEE_COLLECTOR.addr) - initialTokenFeeTreasuryBalance;

        assertEq(gasPaidBySAInERC20, gasCollectedInERC20ByFeeCollector);

        // TODO:
        // calculateAndAssertAdjustmentsForTokenPaymaster...
    }

    function test_Success_TokenPaymaster_IndependentMode_WithoutPremium() external {
        vm.warp(1742296776);
        tokenPaymaster.deposit{value: 10 ether}();
        testToken.mint(address(ALICE_ACCOUNT), 100_000 * (10 ** testToken.decimals()));

        vm.startPrank(PAYMASTER_OWNER.addr);
        tokenPaymaster.setUnaccountedGas(70_000);
        vm.stopPrank();

        // Warm up the ERC20 balance slot for tokenFeeTreasury by making some tokens held initially
        testToken.mint(PAYMASTER_FEE_COLLECTOR.addr, 100_000 * (10 ** testToken.decimals()));

        uint256 initialBundlerBalance = BUNDLER.addr.balance;
        uint256 initialPaymasterEpBalance = tokenPaymaster.getDeposit();
        uint256 initialUserTokenBalance = testToken.balanceOf(address(ALICE_ACCOUNT));
        uint256 initialPaymasterTokenBalance = testToken.balanceOf(address(tokenPaymaster));
        uint256 initialTokenFeeTreasuryBalance = testToken.balanceOf(PAYMASTER_FEE_COLLECTOR.addr);

        PackedUserOperation[] memory ops = new PackedUserOperation[](1);

        // Good part of not doing pre-charge and only charging in postOp is we can give approval during the execution phase.
        // So we build a userOp with approve calldata.
        bytes memory userOpCalldata = abi.encodeWithSelector(
            SimpleAccount.execute.selector,
            address(testToken),
            0,
            abi.encodeWithSelector(testToken.approve.selector, address(tokenPaymaster), 1000 * 1e18)
        );

        // Generate and sign the token paymaster data
        (PackedUserOperation memory userOp, bytes32 userOpHash) = createUserOpWithTokenPaymasterAndIndependentMode(
            ALICE, tokenPaymaster, address(testToken), 100_000, userOpCalldata
        );

        ops[0] = userOp;

        vm.expectEmit(true, true, false, false, address(tokenPaymaster));
        emit IStartaleTokenPaymasterEventsAndErrors.PaidGasInTokens(
            address(ALICE_ACCOUNT), address(testToken), 0, 1e6, 0
        );

        // Execute the operation
        startPrank(BUNDLER.addr);
        uint256 gasValue = gasleft();
        ENTRYPOINT.handleOps(ops, payable(BUNDLER.addr));
        gasValue = gasValue - gasleft();
        stopPrank();

        uint256 gasPaidBySAInERC20 = initialUserTokenBalance - testToken.balanceOf(address(ALICE_ACCOUNT));

        uint256 gasCollectedInERC20ByFeeCollector =
            testToken.balanceOf(PAYMASTER_FEE_COLLECTOR.addr) - initialTokenFeeTreasuryBalance;

        assertEq(gasPaidBySAInERC20, gasCollectedInERC20ByFeeCollector);

        // TODO:
        // calculateAndAssertAdjustmentsForTokenPaymaster...
    }

    //TODO:
    // test_RevertIf_InvalidTokenAddress
    // test_RevertIf_InvalidTokenOracle
    // test_RevertIf_InvalidNativeOracle
    // test_RevertIf_InvalidOracleConfig
    // test_RevertIf_DeployWithSignerSetToZero
    // test_RevertIf_DeployWithSignerAsContract
    // test_RevertIf_UnaccountedGasTooHigh
    // test_RevertIf_SetVerifyingSignerToZero
    // test_RevertIf_InvalidNativeOracleDecimals
    // test_RevertIf_InvalidTokenOracleDecimals
    // test_SetNativeAssetToUsdOracle
    // test_RevertIf_PriceExpired
    // test_RevertIf_InvalidSignature_ExternalMode

    function test_SetPriceMarkupTooHigh() external prankModifier(PAYMASTER_OWNER.addr) {
        vm.expectRevert(IStartaleTokenPaymasterEventsAndErrors.FeeMarkupTooHigh.selector);
        tokenPaymaster.addSupportedToken(
            address(testToken),
            2e6 + 1,
            IOracleHelper.TokenOracleConfig({tokenOracle: IOracle(address(tokenToUsdOracle)), maxOracleRoundAge: 1000})
        );
    }

    function test_AddVerifyingSigner() external prankModifier(PAYMASTER_OWNER.addr) {
        assertEq(tokenPaymaster.isSigner(PAYMASTER_SIGNER_A.addr), true);
        assertEq(tokenPaymaster.isSigner(PAYMASTER_SIGNER_B.addr), true);
        address newSigner = address(0x123);
        assertEq(tokenPaymaster.isSigner(newSigner), false);
        vm.expectEmit(true, true, false, true, address(tokenPaymaster));
        emit MultiSigners.SignerAdded(newSigner);
        tokenPaymaster.addSigner(newSigner);
        assertEq(tokenPaymaster.isSigner(newSigner), true);
    }

    function test_RemoveVerifyingSigner() external prankModifier(PAYMASTER_OWNER.addr) {
        assertEq(tokenPaymaster.isSigner(PAYMASTER_SIGNER_A.addr), true);
        assertEq(tokenPaymaster.isSigner(PAYMASTER_SIGNER_B.addr), true);
        vm.expectEmit(true, true, false, true, address(tokenPaymaster));
        emit MultiSigners.SignerRemoved(PAYMASTER_SIGNER_B.addr);
        tokenPaymaster.removeSigner(PAYMASTER_SIGNER_B.addr);
        assertEq(tokenPaymaster.isSigner(PAYMASTER_SIGNER_B.addr), false);
    }
}
