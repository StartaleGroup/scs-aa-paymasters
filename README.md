# SCS AA Paymasters

## Overview

AA Paymasters smart contract repository.
Utilizing Foundary `forge` for contracts development.

## Pre Requisites

### Git Submodules\*\*

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

### Test (Unit tests)

```
forge test
```

## Integration Tests

Integration tests are writen and executed by Typescript, mocha, chai test frameworks.
Those are outside of `forge`'s management, if folders/files namings conflict with `forge` in the future, we need to adjust it.

### Installing packages

```
npm i
```

### Execute tests

```
make test-v0_7 {PAYMASTER_ADDRESS}
```

### Addresses

**Smart Contracts**

| Name                   | Address                                      |
| ---------------------- | -------------------------------------------- |
| EntryPoint v0.7        | `0x0000000071727De22E5E9d8BAf0edAc6f37da032` |
| Simple Account Factory | `0x91E60e0613810449d098b0b5Ec8b51A0FE8c8985` |
| Test Counter           | `0x0338Dcd5512ae8F3c481c33Eb4b6eEdF632D1d2f` |
| Sponsorship Paymaster  | ※1 Determined after deploy                   |

※1 Forge script to use Create2 for deterministic contract address (https://book.getfoundry.sh/tutorials/create2-tutorial) is not supported in local dev network. Once finding out how to make it work, use deterministic address for paymaster as well. Until that, copy&paste paymaster contract address everytime for integration test execution.

**EOAs**

| Name                        | Address                                      |
| --------------------------- | -------------------------------------------- |
| Paymaster Contract Deployer | `0x6B82272b4798B99Fc1ccC55a03De0af841B0DfA7` |
| SimpleAccount Owner         | `0x80192a0664bd7ca726FfFbbcf66b4E153E6cb931` |
| Paymaster Data Signer       | `0x50862587C070038AD00752F5bcd23F9148a2d744` |
