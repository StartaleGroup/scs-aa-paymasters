// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {BasePaymaster} from "@account-abstraction/v0_7/contracts/core/BasePaymaster.sol";
import {UserOperationLib, PackedUserOperation} from "@account-abstraction/v0_7/contracts/core/UserOperationLib.sol";
import {_packValidationData} from "@account-abstraction/v0_7/contracts/core/Helpers.sol";
import {IEntryPoint} from "@account-abstraction/v0_7/contracts/interfaces/IEntryPoint.sol";
import {MultiSigners} from "./MultiSigners.sol";

contract SponsorshipPaymaster is BasePaymaster, MultiSigners {
    using UserOperationLib for PackedUserOperation;

    uint256 private constant VALID_TIMESTAMP_OFFSET = PAYMASTER_DATA_OFFSET;

    uint256 private constant TIMESTAMP_DATA_LENGTH = 6;

    uint256 private constant SIGNATURE_OFFSET = VALID_TIMESTAMP_OFFSET + TIMESTAMP_DATA_LENGTH * 2;

    /// @notice The paymaster signature length is invalid.
    error PaymasterSignatureLengthInvalid();

    /// @dev Emitted when a user operation is sponsored by the paymaster.
    event UserOperationSponsored(
        bytes32 indexed userOpHash,
        /// @param The user that requested sponsorship.
        address indexed user
    );

    constructor(address _entryPoint, address[] memory _signers)
        BasePaymaster(IEntryPoint(_entryPoint))
        MultiSigners(_signers)
    {}

    /**
     * return the hash we're going to sign off-chain (and validate on-chain)
     * this method is called by the off-chain service, to sign the request.
     * it is called on-chain from the validatePaymasterUserOp, to validate the signature.
     * note that this signature covers all fields of the UserOperation, except the "paymasterAndData",
     * which will carry the signature itself.
     */
    function getHash(PackedUserOperation calldata userOp) public view returns (bytes32) {
        return keccak256(
            abi.encode(
                userOp.getSender(),
                userOp.nonce,
                keccak256(userOp.initCode),
                keccak256(userOp.callData),
                userOp.accountGasLimits,
                userOp.preVerificationGas,
                userOp.gasFees,
                block.chainid,
                address(this),
                // hashing over all paymaster fields besides signature
                keccak256(userOp.paymasterAndData[:SIGNATURE_OFFSET])
            )
        );
    }

    /**
     * @notice Internal helper to parse and validate the userOperation's paymasterAndData.
     * @param _userOp The userOperation.
     * @param _userOpHash The userOperation hash.
     * @return (context, validationData) The context and validation data to return to the EntryPoint.
     *
     * verify our external signer signed this request.
     * the "paymasterAndData" is expected to be the paymaster and a signature over the entire request params
     * paymasterAndData[:20] : address(this)
     * paymasterAndData[20:36] : paymaster validation gas
     * paymasterAndData[36:52] : paymaster post-op gas
     * paymasterAndData[52:64] : abi.packedEncode(validUntil, validAfter) - uint48 (6bytes length) for each
     * paymasterAndData[64:] : signature
     */
    function _validatePaymasterUserOp(PackedUserOperation calldata _userOp, bytes32 _userOpHash, uint256 /* maxCost */ )
        internal
        override
        returns (bytes memory, uint256)
    {
        (uint48 validUntil, uint48 validAfter, bytes calldata signature) =
            parsePaymasterAndData(_userOp.paymasterAndData);
        // ECDSA library supports both 64 and 65-byte long signatures.
        if (signature.length != 64 && signature.length != 65) {
            revert PaymasterSignatureLengthInvalid();
        }

        bytes32 hash = MessageHashUtils.toEthSignedMessageHash(getHash(_userOp));
        address recoveredSigner = ECDSA.recover(hash, signature);

        // Don't revert even if signature is invalid.
        bool isSignatureValid = signers[recoveredSigner];
        uint256 validationData = _packValidationData(!isSignatureValid, validUntil, validAfter);

        emit UserOperationSponsored(_userOpHash, _userOp.getSender());
        return ("", validationData);
    }

    function parsePaymasterAndData(bytes calldata paymasterAndData)
        public
        pure
        returns (uint48 validUntil, uint48 validAfter, bytes calldata signature)
    {
        validUntil =
            uint48(bytes6(paymasterAndData[VALID_TIMESTAMP_OFFSET:VALID_TIMESTAMP_OFFSET + TIMESTAMP_DATA_LENGTH]));
        validAfter = uint48(bytes6(paymasterAndData[VALID_TIMESTAMP_OFFSET + TIMESTAMP_DATA_LENGTH:SIGNATURE_OFFSET]));
        signature = paymasterAndData[SIGNATURE_OFFSET:];
    }
}
