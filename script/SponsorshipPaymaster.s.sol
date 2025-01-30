// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {SponsorshipPaymaster} from "../src/sponsorship/SponsorshipPaymaster.sol";

contract DeploySponsorshipPaymaster is Script {
    address entryPoint;

    function setUp() public {
        // EntryPoint v0.7 address
        entryPoint = vm.parseAddress("0x0000000071727De22E5E9d8BAf0edAc6f37da032");
    }

    function run() public {
        uint256 salt = vm.envUint("SALT");
        address owner = vm.envAddress("OWNER");
        string[] memory signers = vm.envString("SIGNERS", ",");
        address[] memory signersAddr = new address[](signers.length);
        for (uint256 i = 0; i < signers.length; i++) {
            signersAddr[i] = vm.parseAddress(signers[i]);
        }

        run(salt, owner, signersAddr);
    }

    function run(uint256 _salt, address _owner, address[] memory _signers) public {
        vm.startBroadcast();
        SponsorshipPaymaster pm = new SponsorshipPaymaster{salt: bytes32(_salt)}(_owner, entryPoint, _signers);
        console.log("Sponsorship Paymaster Contract deployed at ", address(pm));
        vm.stopBroadcast();
    }
}
