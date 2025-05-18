// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

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

contract TestTokenPaymasterSoneium is TestBase {
    uint256 public constant WITHDRAWAL_DELAY = 3600;
    uint256 public constant MIN_DEPOSIT = 1e15;
    uint256 public constant UNACCOUNTED_GAS = 50e3;
    uint48 public constant MAX_ORACLE_ROUND_AGE = 4 hours;

    StartaleTokenPaymaster public tokenPaymaster;
    // MockOracle public nativeAssetToUsdOracle;
    // MockOracle public tokenToUsdOracle;

    IOracle public nativeOracle = IOracle(0x291cF980BA12505D65ee01BDe0882F1d5e533525); // soneium ETH/USD chainlink feed
    IOracle public sequencerUptimeOracle = IOracle(0xaDE1b9AbB98c6A542E4B49db2588a3Ec4bF7Cdf0); // soneium L2 Sequencer Uptime Status Feed
    IOracle public tokenOracle = IOracle(0xBa5C28f78eFdC03C37e2C46880314386aFf43228); // soneium ASTR/USD chainlink feed
    IERC20 public astr = IERC20(0x2CAE934a1e84F693fbb78CA5ED3B0A6893259441); // soneium ASTR
    TestCounter public testCounter;

    // MockToken public testToken;

    function setUp() public {
        uint256 forkId = vm.createFork("https://rpc.soneium.org");
        vm.selectFork(forkId);

        console2.log(block.timestamp);

        setupPaymasterTestEnvironment();
        // Deploy Sponsorship Paymaster
        address[] memory signers = new address[](2);
        signers[0] = PAYMASTER_SIGNER_A.addr;
        signers[1] = PAYMASTER_SIGNER_B.addr;

        tokenPaymaster = new StartaleTokenPaymaster({
            _owner: PAYMASTER_OWNER.addr,
            _entryPoint: address(ENTRYPOINT),
            _signers: signers,
            _tokenFeesTreasury: PAYMASTER_FEE_COLLECTOR.addr,
            _unaccountedGas: UNACCOUNTED_GAS,
            _nativeAssetToUsdOracle: address(nativeOracle),
            _sequencerUptimeOracle: address(sequencerUptimeOracle),
            _nativeAssetMaxOracleRoundAge: MAX_ORACLE_ROUND_AGE,
            _nativeAssetDecimals: 18,
            _independentTokens: _toSingletonArray(address(astr)),
            _feeMarkupsForIndependentTokens: _toSingletonArray(1e6),
            _tokenOracleConfigs: _toSingletonArray(
                IOracleHelper.TokenOracleConfig({
                    tokenOracle: IOracle(address(tokenOracle)),
                    maxOracleRoundAge: MAX_ORACLE_ROUND_AGE
                })
            )
        });
    }

    function test_Deploy_STPM_Soneium() external {
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
            address(nativeOracle),
            address(sequencerUptimeOracle),
            MAX_ORACLE_ROUND_AGE,
            18, // native token decimals
            _toSingletonArray(address(astr)),
            _toSingletonArray(1e6),
            _toSingletonArray(
                IOracleHelper.TokenOracleConfig({
                    tokenOracle: IOracle(address(tokenOracle)),
                    maxOracleRoundAge: MAX_ORACLE_ROUND_AGE
                })
            )
        );

        assertEq(testArtifact.owner(), PAYMASTER_OWNER.addr);
        assertEq(address(testArtifact.entryPoint()), ENTRYPOINT_ADDRESS);
        assertEq(testArtifact.isSigner(PAYMASTER_SIGNER_A.addr), true);
        assertEq(testArtifact.isSigner(PAYMASTER_SIGNER_B.addr), true);
        assertEq(address(testArtifact.nativeAssetToUsdOracle()), address(nativeOracle));
        assertEq(testArtifact.unaccountedGas(), UNACCOUNTED_GAS);
    }

    function test_Deposit_Soneium() external prankModifier(PAYMASTER_OWNER.addr) {
        uint256 depositAmount = 10 ether;
        assertEq(tokenPaymaster.getDeposit(), 0);

        tokenPaymaster.deposit{value: depositAmount}();
        assertEq(tokenPaymaster.getDeposit(), depositAmount);
    }

    function test_WithdrawTo_Soneium() external prankModifier(PAYMASTER_OWNER.addr) {
        uint256 depositAmount = 10 ether;
        tokenPaymaster.deposit{value: depositAmount}();
        uint256 initialBalance = BOB_ADDRESS.balance;

        // Withdraw ETH to BOB_ADDRESS and verify the balance changes
        tokenPaymaster.withdrawTo(payable(BOB_ADDRESS), depositAmount);

        assertEq(BOB_ADDRESS.balance, initialBalance + depositAmount);
        assertEq(tokenPaymaster.getDeposit(), 0);
    }

    function test_Success_TokenPaymaster_IndependentMode_WithoutPremium_Soneium() external {
        tokenPaymaster.deposit{value: 10 ether}();
        deal(address(astr), address(ALICE_ACCOUNT), 100000e18);

        vm.startPrank(PAYMASTER_OWNER.addr);
        tokenPaymaster.setUnaccountedGas(70_000);
        vm.stopPrank();

        // Warm up the ERC20 balance slot for tokenFeeTreasury by making some tokens held initially
        deal(address(astr), PAYMASTER_FEE_COLLECTOR.addr, 100000e18);

        uint256 initialBundlerBalance = BUNDLER.addr.balance;
        uint256 initialPaymasterEpBalance = tokenPaymaster.getDeposit();
        uint256 initialUserTokenBalance = astr.balanceOf(address(ALICE_ACCOUNT));
        uint256 initialPaymasterTokenBalance = astr.balanceOf(address(tokenPaymaster));
        uint256 initialTokenFeeTreasuryBalance = astr.balanceOf(PAYMASTER_FEE_COLLECTOR.addr);

        PackedUserOperation[] memory ops = new PackedUserOperation[](1);

        // Good part of not doing pre-charge and only charging in postOp is we can give approval during the execution phase.
        // So we build a userOp with approve calldata.
        bytes memory userOpCalldata = abi.encodeWithSelector(
            SimpleAccount.execute.selector,
            address(astr),
            0,
            abi.encodeWithSelector(astr.approve.selector, address(tokenPaymaster), 1000 * 1e18)
        );

        // Generate and sign the token paymaster data
        (PackedUserOperation memory userOp, bytes32 userOpHash) = createUserOpWithTokenPaymasterAndIndependentMode(
            ALICE, tokenPaymaster, address(astr), 100_000, userOpCalldata
        );

        ops[0] = userOp;

        vm.expectEmit(true, true, false, false, address(tokenPaymaster));
        emit IStartaleTokenPaymasterEventsAndErrors.PaidGasInTokens(address(ALICE_ACCOUNT), address(astr), 0, 1e6, 0);

        // Execute the operation
        startPrank(BUNDLER.addr);
        uint256 gasValue = gasleft();
        ENTRYPOINT.handleOps(ops, payable(BUNDLER.addr));
        gasValue = gasValue - gasleft();
        stopPrank();

        uint256 gasPaidBySAInERC20 = initialUserTokenBalance - astr.balanceOf(address(ALICE_ACCOUNT));

        uint256 gasCollectedInERC20ByFeeCollector =
            astr.balanceOf(PAYMASTER_FEE_COLLECTOR.addr) - initialTokenFeeTreasuryBalance;

        assertEq(gasPaidBySAInERC20, gasCollectedInERC20ByFeeCollector);

        // TODO:
        // calculateAndAssertAdjustmentsForTokenPaymaster...
    }
}
