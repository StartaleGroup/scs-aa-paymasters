import { equal } from "assert";
import { createPublicClient, createWalletClient, keccak256, encodePacked, toBytes, fromHex, http, PublicClient, WalletClient, parseEther, encodeFunctionData, type Hex } from 'viem'
import { BundlerClient, createBundlerClient, toPackedUserOperation, UserOperation } from 'viem/account-abstraction'
import { localhost } from 'viem/chains'
import { privateKeyToAccount } from 'viem/accounts'
import { toSimpleSmartAccount } from "permissionless/accounts"
import { expect } from 'chai'
import * as fs from 'fs';
import * as path from 'path';

const BUNDLER_URL = "http://localhost:3000";

const ENTRY_POINT_V0_7_JSON_PATH = "../abis/v0_7/EntryPoint.json";
const SPONSORSHIP_PAYMASTER_JSON_PATH = "../abis/v0_7/SponsorshipPaymaster.json";
const COUNTER_JSON_PATH = "../abis/TestCounter.json";

// pre determined addresses
const ENTRY_POINT_V0_7_ADDRESS = "0x0000000071727De22E5E9d8BAf0edAc6f37da032";
const SINPLE_ACCOUNT_FACTORY = "0x91E60e0613810449d098b0b5Ec8b51A0FE8c8985";
const COUNTER_ADDRESS = "0x0338Dcd5512ae8F3c481c33Eb4b6eEdF632D1d2f";

// addresses passed as arguments
const BUNDLER_ADDRESS = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266";
const PAYMASTER_ADDRESS = "0x1d4FE85F34059Be6D73D990E2c3595E920553d52";

const MOCK_VALID_UNTIL = 0;
const MOCK_VALID_AFTER = 0;
const MOCK_SIG = '0x1234';

const DEFAULT_VERIFICATION_GAS_LIMIT = 150000; // default verification gas. will add create2 cost (3200+200*length) if initCode exists
const DEFAULT_PRE_VERIFICATION_GAS = 21000; // should also cover calldata cost.

function getPaymasterData(validUntil: number, validAfter: number) {
  const data = {
    preVerificationGas: BigInt(100_000),
    postOpGas: BigInt(50_000),
    validUntil,
    validAfter,
  }

  return encodePacked(
    ['uint128', 'uint128', 'uint48', 'uint48'],
    [data.preVerificationGas, data.postOpGas, data.validUntil, data.validAfter],
  )
}

function getDummyPaymasterData(): Hex {
  return encodePacked(
    [
        "uint128", // preVerificationGas
        "uint128", // postOpGas
        "uint48", // validUntil
        "uint48", // validAfter
        "bytes" // signature
    ],
    [
        BigInt(100_000),
        BigInt(50_000),
        0,
        0,
        "0xcd91f19f0f19ce862d7bec7b7d9b95457145afc6f639c28fd0360f488937bfa41e6eedcd3a46054fd95fcd0e3ef6b0bc0a615c4d975eef55c8a3517257904d5b1c"
    ]
  )
}

const maxBigInt = (a: bigint, b: bigint) => {
  return a > b ? a : b
}

