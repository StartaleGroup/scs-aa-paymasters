import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "@nomicfoundation/hardhat-foundry";

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.29", // adjust version as needed
    settings: {
      optimizer: {
        enabled: true,
        runs: 999,
      },
      evmVersion: "cancun",
      viaIR: true,
    },
  },
  paths: {
    sources: "./src", // Use src instead of contracts
    tests: "./test/hardhat", // Separate Hardhat tests
    cache: "./cache/hardhat", // Separate Hardhat cache
    artifacts: "./artifacts/hardhat", // Separate Hardhat artifacts
  },
};

export default config;
