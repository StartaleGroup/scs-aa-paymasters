// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {Deployer} from "../src/deployer/Deployer.sol";

contract DeployDeployer is Script {
    mapping(uint256 => uint256) public DEPLOYMENT_CHAIN_GAS_PRICES;

    function setUp() public {
        DEPLOYMENT_CHAIN_GAS_PRICES[1946] = 0.002 gwei;
    }

    function run() public {
        uint256 DEPLOYMENT_FEE = 0.001 ether; // Deployment fee
        console.log("DEPLOYMENT_FEE:", DEPLOYMENT_FEE);

        // Load values from `.env`
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_CONTRACT_DEPLOYER_PRIVATE_KEY");
        uint256 fundingPrivateKey = vm.envUint("FUNDING_ACCOUNT_PRIVATE_KEY");

        address deployerAddress = vm.addr(deployerPrivateKey);
        address fundingAddress = vm.addr(fundingPrivateKey);

        console.log("Deployer Address:", deployerAddress);
        console.log("Funding Address:", fundingAddress);

        // Get chain ID
        uint256 chainId = block.chainid;

        uint256 gasPrice = DEPLOYMENT_CHAIN_GAS_PRICES[chainId];
        require(gasPrice > 0, "No deployment gas price set for this chain");

        // Compute the contract address of the deployer (nonce = 0)
        address deployerContractAddress = getContractAddress(deployerAddress, 0);

        console.log("Checking deployer contract at:", deployerContractAddress);

        // Check if contract is already deployed
        uint256 codeSize;
        assembly {
            codeSize := extcodesize(deployerContractAddress)
        }

        if (codeSize == 0) {
            console.log("Deployer contract has not been deployed yet");

            uint256 deployerBalance = deployerAddress.balance;
            uint256 fundingBalance = fundingAddress.balance;

            console.log("Deployer Balance (ETH):", deployerBalance / 1 ether);
            console.log("Funding Account Balance (ETH):", fundingBalance / 1 ether);

            // Ensure deployer has enough balance
            if (deployerBalance < DEPLOYMENT_FEE) {
                uint256 fundsNeeded = DEPLOYMENT_FEE - deployerBalance;
                console.log("Funding deployer with:", fundsNeeded / 1 ether, "ETH");

                require(fundingBalance > fundsNeeded, "Not enough funds in funding account");

                // Fund the deployer account
                vm.startBroadcast(fundingPrivateKey);
                payable(deployerAddress).transfer(fundsNeeded);
                vm.stopBroadcast();

                console.log("Funds transferred to deployer.");
            }

            // Deploy contract using deployer's private key
            console.log("Deploying Deployer Contract...");
            vm.startBroadcast(deployerPrivateKey);
            Deployer deployerContract = new Deployer();
            vm.stopBroadcast();

            console.log("Deployer Contract deployed at:", address(deployerContract));
        } else {
            console.log("Deployer Contract already exists at:", deployerContractAddress);
        }
    }

    /// @dev Compute the contract address using CREATE formula: keccak256(RLP(sender, nonce))
    function getContractAddress(address deployer, uint256 nonce) public pure returns (address) {
        bytes memory data;

        if (nonce == 0x00) {
            data = abi.encodePacked(bytes1(0xd6), bytes1(0x94), deployer, bytes1(0x80));
        } else if (nonce <= 0x7f) {
            data = abi.encodePacked(bytes1(0xd6), bytes1(0x94), deployer, uint8(nonce));
        } else if (nonce <= 0xff) {
            data = abi.encodePacked(bytes1(0xd7), bytes1(0x94), deployer, bytes1(0x81), uint8(nonce));
        } else if (nonce <= 0xffff) {
            data = abi.encodePacked(bytes1(0xd8), bytes1(0x94), deployer, bytes1(0x82), uint16(nonce));
        } else if (nonce <= 0xffffff) {
            data = abi.encodePacked(bytes1(0xd9), bytes1(0x94), deployer, bytes1(0x83), uint24(nonce));
        } else {
            data = abi.encodePacked(bytes1(0xda), bytes1(0x94), deployer, bytes1(0x84), uint32(nonce));
        }

        return address(uint160(uint256(keccak256(data))));
    }

    function run(bytes32 _salt, bytes memory _creationCode) public {
        vm.startBroadcast();
        Deployer d = new Deployer();
        d.deploy(_salt, _creationCode);
        vm.stopBroadcast();
    }
}
