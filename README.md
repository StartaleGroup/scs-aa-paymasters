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

| Contract Name                  | Address                                      |
|--------------------------------|----------------------------------------------|
| Postpaid Sponsorship Paymaster | `0x00000095901E8AB695Dc24FA52B0Cce15E9896Ad` |
| Prepaid Sponsorship Paymaster  | `0x0000002deA684Ecd1979140746CF415AD46D8b16` |
| Startale Token Paymaster       | `0x0000006C18daC1Ff8F50Df743F7587a8b7d8a8a7` |
