# SCS AA Paymasters

## Overview

AA Paymasters smart contract repository.
Utilizing Foundary `forge` for contracts development.

## Pre Requisites

### Git Submodules

```
git clone git@github.com:StartaleLabs/scs-aa-paymasters.git
cd scs-aa-paymasters
git submodule update --init --recursive
```

※ You may need to execute `git submodule update --init --recursive` twice for Rundler compilation. This is because of submodules of our submodule Rundler.

### Foundry

Utilizing `forge` a part of Foundry's tool heavilly in this project.

Doc: https://book.getfoundry.sh/
Installation: https://book.getfoundry.sh/getting-started/installation

```
curl -L https://foundry.paradigm.xyz | bash
```

**Forge version `0.3.0` or higher is required.**

## Develop

Repository is structured based on Foundry's project layout.
See more details here: https://book.getfoundry.sh/projects/project-layout.

`src`: Solidity smart contracts

`scripts`: Utility scripts for various purposes written in Solidity

`test`: Unit tests for smart contracts in `src` folder, written in Solidity

`lib`: Dependency libraries for our smart contracts, managed by git submodules

### Build

```
forge build
```

### Tests

#### Unit Tests

```
forge test # or make test
```

#### Integration Test

```
npm i
make setup
make integration
```

## Deploy

Deploy using forge create2

```
# deploy
source .env && forge script script/SponsorshipPaymaster.s.sol:DeploySponsorshipPaymaster \
    --rpc-url https://rpc.minato.soneium.org \
    --broadcast \
    --private-key $PRIVATE_KEY

# and verify
forge verify-contract \
  --rpc-url $RPC_URL \
  --verifier blockscout \
  --verifier-url 'https://$BLOCKSCOUT_HOST/api/' \
  $CONTRACT_ADDRESS \
src/sponsorship/SponsorshipPaymaster.sol:SponsorshipPaymaster --watch
```

### Deployed Contract addresses

**Sponsorship Paymaster**

| Network        | Address                                                                                                                                                                                                                                                      |
| -------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Soneium Minato | `0x1F34E9253395df78bA8545d54e0a1576010cC025` (salt:`0x90d8084deab30c2a37c45e8d47f49f2f7965183cb6990a98943ef94940681de3`, constructor owner: `0xFc035b327d67E3d12f207C6A3fE5d5Ed67ADe5BE`, constructor signers `0xFc035b327d67E3d12f207C6A3fE5d5Ed67ADe5BE`, FEE_COLLECTOR `0xFc035b327d67E3d12f207C6A3fE5d5Ed67ADe5BE`, MIN_DEPOSIT `1000000000000000`WITHDRAWAL_DELAY `60`, SPONSERSHIP_PM_UNACCOUNTED_GAS `11000`) |

**Token Paymaster**

deployed with ASTR token support from beginning (Independent mode)

#####Initial draft is deployed at below address

| -------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Soneium Minato | `0xC7d6d41DeDbfB365469FF2FFB2c89c11aC41d4f0..` (salt:`0x90d8084deab30c2a37c45e8d47f49f2f7965183cb6990a98943ef94940681de3`, constructor owner: `0xFc035b327d67E3d12f207C6A3fE5d5Ed67ADe5BE`, constructor signers `0xFc035b327d67E3d12f207C6A3fE5d5Ed67ADe5BE`, TOKEN_FEE_TREASURY`0xFc035b327d67E3d12f207C6A3fE5d5Ed67ADe5BE`, TOKEN_PM_UNACCOUNTED_GAS `40000`), ASTR_ADDRESS `0x26e6f7c7047252DdE3dcBF26AA492e6a264Db655` | ASTR_USD_FEED_ADDRESS `0x1e13086Ca715865e4d89b280e3BB6371dD48DabA` | ETH_USD_FEED_ADDRESS `0xCA50964d2Cf6366456a607E5e1DBCE381A8BA807` 


**Startale Managed Paymaster**

| Network        | Address                                                                                                                                                                                                                                                      |
| -------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Soneium Minato | `0x159DD1E396B655B683603CA6eaA7E78708c0f6Af` (salt:`0x90d8084deab30c2a37c45e8d47f49f2f7965183cb6990a98943ef94940681de3`, constructor owner: `0x2cf491602ad22944D9047282aBC00D3e52F56B37`, constructor signers `0xFc035b327d67E3d12f207C6A3fE5d5Ed67ADe5BE`) |