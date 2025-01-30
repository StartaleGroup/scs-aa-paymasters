#!/bin/bash

export PAYMASTER_ADDRESS="0x717E095C7c7fF763e35C5Ed0548f211EB36F32b1"
export BUNDLER_URL="http://localhost:3000"

export ENTRY_POINT_ADDRESS="0x0000000071727De22E5E9d8BAf0edAc6f37da032"
export SINPLE_ACCOUNT_FACTORY="0x91E60e0613810449d098b0b5Ec8b51A0FE8c8985"
export COUNTER_ADDRESS="0x0338Dcd5512ae8F3c481c33Eb4b6eEdF632D1d2f"

export SIMPLE_ACCOUNT_OWNER_PRIVATE_KEY=$(cat integration/keys/simpleAccount.key)
export PAYMASTER_SIGNER_PRIVATE_KEY=$(cat integration/keys/paymaster.key)
export PAYMASTER_OWNER_PRIVATE_KEY=$(cat integration/keys/deployer.key)

npm run test
