#!/bin/bash
set -x
cd "$(dirname "$0")"

ENTRYPOINT=0x0000000071727De22E5E9d8BAf0edAc6f37da032

# ========== Setup Node & Bundler ==========

./launcher.sh stop # kill already running processes if any
export DISABLE_ENTRY_POINT_V0_6=true
./launcher.sh start v0_7

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
forge create --rpc-url http://localhost:8545 --constructor-args $ENTRYPOINT [$PAYMASTER_SIGNER] \
    --private-key $(cat integration/keys/deployer.key) src/v0_7/sponsorship/SponsorshipPaymaster.sol:SponsorshipPaymaster