describe("EntryPoint v0.7 with SponsorshipPaymaster", () => {
  let publicClient: PublicClient;
  let walletClient: WalletClient;
  let bundlerClient: BundlerClient;
  let entryPointAbi;
  let sponsorshipPaymasterAbi;
  let counterAbi;

  before(async () => {
    entryPointAbi = JSON.parse(
      fs.readFileSync(path.resolve(__dirname, ENTRY_POINT_V0_7_JSON_PATH), 'utf8')
    );

    sponsorshipPaymasterAbi = JSON.parse(
      fs.readFileSync(path.resolve(__dirname, SPONSORSHIP_PAYMASTER_JSON_PATH), 'utf8')
    );

    counterAbi = JSON.parse(
      fs.readFileSync(path.resolve(__dirname, COUNTER_JSON_PATH), 'utf8')
    );

    // @ts-ignore
    publicClient = createPublicClient({
      chain: localhost,
      transport: http(),
    });

    walletClient = createWalletClient({
      chain: localhost,
      transport: http(),
    });

    bundlerClient = createBundlerClient({
      // @ts-ignore
      client: publicClient,
      transport: http(BUNDLER_URL)
    })

    const [address] = await walletClient.getAddresses();
    console.log("Default Wallet Client Address: ", address);
    console.log("Default Wallet Balance: ", await publicClient.getBalance({
      address: address,
    }));

    // Make sure the Bundler EOA has sufficient amount of ETH
    console.log("Bundler Address: ", BUNDLER_ADDRESS);
    const bundlerBalance = await publicClient.getBalance({
      address: BUNDLER_ADDRESS,
    });
    if (bundlerBalance === BigInt(0)) {
      console.log("Bundler EOA has no ETH, please fund it first");
      process.exit(1);
    }
    console.log("Bundler Balance: ", bundlerBalance);

    // @ts-ignore
    await walletClient.sendTransaction({
      account: privateKeyToAccount("0xb10784b3e33005aa8e83faca861cbda4794399bd1a25746fcece4fc93e4dccc8"),
      to: PAYMASTER_ADDRESS,
      value: parseEther("2"),
      data: encodeFunctionData({
        abi: sponsorshipPaymasterAbi,
        functionName: "addStake",
        args: [1],
      })
    });

    // Deposit ETH to Paymaster address in EntryPoint contract
    // @ts-ignore
    await walletClient.sendTransaction({
      account: address,
      to: ENTRY_POINT_V0_7_ADDRESS,
      value: parseEther("1"),
      data: encodeFunctionData({
        abi: entryPointAbi,
        functionName: "depositTo",
        args: [PAYMASTER_ADDRESS],
      }),
    });

    const depositedBalance = await publicClient.readContract({
      address: ENTRY_POINT_V0_7_ADDRESS,
      abi: entryPointAbi,
      functionName: "balanceOf",
      args: [PAYMASTER_ADDRESS],
    })
    console.log("Paymaster Deposited Balance: ", depositedBalance);

    const isSigner = await publicClient.readContract({
      address: PAYMASTER_ADDRESS,
      abi: sponsorshipPaymasterAbi,
      functionName: "signers",
      args: [privateKeyToAccount("0x574d33f5ba32008ca486410a245aabf52f30a16424222cf8092a8a5950bfbf3d").address],
    })
    console.log("Is Signer: ", isSigner);
  })

  describe('#parsePaymasterAndData', () => {
    it('should parse data properly', async () => {
      const paymasterAndData = encodePacked(
        [
          "address", // paymaster
          "uint128", // paymasterVerificationGasLimit
          "uint128", // paymasterPostOpGasLimit
          "uint48", // validUntil
          "uint48", // validAfter
          "bytes" // signature
        ],
        [
          PAYMASTER_ADDRESS,
          BigInt(DEFAULT_VERIFICATION_GAS_LIMIT),
          BigInt(DEFAULT_PRE_VERIFICATION_GAS),
          MOCK_VALID_UNTIL,
          MOCK_VALID_AFTER,
          MOCK_SIG
        ]
      )
      console.log('PAYMASTER AND DATA: ', paymasterAndData)
      const res = await publicClient.readContract({
        address: PAYMASTER_ADDRESS,
        abi: sponsorshipPaymasterAbi,
        functionName: "parsePaymasterAndData",
        args: [paymasterAndData],
      });

      expect(res[0]).to.be.equal(MOCK_VALID_UNTIL);
      expect(res[1]).to.be.equal(MOCK_VALID_AFTER);
      expect(res[2]).to.be.equal(MOCK_SIG);
    })
  });

  describe("succeed with valid signature", () => {
    it("Counter incremented sponsored by Paymaster", async () => {
      // Create a simple smart account
      const simpleAccount = await toSimpleSmartAccount({
        // @ts-ignore
        client: publicClient,
        owner: privateKeyToAccount("0x7dcbb1e4a86ca0cb4a2c5b1edd48dce20e51ca4d0f08acec88db276e961ca500"),
        factoryAddress: SINPLE_ACCOUNT_FACTORY,
        entryPoint: {
          address: ENTRY_POINT_V0_7_ADDRESS,
          version: "0.7",
        },
      })
  
      // Hold pre user operation data
      const preAccountBalance = await publicClient.getBalance({address: simpleAccount.address});
      const preCounterValue = await publicClient.call({
        to: COUNTER_ADDRESS,
        data: encodeFunctionData({
          abi: counterAbi,
          functionName: 'counters',
          args: [simpleAccount.address]
        })
      }).then((response) => fromHex(response.data, "number"));

      const userOp = await bundlerClient.prepareUserOperation({
        account: simpleAccount,
        calls: [{
          to: COUNTER_ADDRESS,
          // @ts-ignore
          value: 0n,
          // @ts-ignore
          data: encodeFunctionData({
            abi: counterAbi,
            functionName: "count"
          }),
        }],
      });
  
      // Prepare paymaster data
      const paymasterData = getPaymasterData(0, 0); // no expiration
  
      // Before Hashing
      userOp.paymaster = PAYMASTER_ADDRESS;
      userOp.paymasterData = paymasterData;

      console.log("BEFORE HASHING PACKED USER OPERATION")
      console.log(toPackedUserOperation(userOp))
      const hash = await publicClient.readContract({
        address: PAYMASTER_ADDRESS,
        abi: sponsorshipPaymasterAbi,
        functionName: "getHash",
        args: [toPackedUserOperation(userOp)],
      });
      
      console.log(hash)
  
      const paymasterSignerAccount = privateKeyToAccount("0x574d33f5ba32008ca486410a245aabf52f30a16424222cf8092a8a5950bfbf3d");
      console.log("PAYMASTER SIGNER ACCOUNT")
      console.log(paymasterSignerAccount.address)
  
      // sign the hash
      const sig = await walletClient.signMessage({
        account: privateKeyToAccount("0x574d33f5ba32008ca486410a245aabf52f30a16424222cf8092a8a5950bfbf3d"),
        message: { raw: toBytes(hash as Hex) }
      })
      
      console.log(sig);
  
      // Send User Operation
      // @ts-ignore
      const userOpHash = await bundlerClient.sendUserOperation({ 
        ...userOp,
        paymasterData: encodePacked(
          ["bytes", "bytes"],
          [paymasterData, sig]
        ),
      });
  
      await bundlerClient.waitForUserOperationReceipt({ 
        hash: userOpHash,
      })
  
      // Check account balance not changed
      const postAccountBalance = await publicClient.getBalance({address: simpleAccount.address});
      equal(postAccountBalance, preAccountBalance);
  
      // Check counter value incremented
      const postCounter = await publicClient.call({
        to: COUNTER_ADDRESS,
        data: encodeFunctionData({
          abi: counterAbi,
          functionName: 'counters',
          args: [simpleAccount.address]
        })
      }).then((response) => fromHex(response.data, "number"));
  
      equal(postCounter, preCounterValue + 1);
    });
  })
});
