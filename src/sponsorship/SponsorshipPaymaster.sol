// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {BasePaymaster} from "../base/BasePaymaster.sol";
import {UserOperationLib, PackedUserOperation} from "@account-abstraction/contracts/core/UserOperationLib.sol";
import {_packValidationData} from "@account-abstraction/contracts/core/Helpers.sol";
import {IEntryPoint} from "@account-abstraction/contracts/interfaces/IEntryPoint.sol";
import {MultiSigners} from "./MultiSigners.sol";

contract SponsorshipPaymaster is BasePaymaster, MultiSigners {
    using UserOperationLib for PackedUserOperation;

    uint256 private constant FUNDING_ID_OFFSET = PAYMASTER_DATA_OFFSET;

    uint256 private constant FUNDING_ID_LENGTH = 20;

    uint256 private constant VALID_UNTIL_TIMESTAMP_OFFSET = FUNDING_ID_OFFSET + FUNDING_ID_LENGTH;

    uint256 private constant TIMESTAMP_DATA_LENGTH = 6;

    uint256 private constant VALID_AFTER_TIMESTAMP_OFFSET = VALID_UNTIL_TIMESTAMP_OFFSET + TIMESTAMP_DATA_LENGTH;

    uint256 private constant DYNAMIC_ADJUSTMENT_OFFSET = VALID_AFTER_TIMESTAMP_OFFSET + TIMESTAMP_DATA_LENGTH;

    uint256 private constant DYNAMIC_ADJUSTMENT_LENGTH = 4;

    uint256 private constant SIGNATURE_OFFSET = DYNAMIC_ADJUSTMENT_OFFSET + DYNAMIC_ADJUSTMENT_LENGTH;

    /// @notice The paymaster signature length is invalid.
    error PaymasterSignatureLengthInvalid();

    /// @dev Emitted when a user operation is sponsored by the paymaster.
    event UserOperationSponsored(
        bytes32 indexed userOpHash,
        /// @param The user that requested sponsorship.
        address indexed user
    );

    constructor(address _owner, address _entryPoint, address[] memory _signers)
        BasePaymaster(_owner, IEntryPoint(_entryPoint))
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
                uint256(bytes32(userOp.paymasterAndData[PAYMASTER_VALIDATION_GAS_OFFSET:PAYMASTER_DATA_OFFSET])),
                userOp.preVerificationGas,
                userOp.gasFees,
                block.chainid,
                address(this),
                userOp.paymasterAndData[PAYMASTER_DATA_OFFSET:SIGNATURE_OFFSET]
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
     * paymasterAndData[52:72] : fundingId
     * paymasterAndData[72:84] : abi.packedEncode(validUntil, validAfter) - uint48 (6bytes length) for each
     * paymasterAndData[84:88] : dynamicAdjustment
     * paymasterAndData[88:] : signature
     */
    function _validatePaymasterUserOp(PackedUserOperation calldata _userOp, bytes32 _userOpHash, uint256 /* maxCost */ )
        internal
        override
        returns (bytes memory, uint256)
    {
        (address _fundingId, uint48 validUntil, uint48 validAfter, uint32 _dynamicAdjustment, bytes calldata signature)
        = parsePaymasterAndData(_userOp.paymasterAndData);
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

    function parsePaymasterAndData(bytes calldata _paymasterAndData)
        public
        pure
        returns (
            address fundingId,
            uint48 validUntil,
            uint48 validAfter,
            uint32 dynamicAdjustment,
            bytes calldata signature
        )
    {
        fundingId = address(bytes20(_paymasterAndData[FUNDING_ID_OFFSET:VALID_UNTIL_TIMESTAMP_OFFSET]));
        validUntil = uint48(bytes6(_paymasterAndData[VALID_UNTIL_TIMESTAMP_OFFSET:VALID_AFTER_TIMESTAMP_OFFSET]));
        validAfter = uint48(bytes6(_paymasterAndData[VALID_AFTER_TIMESTAMP_OFFSET:DYNAMIC_ADJUSTMENT_OFFSET]));
        dynamicAdjustment = uint32(bytes4(_paymasterAndData[DYNAMIC_ADJUSTMENT_OFFSET:SIGNATURE_OFFSET]));
        signature = _paymasterAndData[SIGNATURE_OFFSET:];
    }
}
