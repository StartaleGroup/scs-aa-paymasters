#!/bin/bash
set -x
cd "$(dirname "$0")"

# EntryPoint v0/7 contract address
ENTRYPOINT=0x0000000071727De22E5E9d8BAf0edAc6f37da032

# ========== Setup Node & Bundler ==========

./launcher.sh stop # kill already running processes if any
export DISABLE_ENTRY_POINT_V0_6=true
./launcher.sh start v0_7

# ========== Setup Deterministic Deployment Proxy ==========

# Deploy Create2Factory at `0x4e59b44847b379578588920ca78fbf26c0b4956c` as anvil has by default
../deterministic-deployment-proxy/deploy-deterministic-deployment-proxy.sh

# ========== Deploy paymaster contracts ==========

# Move back to the root directory
cd ../../

forge build

PAYMASTER_SIGNER=$(cast wallet address "$(cat integration/keys/paymaster.key)")
DEPLOYER=$(cast wallet address "$(cat integration/keys/deployer.key)")

## Fund deployer address
cast send --unlocked --from $(cast rpc eth_accounts | tail -n 1 | tr -d '[]"') --value 1000ether $DEPLOYER > /dev/null

## Deploy
### Paymaster

SALT=0x90d8084deab30c2a37c45e8d47f49f2f7965183cb6990a98943ef94940681de3 \
    OWNER="$DEPLOYER" \
    SIGNERS="$PAYMASTER_SIGNER" \
    forge script script/SponsorshipPaymaster.s.sol:DeploySponsorshipPaymaster \
    --rpc-url http://localhost:8545 --broadcast --private-key $(cat integration/keys/deployer.key)
