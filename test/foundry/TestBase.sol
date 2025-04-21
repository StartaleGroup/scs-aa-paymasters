// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {console2} from "forge-std/console2.sol";
import {CheatCodes} from "./utils/CheatCodes.sol";
import "./utils/TestHelper.sol";

import "solady/utils/ECDSA.sol";

import "account-abstraction/core/UserOperationLib.sol";

import {IAccount} from "account-abstraction/interfaces/IAccount.sol";
import {Exec} from "account-abstraction/utils/Exec.sol";
import {IPaymaster} from "account-abstraction/interfaces/IPaymaster.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {SponsorshipPaymaster} from "../../src/sponsorship/SponsorshipPaymaster.sol";
import {StartaleManagedPaymaster} from "../../src/sponsorship/StartaleManagedPaymaster.sol";
import {BaseEventsAndErrors} from "./BaseEventsAndErrors.sol";
import {IOracleHelper} from "../../src/interfaces/IOracleHelper.sol";
import {StartaleTokenPaymaster} from "../../src/token/startale/StartaleTokenPaymaster.sol";
import {IStartaleTokenPaymaster} from "../../src/interfaces/IStartaleTokenPaymaster.sol";
// Notice: We can add a base contract for required events and errors for the paymasters

abstract contract TestBase is CheatCodes, TestHelper, BaseEventsAndErrors {
    using UserOperationLib for PackedUserOperation;

    address constant ENTRYPOINT_ADDRESS = address(0x0000000071727De22E5E9d8BAf0edAc6f37da032);
    // Note: addresses valid for Base and Soneium, can be different for other chains
    address constant WRAPPED_NATIVE_ADDRESS = address(0x4200000000000000000000000000000000000006);

    // SWAP_ROUTER_ADDRESS

    uint32 internal constant _PRICE_MARKUP_DENOMINATOR = 1e6;

    Vm.Wallet internal PAYMASTER_OWNER;
    Vm.Wallet internal PAYMASTER_SIGNER_A;
    Vm.Wallet internal PAYMASTER_SIGNER_B;
    Vm.Wallet internal PAYMASTER_FEE_COLLECTOR;
    Vm.Wallet internal SPONSOR_ACCOUNT;

    uint256 internal constant _PAYMASTER_POSTOP_GAS_OFFSET = UserOperationLib.PAYMASTER_POSTOP_GAS_OFFSET;
    uint256 internal constant _PAYMASTER_DATA_OFFSET = UserOperationLib.PAYMASTER_DATA_OFFSET;

    struct SponsorshipPaymasterData {
        uint128 validationGasLimit;
        uint128 postOpGasLimit;
        address sponsorAccount;
        uint48 validUntil;
        uint48 validAfter;
        uint32 feeMarkup;
    }

    struct StartaleManagedPaymasterData {
        uint128 validationGasLimit;
        uint128 postOpGasLimit;
        uint48 validUntil;
        uint48 validAfter;
    }

    struct TokenPaymasterDataExternalMode {
        uint128 validationGasLimit;
        uint128 postOpGasLimit;
        IStartaleTokenPaymaster.PaymasterMode mode;
        uint48 validUntil;
        uint48 validAfter;
        address tokenAddress;
        uint256 exchangeRate;
        uint48 appliedFeeMarkup;
    }

    struct StartaleTokenPaymasterData {
        uint128 paymasterValGasLimit;
        uint128 paymasterPostOpGasLimit;
    }
    // ...

    // Used to buffer user op gas limits
    // GAS_LIMIT = (ESTIMATED_GAS * GAS_BUFFER_RATIO) / 100
    uint8 private constant GAS_BUFFER_RATIO = 110;

    // -----------------------------------------
    // Modifiers
    // -----------------------------------------
    modifier prankModifier(address pranker) {
        startPrank(pranker);
        _;
        stopPrank();
    }

    // -----------------------------------------
    // Setup Functions
    // -----------------------------------------
    /// @notice Initializes the testing environment with wallets, contracts, and accounts
    function setupPaymasterTestEnvironment() internal virtual {
        /// Initializes the testing environment
        setupPredefinedWallets();
        setupPaymasterPredefinedWallets();
        deployTestContracts();
        deploySimpleAccountForPredefinedWallets();
    }

    function setupPaymasterPredefinedWallets() internal {
        PAYMASTER_OWNER = createAndFundWallet("PAYMASTER_OWNER", 1000 ether);
        PAYMASTER_SIGNER_A = createAndFundWallet("PAYMASTER_SIGNER_A", 1000 ether);
        PAYMASTER_SIGNER_B = createAndFundWallet("PAYMASTER_SIGNER_B", 1000 ether);
        PAYMASTER_FEE_COLLECTOR = createAndFundWallet("PAYMASTER_FEE_COLLECTOR", 1000 ether);
        SPONSOR_ACCOUNT = createAndFundWallet("SPONSOR_ACCOUNT", 1000 ether);
    }

    function estimateUserOpGasCosts(PackedUserOperation memory userOp)
        internal
        prankModifier(ENTRYPOINT_ADDRESS)
        returns (uint256 verificationGasUsed, uint256 callGasUsed, uint256 verificationGasLimit, uint256 callGasLimit)
    {
        bytes32 userOpHash = ENTRYPOINT.getUserOpHash(userOp);
        verificationGasUsed = gasleft();
        IAccount(userOp.sender).validateUserOp(userOp, userOpHash, 0);
        verificationGasUsed = verificationGasUsed - gasleft(); //+ 21000;

        callGasUsed = gasleft();
        bool success = Exec.call(userOp.sender, 0, userOp.callData, 3e6);
        callGasUsed = callGasUsed - gasleft(); //+ 21000;
        assert(success);

        verificationGasLimit = (verificationGasUsed * GAS_BUFFER_RATIO) / 100;
        callGasLimit = (callGasUsed * GAS_BUFFER_RATIO) / 100;
    }

    function estimatePaymasterGasCosts(
        SponsorshipPaymaster paymaster,
        PackedUserOperation memory userOp,
        uint256 requiredPreFund
    )
        internal
        prankModifier(ENTRYPOINT_ADDRESS)
        returns (uint256 validationGasUsed, uint256 postopGasUsed, uint256 validationGasLimit, uint256 postopGasLimit)
    {
        bytes32 userOpHash = ENTRYPOINT.getUserOpHash(userOp);
        // Warm up accounts to get more accurate gas estimations
        (bytes memory context,) = paymaster.validatePaymasterUserOp(userOp, userOpHash, requiredPreFund);
        paymaster.postOp(IPaymaster.PostOpMode.opSucceeded, context, 1e12, 3e6);

        // Estimate gas used
        validationGasUsed = gasleft();
        (context,) = paymaster.validatePaymasterUserOp(userOp, userOpHash, requiredPreFund);
        validationGasUsed = validationGasUsed - gasleft(); //+ 21000;

        postopGasUsed = gasleft();
        paymaster.postOp(IPaymaster.PostOpMode.opSucceeded, context, 1e12, 3e6);
        postopGasUsed = (postopGasUsed - gasleft()); //+ 21000;

        validationGasLimit = (validationGasUsed * GAS_BUFFER_RATIO) / 100;
        postopGasLimit = (postopGasUsed * GAS_BUFFER_RATIO) / 100;
    }

    // Note: we could use externally provided gas limits to override.
    // Note: we could pass callData and callGasLimit as args to test with more tx types
    // Note: we could pass SimpleAccount instance instead of sender EOA and computing counterfactual within buildUserOpWithCalldata
    function createUserOpWithSponsorshipPaymaster(
        Vm.Wallet memory sender,
        SponsorshipPaymaster paymaster,
        uint32 feeMarkup,
        uint128 postOpGasLimitOverride
    ) internal returns (PackedUserOperation memory userOp, bytes32 userOpHash) {
        // Create userOp with no gas estimates
        userOp = buildUserOpWithCalldata(sender, "", 0, 0);

        SponsorshipPaymasterData memory pmData = SponsorshipPaymasterData({
            validationGasLimit: 100_000,
            postOpGasLimit: uint128(postOpGasLimitOverride),
            sponsorAccount: SPONSOR_ACCOUNT.addr,
            validUntil: uint48(block.timestamp + 1 days),
            validAfter: uint48(block.timestamp),
            feeMarkup: feeMarkup
        });
        (userOp.paymasterAndData,) =
            generateAndSignSponsorshipPaymasterData(userOp, PAYMASTER_SIGNER_A, paymaster, pmData);
        userOp.signature = signUserOp(sender, userOp);

        // Estimate account gas limits
        // (,, uint256 verificationGasLimit, uint256 callGasLimit) = estimateUserOpGasCosts(userOp);
        // // Estimate paymaster gas limits
        // (, uint256 postopGasUsed, uint256 validationGasLimit, uint256 postopGasLimit) =
        //     estimatePaymasterGasCosts(paymaster, userOp, 5e4);

        // vm.startPrank(paymaster.owner());
        // paymaster.setUnaccountedGas(postopGasUsed + 500);
        // vm.stopPrank();

        // Ammend the userop to have updated / overridden gas limits
        userOp.accountGasLimits = bytes32(abi.encodePacked(uint128(100_000), uint128(0)));
        SponsorshipPaymasterData memory pmDataNew = SponsorshipPaymasterData(
            uint128(100_000),
            uint128(postOpGasLimitOverride),
            SPONSOR_ACCOUNT.addr,
            uint48(block.timestamp + 1 days),
            uint48(block.timestamp),
            feeMarkup
        );

        (userOp.paymasterAndData,) =
            generateAndSignSponsorshipPaymasterData(userOp, PAYMASTER_SIGNER_A, paymaster, pmDataNew);
        userOp.signature = signUserOp(sender, userOp);
        userOpHash = ENTRYPOINT.getUserOpHash(userOp);
    }

    function createUserOpWithStartaleManagedPaymaster(
        Vm.Wallet memory sender,
        StartaleManagedPaymaster paymaster,
        uint128 postOpGasLimitOverride
    ) internal view returns (PackedUserOperation memory userOp, bytes32 userOpHash) {
        // Create userOp with no gas estimates
        userOp = buildUserOpWithCalldata(sender, "", 0, 0);

        StartaleManagedPaymasterData memory pmData = StartaleManagedPaymasterData({
            validationGasLimit: 100_000,
            postOpGasLimit: uint128(postOpGasLimitOverride),
            validUntil: uint48(block.timestamp + 1 days),
            validAfter: uint48(block.timestamp)
        });
        (userOp.paymasterAndData,) =
            generateAndSignStartaleManagedPaymasterData(userOp, PAYMASTER_SIGNER_A, paymaster, pmData);
        userOp.signature = signUserOp(sender, userOp);

        // Ammend the userop to have updated / overridden gas limits
        userOp.accountGasLimits = bytes32(abi.encodePacked(uint128(100_000), uint128(0)));
        StartaleManagedPaymasterData memory pmDataNew = StartaleManagedPaymasterData(
            uint128(100_000), uint128(postOpGasLimitOverride), uint48(block.timestamp + 1 days), uint48(block.timestamp)
        );

        (userOp.paymasterAndData,) =
            generateAndSignStartaleManagedPaymasterData(userOp, PAYMASTER_SIGNER_A, paymaster, pmDataNew);
        userOp.signature = signUserOp(sender, userOp);
        userOpHash = ENTRYPOINT.getUserOpHash(userOp);
    }

    function createUserOpWithTokenPaymasterAndExternalMode(
        Vm.Wallet memory sender,
        StartaleTokenPaymaster paymaster,
        address tokenAddress,
        uint256 exchangeRate,
        uint48 appliedFeeMarkup,
        uint128 postOpGasLimitOverride,
        bytes memory userOpCalldata
    ) internal returns (PackedUserOperation memory userOp, bytes32 userOpHash) {
        // Create userOp with no gas estimates
        userOp = buildUserOpWithCalldata(sender, userOpCalldata, 0, 0);

        TokenPaymasterDataExternalMode memory pmData = TokenPaymasterDataExternalMode({
            validationGasLimit: uint128(100_000),
            postOpGasLimit: uint128(postOpGasLimitOverride),
            mode: IStartaleTokenPaymaster.PaymasterMode.EXTERNAL,
            validUntil: uint48(block.timestamp + 1 days),
            validAfter: uint48(block.timestamp),
            tokenAddress: tokenAddress,
            exchangeRate: exchangeRate,
            appliedFeeMarkup: appliedFeeMarkup
        });

        bytes memory pmSignature;

        (userOp.paymasterAndData, pmSignature) =
            generateAndSignTokenPaymasterDataExternalMode(userOp, PAYMASTER_SIGNER_A, paymaster, pmData);
        userOp.signature = signUserOp(sender, userOp);
        userOpHash = ENTRYPOINT.getUserOpHash(userOp);
    }

    function createUserOpWithTokenPaymasterAndIndependentMode(
        Vm.Wallet memory sender,
        StartaleTokenPaymaster paymaster,
        address tokenAddress,
        uint128 postOpGasLimitOverride,
        bytes memory userOpCalldata
    ) internal returns (PackedUserOperation memory userOp, bytes32 userOpHash) {
        // Create userOp with no gas estimates
        userOp = buildUserOpWithCalldata(sender, userOpCalldata, 0, 0);

        bytes memory pmData = abi.encodePacked(
            address(paymaster),
            uint128(100_000),
            uint128(postOpGasLimitOverride),
            uint8(IStartaleTokenPaymaster.PaymasterMode.INDEPENDENT),
            tokenAddress
        );

        userOp.paymasterAndData = pmData;
        userOp.signature = signUserOp(sender, userOp);
        userOpHash = ENTRYPOINT.getUserOpHash(userOp);
    }

    /// @notice Generates and signs the paymaster data for a user operation.
    /// @dev This function prepares the `paymasterAndData` field for a `PackedUserOperation` with the correct signature.
    /// @param userOp The user operation to be signed.
    /// @param signer The wallet that will sign the paymaster hash.
    /// @param paymaster The paymaster contract.
    /// @return finalPmData Full Pm Data.
    /// @return signature  Pm Signature on Data.
    function generateAndSignSponsorshipPaymasterData(
        PackedUserOperation memory userOp,
        Vm.Wallet memory signer,
        SponsorshipPaymaster paymaster,
        SponsorshipPaymasterData memory pmData
    ) internal view returns (bytes memory finalPmData, bytes memory signature) {
        // Initial paymaster data with zero signature
        userOp.paymasterAndData = abi.encodePacked(
            address(paymaster),
            pmData.validationGasLimit,
            pmData.postOpGasLimit,
            pmData.sponsorAccount,
            pmData.validUntil,
            pmData.validAfter,
            pmData.feeMarkup,
            new bytes(65) // Zero signature
        );

        {
            // Generate hash to be signed
            bytes32 paymasterHash =
                paymaster.getHash(userOp, pmData.sponsorAccount, pmData.validUntil, pmData.validAfter, pmData.feeMarkup);

            // Sign the hash
            signature = signMessage(signer, paymasterHash);
        }

        // Final paymaster data with the actual signature
        finalPmData = abi.encodePacked(
            address(paymaster),
            pmData.validationGasLimit,
            pmData.postOpGasLimit,
            pmData.sponsorAccount,
            pmData.validUntil,
            pmData.validAfter,
            pmData.feeMarkup,
            signature
        );
    }

    /// @notice Generates and signs the paymaster data for a user operation.
    /// @dev This function prepares the `paymasterAndData` field for a `PackedUserOperation` with the correct signature.
    /// @param userOp The user operation to be signed.
    /// @param signer The wallet that will sign the paymaster hash.
    /// @param paymaster The paymaster contract.
    /// @return finalPmData Full Pm Data.
    /// @return signature  Pm Signature on Data.
    function generateAndSignStartaleManagedPaymasterData(
        PackedUserOperation memory userOp,
        Vm.Wallet memory signer,
        StartaleManagedPaymaster paymaster,
        StartaleManagedPaymasterData memory pmData
    ) internal view returns (bytes memory finalPmData, bytes memory signature) {
        // Initial paymaster data with zero signature
        userOp.paymasterAndData = abi.encodePacked(
            address(paymaster),
            pmData.validationGasLimit,
            pmData.postOpGasLimit,
            pmData.validUntil,
            pmData.validAfter,
            new bytes(65) // Zero signature
        );

        {
            // Generate hash to be signed
            bytes32 paymasterHash = paymaster.getHash(userOp, pmData.validUntil, pmData.validAfter);

            // Sign the hash
            signature = signMessage(signer, paymasterHash);
        }

        // Final paymaster data with the actual signature
        finalPmData = abi.encodePacked(
            address(paymaster),
            pmData.validationGasLimit,
            pmData.postOpGasLimit,
            pmData.validUntil,
            pmData.validAfter,
            signature
        );
    }

    function generateAndSignTokenPaymasterDataExternalMode(
        PackedUserOperation memory userOp,
        Vm.Wallet memory signer,
        StartaleTokenPaymaster paymaster,
        TokenPaymasterDataExternalMode memory pmData
    ) internal view returns (bytes memory finalPmData, bytes memory signature) {
        // Initial paymaster data with zero signature
        userOp.paymasterAndData = abi.encodePacked(
            address(paymaster),
            pmData.validationGasLimit,
            pmData.postOpGasLimit,
            uint8(pmData.mode),
            pmData.validUntil,
            pmData.validAfter,
            pmData.tokenAddress,
            pmData.exchangeRate,
            pmData.appliedFeeMarkup,
            new bytes(65) // Zero signature
        );

        {
            // Generate hash to be signed
            bytes32 paymasterHash = paymaster.getHashForExternalMode(
                userOp,
                pmData.validUntil,
                pmData.validAfter,
                pmData.tokenAddress,
                pmData.exchangeRate,
                pmData.appliedFeeMarkup
            );

            // Sign the hash
            signature = signMessage(signer, paymasterHash);
        }

        // Final paymaster data with the actual signature
        finalPmData = abi.encodePacked(
            address(paymaster),
            pmData.validationGasLimit,
            pmData.postOpGasLimit,
            uint8(pmData.mode),
            pmData.validUntil,
            pmData.validAfter,
            pmData.tokenAddress,
            pmData.exchangeRate,
            pmData.appliedFeeMarkup,
            signature
        );
    }

    function getMaxPenalty(PackedUserOperation calldata userOp) public pure returns (uint256) {
        return (
            uint128(uint256(userOp.accountGasLimits))
                + uint128(bytes16(userOp.paymasterAndData[_PAYMASTER_POSTOP_GAS_OFFSET:_PAYMASTER_DATA_OFFSET]))
        ) * 10 * userOp.unpackMaxFeePerGas() / 100;
    }

    function getRealPenalty(PackedUserOperation calldata userOp, uint256 gasValue, uint256 gasPrice)
        public
        pure
        returns (uint256)
    {
        uint256 gasLimit = uint128(uint256(userOp.accountGasLimits))
            + uint128(bytes16(userOp.paymasterAndData[_PAYMASTER_POSTOP_GAS_OFFSET:_PAYMASTER_DATA_OFFSET]));

        uint256 penalty = (gasLimit - gasValue) * 10 * gasPrice / 100;
        return penalty;
    }

    // Todo: calculateAndAssertAdjustments helper could be added.

    function getPriceMarkups(
        SponsorshipPaymaster paymaster,
        uint256 initialSponsorAccountPaymasterBalance,
        uint256 initialFeeCollectorBalance,
        uint32 priceMarkup,
        uint256 maxPenalty
    ) internal view returns (uint256 expectedPriceMarkup, uint256 actualPriceMarkup) {
        uint256 resultingSponsorAccountPaymasterBalance = paymaster.getBalance(SPONSOR_ACCOUNT.addr);
        uint256 resultingFeeCollectorPaymasterBalance = paymaster.getBalance(PAYMASTER_FEE_COLLECTOR.addr);

        uint256 totalGasFeesCharged = initialSponsorAccountPaymasterBalance - resultingSponsorAccountPaymasterBalance;
        uint256 accountableGasFeesCharged = totalGasFeesCharged - maxPenalty;

        expectedPriceMarkup = accountableGasFeesCharged - ((accountableGasFeesCharged * 1e6) / priceMarkup);
        actualPriceMarkup = resultingFeeCollectorPaymasterBalance - initialFeeCollectorBalance;
    }

    function excludeLastNBytes(bytes memory data, uint256 n) internal pure returns (bytes memory) {
        require(data.length > n, "Input data is too short");
        bytes memory result = new bytes(data.length - n);
        for (uint256 i = 0; i < data.length - n; i++) {
            result[i] = data[i];
        }
        return result;
    }

    function _toSingletonArray(address addr) internal pure returns (address[] memory) {
        address[] memory array = new address[](1);
        array[0] = addr;
        return array;
    }

    function _toSingletonArray(uint48 element) internal pure returns (uint48[] memory) {
        uint48[] memory array = new uint48[](1);
        array[0] = element;
        return array;
    }

    function _toSingletonArray(IOracleHelper.TokenOracleConfig memory tokenOracleConfig)
        internal
        pure
        returns (IOracleHelper.TokenOracleConfig[] memory)
    {
        IOracleHelper.TokenOracleConfig[] memory array = new IOracleHelper.TokenOracleConfig[](1);
        array[0] = tokenOracleConfig;
        return array;
    }
}
