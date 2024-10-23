// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { MessageHashUtils } from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import { BasePaymaster } from "@account-abstraction/v0_7/contracts/core/BasePaymaster.sol";
import { UserOperationLib, PackedUserOperation } from "@account-abstraction/v0_7/contracts/core/UserOperationLib.sol";
import { _packValidationData } from "@account-abstraction/v0_7/contracts/core/Helpers.sol";
import { IEntryPoint } from "@account-abstraction/v0_7/contracts/interfaces/IEntryPoint.sol";
import { MultiSigners } from "./MultiSigners.sol";

contract VerifyingPaymaster is BasePaymaster, MultiSigners {

    using UserOperationLib for PackedUserOperation;

    uint256 private constant VALID_TIMESTAMP_OFFSET = PAYMASTER_DATA_OFFSET;
    uint256 private constant SIGNATURE_OFFSET = VALID_TIMESTAMP_OFFSET + 64;

    /// @notice The paymaster signature length is invalid.
    error PaymasterSignatureLengthInvalid();

    /// @dev Emitted when a user operation is sponsored by the paymaster.
    event UserOperationSponsored(
        bytes32 indexed userOpHash,
        /// @param The user that requested sponsorship.
        address indexed user
    );

    constructor(IEntryPoint _entryPoint, address _owner, address[] memory _verifyingSigners)
        BasePaymaster(_entryPoint)
        MultiSigners(_verifyingSigners)
    {}

    /**
     * @notice Internal helper to parse and validate the userOperation's paymasterAndData.
     * @param _userOp The userOperation.
     * @param _userOpHash The userOperation hash.
     * @return (context, validationData) The context and validation data to return to the EntryPoint.
     *
     * verify our external signer signed this request.
     * the "paymasterAndData" is expected to be the paymaster and a signature over the entire request params
     * paymasterAndData[:20] : address(this)
     * paymasterAndData[20:84] : abi.encode(validUntil, validAfter)
     * paymasterAndData[84:] : signature
     */
    function _validatePaymasterUserOp(PackedUserOperation calldata _userOp, bytes32 _userOpHash, uint256 /* maxCost */ )
        internal override
        returns (bytes memory, uint256)
    {
        (uint48 validUntil, uint48 validAfter, bytes calldata signature) = _parsePaymasterAndData(_userOp.paymasterAndData);
        // ECDSA library supports both 64 and 65-byte long signatures.
        if (signature.length != 64 && signature.length != 65) {
            revert PaymasterSignatureLengthInvalid();
        }

        bytes32 hash = MessageHashUtils.toEthSignedMessageHash(getHash(_userOp, validUntil, validAfter));
        address recoveredSigner = ECDSA.recover(hash, signature);

        // Don't revert even if signature is invalid.
        bool isSignatureValid = signers[recoveredSigner];
        uint256 validationData = _packValidationData(!isSignatureValid, validUntil, validAfter);

        emit UserOperationSponsored(_userOpHash, _userOp.getSender());
        return ("", validationData);
    }

    function _parsePaymasterAndData(bytes calldata _paymasterAndData) public pure returns (uint48 validUntil, uint48 validAfter, bytes calldata signature) {
        (validUntil, validAfter) = abi.decode(_paymasterAndData[VALID_TIMESTAMP_OFFSET :], (uint48, uint48));
        signature = _paymasterAndData[SIGNATURE_OFFSET :];
    }

    /**
     * return the hash we're going to sign off-chain (and validate on-chain)
     * this method is called by the off-chain service, to sign the request.
     * it is called on-chain from the validatePaymasterUserOp, to validate the signature.
     * note that this signature covers all fields of the UserOperation, except the "paymasterAndData",
     * which will carry the signature itself.
     */
    function getHash(PackedUserOperation calldata userOp, uint48 validUntil, uint48 validAfter)
    public view returns (bytes32) {
        // can't use userOp.hash(), since it contains also the paymasterAndData itself.
        address sender = userOp.getSender();
        return
            // TODO: Decide what to hash.
            keccak256(
                abi.encode(
                    sender,
                    userOp.nonce,
                    keccak256(userOp.initCode),
                    keccak256(userOp.callData),
                    userOp.accountGasLimits,
                    uint256(bytes32(userOp.paymasterAndData[PAYMASTER_VALIDATION_GAS_OFFSET : PAYMASTER_DATA_OFFSET])),
                    userOp.preVerificationGas,
                    userOp.gasFees,
                    block.chainid,
                    address(this),
                    validUntil,
                    validAfter
                )
            );
    }
}
