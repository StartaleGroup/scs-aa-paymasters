// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Script, console} from "forge-std/Script.sol";
import {StartaleManagedPaymaster} from "../src/sponsorship/StartaleManagedPaymaster.sol";

contract DeployStartaleManagedPaymaster is Script {
    // Note: When we deploy keep unaccountedGas around 11000
    address entryPoint;

    function setUp() public {
        // EntryPoint v0.7 address
        entryPoint = vm.parseAddress("0x0000000071727De22E5E9d8BAf0edAc6f37da032");
    }

    function run() public {
        // Load environment variables
        uint256 salt = vm.envUint("SALT");
        address owner = vm.envAddress("OWNER");

        // Parse signers from comma-separated string
        string[] memory signers = vm.envString("SIGNERS", ",");
        address[] memory signersAddr = new address[](signers.length);
        for (uint256 i = 0; i < signers.length; i++) {
            signersAddr[i] = vm.parseAddress(signers[i]);
        }

        run(salt, owner, signersAddr);
    }

    function run(uint256 _salt, address _owner, address[] memory _signers) public {
        vm.startBroadcast();
        StartaleManagedPaymaster pm = new StartaleManagedPaymaster{salt: bytes32(_salt)}(_owner, entryPoint, _signers);
        console.log("Startale Managed Paymaster Contract deployed at ", address(pm));
        vm.stopBroadcast();
    }
}
