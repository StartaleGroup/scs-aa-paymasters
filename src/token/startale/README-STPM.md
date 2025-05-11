# Token Paymaster Contract - EP v0.7.0

The **Token Paymaster** contract facilitates **paying gas using ERC20 tokens** for **UserOperations** in **ERC-4337 Account Abstraction**. It securely validates **ERC20 balance**, and ensures **charging in ERC20** using postOp() flow of **EntryPoint**.

## 🔹 Core Functionalities

### Premium and fee collection

tokenFeeTreasury is the address where all the collected ERC20 tokens will go to. This is configurable to be the contract address itself so we can do infrequent/frequent swaps(and deposit to entrypoint)

premium is set for independent mode tokens. premium for external mode tokens is received from paymaster and data. 

price oracle helper is used to maintain chainlink oracle information.



### Secure Paymaster Validation (`_validatePaymasterUserOp`)

- **Parses `paymasterAndData`** to extract: mode and modeSpecific data
- validates the mode
- mode is INDEPENDENT
  -- check if the token is supposed on the contract
  -- get the set price markup on the contract
  -- prepare the context
  -- pass exchangeRate 0 so postOp can query it from oracles.


- mode is EXTERNAL
  -- validate paymaster signature
  -- check supplied fee markup
  -- prepare the context and passes on the exchange rate.

- Do Not validate balance (requires exchange rate)
- Do Not pre-charge (requires prior approval)


### Post-Operation

- Query the exchange rate in case it is not found in the context(supplied 0)
- **Calculates actual gas costs** and adjusts for **EntryPoint overhead gas**.(unaccountedGas is gas not accounted for postOp and within the entrypoint)
- **Applies price markup**
- Transfers the tokens + fees to current set tokenFeeTreasury.



## 🔹 Features under consideration

#### On-chain means of replenishing the paymaster. Using uniswap router to make a swap between collected ERC20 to ETH and deposit them on the Entrypoint.
#### Applying caching logic for exchange rate in case of Independent mode.
#### Extra validations
