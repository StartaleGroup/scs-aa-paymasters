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
SALT=$SALT OWNER=$OWNER SIGNERS=$SIGNERS_COMMA_DELIMITED forge script script/SponsorshipPaymaster.s.sol:DeploySponsorshipPaymaster --rpc-url $RPC_URL --broadcast --private-key $PRIV_KEY

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
| Soneium Minato | `0x0a54E88C337e54989E38a8d4D8dcA4A38cC5A96b` (salt:`0x90d8084deab30c2a37c45e8d47f49f2f7965183cb6990a98943ef94940681de3`, constructor owner: `0xFAD1f284416fA799647e25064D5F75b90e95664e`, constructor signers `0xFc035b327d67E3d12f207C6A3fE5d5Ed67ADe5BE` ) |
