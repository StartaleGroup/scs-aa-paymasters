// Which tokens do we have on Soneium?
// Which tokens we must support? besides wrapped ASTR ERC20

// Do we have Chainlink price feeds on Soneium mainnet and minato?  Yes!!
// ^ https://docs.chain.link/data-feeds/price-feeds/addresses?network=soneium&page=1 

// Do we have Uniswap V3 router on Soneium? Which pools are created? What are the addresses?
// All reference links here...

// 






-----------------------------
1. Supporting one token per pm vs multiple

single token pm can be more/fully decentralised

supporting multiple tokens with different modes (independent / external backed service based) can make paymaster extensible to support more.




-------------------------------
2. Multiple modes for paymaster
and paymasterData structure in each case

a. Infinitism
paymasterData is 0x or user supplied price
uses precharge and refund model
maintains cached price
no mode

b. Pimlico
uses VERIFYING_MODE and ERC20_MODE
hybrid paymaster for sponsorship and erc20 (sponsroship is postpaid)

c. Circle
1 token per pm. token must support EIP2612 permit
permit signature is received in paymasterData
you call token.permit to make approval and then precharge
still uses pre-charge & refund model.
one good thing they have done is also calculating potential penalty. this may be implemented in sponsorship paymaster as well!



---------------------------------
3. Precharge & Refund model vs Charging only in postOp (depending on mode)


Precharge requires to call safeTransferFrom in validatePaymasterUserOp -> pre approval must be given
Charging only in postOp -> requires some guarantee (probably besides just checking enough balance in validation stage) 

Approval can be done if permit/permit2 sig is received before execution.

////
What we want to do in validation stage
TBD..

////
What we want to do in postOp stage
TBD..



--------------------------------
4. Swapping logic for ERC20 back to Eth

- Integrate uniswap base for (optional) swapping functionality

// check refillEntryPointDeposit reference in Infinitism: 

  how often: 
  a. if balance is below threshold [ Infinitism ]
  (along with this you can have manual withdraw to some address then trigger swaps)
  b. flag based
  c. manual withdraw to treasury / always sending to feeCollector treasury and handling off-chain based on need.




---------------------------------
5. misc

Deposit Paymaster: user's ERC20 gas tank. pre deposits




-----------------------------------
Comments


business offering / product / money flows

1. Sponsorship PM

prepaid singleton : all dapps deposit eth (to sponsor on behalf of their users) to same pm and we charge premium
prepaid singleton : dapps could deposit in ASTR? (wrapper)
postpaid : can be combined with erc20 as hybrid paymaster. all we do is front the gas


2. ERC20 PM

startale managed singleton: we manage ETH deposits and collect ERC20 from users of all dapps, charge premium directly to users
1. 1 pm per token (independent mode. oracle based) 
2. n tokens supported by paymaster with independent and external both modes.
// 1 token per pm for all independent tokens.  [ N ]
// 1 another pm for other tokens that requires exchangeRate from service(external)
N + 1 contracts


dapp managed: (1 contract per dapp) dapp manages eth deposits and receives erc20 in their own treasury. they can configure. premium: all received by dapp or shared deal




