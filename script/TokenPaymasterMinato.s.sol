// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

import {Script, console} from "forge-std/Script.sol";
import {StartaleTokenPaymaster} from "../src/token/startale/StartaleTokenPaymaster.sol";
import {IOracleHelper} from "../src/interfaces/IOracleHelper.sol";
import {IOracle} from "../src/interfaces/IOracle.sol";

contract DeployTokenPaymasterMinato is Script {
    address entryPoint;

    function setUp() public {
        // EntryPoint v0.7 address
        entryPoint = vm.parseAddress("0x0000000071727De22E5E9d8BAf0edAc6f37da032");
    }

    function run() public {
        // Load environment variables
        uint256 salt = vm.envUint("SALT");
        address owner = vm.envAddress("OWNER");
        address feeTreasury = vm.envAddress("TOKEN_FEE_TREASURY");
        uint256 unaccountedGas = vm.envUint("UNACCOUNTED_GAS");
        address nativeAssetToUsdOracle = vm.envAddress("NATIVE_ASSET_TO_USD_ORACLE");
        uint48 nativeAssetMaxOracleRoundAge = uint48(vm.envUint("NATIVE_ASSET_MAX_ORACLE_ROUND_AGE"));
        uint8 nativeAssetDecimals = 18;

        // Let's deploy with one Independent Token and more we can add later
        address astrAddress = vm.envAddress("ASTR_TOKEN_ADDERESS_MINATO");
        address astrToUsdOracle = vm.envAddress("ASTR_TO_USD_ORACLE");
        uint48 feeMarkupForIndependentToken = uint48(vm.envUint("FEE_MARKUP_FOR_INDEPENDENT_TOKEN"));
        uint48 astrMaxOracleRoundAge = uint48(vm.envUint("ASTR_MAX_ORACLE_ROUND_AGE"));

        // Parse signers from comma-separated string
        string[] memory signers = vm.envString("SIGNERS", ",");
        address[] memory signersAddr = new address[](signers.length);
        for (uint256 i = 0; i < signers.length; i++) {
            signersAddr[i] = vm.parseAddress(signers[i]);
        }

        run(
            salt,
            owner,
            signersAddr,
            feeTreasury,
            unaccountedGas,
            nativeAssetToUsdOracle,
            nativeAssetMaxOracleRoundAge,
            nativeAssetDecimals,
            _toSingletonArray(astrAddress),
            _toSingletonArray(feeMarkupForIndependentToken),
            _toSingletonArray(
                IOracleHelper.TokenOracleConfig({
                    tokenOracle: IOracle(address(astrToUsdOracle)),
                    maxOracleRoundAge: astrMaxOracleRoundAge
                })
            )
        );
    }

    function run(
        uint256 _salt,
        address _owner,
        address[] memory _signers,
        address _feeTreasury,
        uint256 _unaccountedGas,
        address _nativeAssetToUsdOracle,
        uint48 _nativeAssetMaxOracleRoundAge,
        uint8 _nativeAssetDecimals,
        address[] memory _independentTokens,
        uint48[] memory _feeMarkupsForIndependentTokens,
        IOracleHelper.TokenOracleConfig[] memory _tokenOracleConfigs
    ) public {
        vm.startBroadcast();
        StartaleTokenPaymaster pm = new StartaleTokenPaymaster{salt: bytes32(_salt)}(
            _owner,
            entryPoint,
            _signers,
            _feeTreasury,
            _unaccountedGas,
            _nativeAssetToUsdOracle,
            address(0),
            _nativeAssetMaxOracleRoundAge,
            _nativeAssetDecimals,
            _independentTokens,
            _feeMarkupsForIndependentTokens,
            _tokenOracleConfigs
        );
        console.log("Token Paymaster Contract deployed at ", address(pm));
        vm.stopBroadcast();
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
