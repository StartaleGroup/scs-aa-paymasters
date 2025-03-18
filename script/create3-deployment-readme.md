# Deploying the Deployer contract

We need consistent msg.sender with unused 0 nonce on the chain to be deployed.

Startale will maintain an EOA address that would deploy the deployer contract.

another funding EOA can fund deployer deployer EOA as part of the script then Create3 Deployer is deployed.

Startale Deployer: https://soneium-minato.blockscout.com/address/0x3C02c039a7f38699bC548D0f324c92bD7FeA7800?tab=contract



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