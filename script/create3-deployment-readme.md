# Deploying the Deployer contract

We need consistent msg.sender with unused 0 nonce on the chain to be deployed.

Startale will maintain an EOA address that would deploy the deployer contract.

another funding EOA can fund deployer deployer EOA as part of the script then Create3 Deployer is deployed.
(current deployer deployer EOA : 0xd3F344fd7461f55Bb4A78B37b622DBf4112263F4)

Startale Deployer: 
https://soneium-minato.blockscout.com/address/0x3C02c039a7f38699bC548D0f324c92bD7FeA7800?tab=contract
https://soneium.blockscout.com/address/0x3C02c039a7f38699bC548D0f324c92bD7FeA7800



# Generating salt

https://github.com/livingrockrises/create3
`cargo run`

We can generate salt for our desired number of zeros in to-be-deployed contract, by providing deployer address.

Current salt for paymaster: SPONSORSHIP_PAYMASTER_V_0_0_1_SALT_R0gvhZ9
using deployer: 0x3C02c039a7f38699bC548D0f324c92bD7FeA7800
fixed deployment address (independent of constructor args): 0x00000864Bbb7B8F0D42D41026f2D1c774CEcb6dD


# Deploying protocol contracts using deployed Create3 Deployer

this needs bytecode, salt and constructor args.
check src/script/DeploySponsorshipPaymasterCreate3.s.sol for example

Deployed address: https://soneium-minato.blockscout.com/address/0x00000864bbb7b8f0d42d41026f2d1c774cecb6dd?tab=contract


# What is CREATE3

CREATE3
CREATE3 isn't itself an EVM opcode but a method that uses CREATE and CREATE2 in combination to eliminate the bytecode from contract address calculation.

Internally, first CREATE2 is used to deploy a CREATE factory or "proxy" which then deploys your contract. So the only data required for address calculation is:

address of the factory contract itself;
salt (a chosen value).
CREATE3 factories may also factor in the address of the account that uses the factory to deploy the contract in order to ensure uniqueness of the deployment address. Using a factory that doesn't factor in the account address may be insecure, as then someone else could front-run deployment of your contract to the same address as yours by using the same salt as in your existing deployments and become the owner of it.

As bytecode no longer affects address, you won't have to worry about accidentally making changes to your contracts (which would cause a different deployment address if you used CREATE2).

It also makes it possible to:

Deploy your contract with updated code / using newer compiler on a new blockchain that will have the same address as the older version that had already been deployed on other blockchains;
use different constructor arguments on different blockchains.

more details here: https://github.com/SKYBITDev3/SKYBIT-Keyless-Deployment 