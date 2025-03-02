#!/bin/bash

export PAYMASTER_ADDRESS="0x6510c0a04fd92Cd1C4E601973D64f5f7e3642E41"
export BUNDLER_URL="http://localhost:3000"

export ENTRY_POINT_ADDRESS="0x0000000071727De22E5E9d8BAf0edAc6f37da032"
export SIMPLE_ACCOUNT_FACTORY="0x91E60e0613810449d098b0b5Ec8b51A0FE8c8985"
export COUNTER_ADDRESS="0x0338Dcd5512ae8F3c481c33Eb4b6eEdF632D1d2f"

export SIMPLE_ACCOUNT_OWNER_PRIVATE_KEY=$(cat integration/keys/simpleAccount.key)
export PAYMASTER_SIGNER_PRIVATE_KEY=$(cat integration/keys/paymaster.key)
export PAYMASTER_OWNER_PRIVATE_KEY=$(cat integration/keys/deployer.key)


npm run test:integration

#Todo: make setup could only setup rundler
#And then go straight ahead in running hardhat tests where estimation happens with bundler if client is up. otherwise uses hard coded values
#npm run test:hardhat
