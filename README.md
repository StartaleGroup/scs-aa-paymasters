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
| Soneium Minato | `0x653ceAB2A4918641e9996850B0F4F30b51085076` (salt:`0x90d8084deab30c2a37c45e8d47f49f2f7965183cb6990a98943ef94940681de3`, constructor owner: `0xFAD1f284416fA799647e25064D5F75b90e95664e`, constructor signers `0xFc035b327d67E3d12f207C6A3fE5d5Ed67ADe5BE` ) |

sender: '0x5237d12F6800E66dF678A9b8786faa855e39A268',
callData: '0xb61d27f60000000000000000000000000338dcd5512ae8f3c481c33eb4b6eedf632d1d2f00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000000000000000000000406661abd00000000000000000000000000000000000000000000000000000000',
factory: '0x91E60e0613810449d098b0b5Ec8b51A0FE8c8985',
factoryData: '0x5fbfb9cf00000000000000000000000080192a0664bd7ca726fffbbcf66b4e153e6cb9310000000000000000000000000000000000000000000000000000000000000000',
maxFeePerGas: 199276027298n,
maxPriorityFeePerGas: 198659353398n,
nonce: 32061731052143554838986127048704n,
signature: '0xfffffffffffffffffffffffffffffff0000000000000000000000000000000007aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa1c',
callGasLimit: 31672n,
preVerificationGas: 51908n,
verificationGasLimit: 251165n,
paymasterPostOpGasLimit: undefined,
paymasterVerificationGasLimit: undefined,
paymaster: '0x68E142810A3d15C568C97304D1F9dF257860684a',
paymasterData: '0x000000000000000000000000000000000000123400000000000000000000000000000005'
}
0x8a0299cfdf4104dfe572fd2c1d8c0242449da56b6395144c382026e503ef42502d28aa7613156a128ec83e588d76719b75f2d04e29655de159b035eef6a49a051c 1) Counter incremented sponsored by Paymaster

1 passing (356ms)
1 failing

1. EntryPoint v0.7 with SponsorshipPaymaster
   succeed with valid signature
   Counter incremented sponsored by Paymaster:
   UserOperationExecutionError: UserOperation rejected because account signature check failed (or paymaster signature, if the paymaster uses its data as signature).

Request Arguments:
callData: 0xb61d27f60000000000000000000000000338dcd5512ae8f3c481c33eb4b6eedf632d1d2f00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000000000000000000000406661abd00000000000000000000000000000000000000000000000000000000
callGasLimit: 31672
factory: 0x91E60e0613810449d098b0b5Ec8b51A0FE8c8985
factoryData: 0x5fbfb9cf00000000000000000000000080192a0664bd7ca726fffbbcf66b4e153e6cb9310000000000000000000000000000000000000000000000000000000000000000
maxFeePerGas: 199.276027298 gwei
maxPriorityFeePerGas: 198.659353398 gwei
nonce: 32061731052143554838986127048704
paymaster: 0x68E142810A3d15C568C97304D1F9dF257860684a
paymasterData: 0x0000000000000000000000000000000000001234000000000000000000000000000000058a0299cfdf4104dfe572fd2c1d8c0242449da56b6395144c382026e503ef42502d28aa7613156a128ec83e588d76719b75f2d04e29655de159b035eef6a49a051c
paymasterVerificationGasLimit: 251165
preVerificationGas: 51908
sender: 0x5237d12F6800E66dF678A9b8786faa855e39A268
signature: 0x66632e47edb682d0d83e5a10bd3b4185d932d8bb5b7f8d56fb5c9ff4ab0d1ff24b979a9a89b447b8d385ec191b64dae7c25e55b0117c2a9233c8253259c679661c
verificationGasLimit: 251165

Details: Invalid paymaster signature
Version: viem@2.21.60
