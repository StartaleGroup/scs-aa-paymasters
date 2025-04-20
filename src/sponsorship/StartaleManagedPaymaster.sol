// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SignatureCheckerLib} from "solady/utils/SignatureCheckerLib.sol";
import {ECDSA as ECDSA_solady} from "solady/utils/ECDSA.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {BasePaymaster} from "../base/BasePaymaster.sol";
import {UserOperationLib, PackedUserOperation} from "@account-abstraction/contracts/core/UserOperationLib.sol";
import {_packValidationData} from "@account-abstraction/contracts/core/Helpers.sol";
import {IEntryPoint} from "@account-abstraction/contracts/interfaces/IEntryPoint.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MultiSigners} from "../lib/MultiSigners.sol";
import {IStartaleManagedPaymaster} from "../interfaces/IStartaleManagedPaymaster.sol";

/**
 * @title StartaleManagedPaymaster
 * @notice Paymaster contract that enables transaction sponsorship for account abstraction
 * @dev uses external service to decide whether to pay for the UserOp.
 * @dev The paymaster trusts an external signers to sign the transaction.
 * @notice Accounting is done off-chain and billed to the projects in a post-paid manner. Off-chain service should only sign if billing is setup using credit card.
 * @notice Startale is responsible for deposting gas on the paymaster contract.
 */
contract StartaleManagedPaymaster is
    BasePaymaster,
    MultiSigners,
    ReentrancyGuardTransient,
    IStartaleManagedPaymaster
{
    using UserOperationLib for PackedUserOperation;
    using SignatureCheckerLib for address;
    using ECDSA_solady for bytes32;

    // paymasterData part of userOp.paymasterAndData starts here
    // userOp.paymasterAndData is paymaster address(20 bytes) + paymaster validation gas limit(16 bytes) + paymaster post-op gas limit(16 bytes) + paymasterData
    // where + means concat

    uint256 private constant VALID_TIMESTAMP_OFFSET = PAYMASTER_DATA_OFFSET; // 52

    uint256 private constant SIGNATURE_OFFSET = VALID_TIMESTAMP_OFFSET + 64; //52 + 12

    // paymasterData validUntil(6 bytes) + validAfter(6 bytes) + signature

    event UserOperationSponsored(bytes32 indexed userOpHash, address indexed user);

    /**
     * @notice Initializes the SponsorshipPaymaster contract
     * @param _owner The owner of the paymaster
     * @param _entryPoint The ERC-4337 EntryPoint contract address
     * @param _signers Array of authorized signers for paymaster validation
     */
    constructor(address _owner, address _entryPoint, address[] memory _signers)
        BasePaymaster(_owner, IEntryPoint(_entryPoint))
        MultiSigners(_signers)
    {}

    /**
     * @notice Receives ETH payments
     * @dev Silent receive function (no events to save gas)
     */
    receive() external payable {
        // do nothing
        // unnecessary to emit that consume gas
    }

    /**
     * @notice Adds a new signer to the list of authorized signers
     * @param _signer The address of the signer to add
     */
    function addSigner(address _signer) external payable onlyOwner {
        _addSigner(_signer);
    }

    /**
     * @notice Removes a signer from the list of authorized signers
     * @param _signer The address of the signer to remove
     */
    function removeSigner(address _signer) external payable onlyOwner {
        _removeSigner(_signer);
    }

    /**
     * @notice Withdraws ETH from the paymaster
     * @param _recipient The recipient address
     * @param _amount The amount of ETH to withdraw
     */
    function withdrawEth(address payable _recipient, uint256 _amount) external payable onlyOwner nonReentrant {
        if (_recipient == address(0)) {
            revert InvalidWithdrawalAddress();
        }
        (bool success,) = _recipient.call{value: _amount}("");
        if (!success) {
            revert WithdrawalFailed();
        }
        emit EthWithdrawn(_recipient, _amount);
    }

    /**
     * @notice Withdraws ERC20 tokens from the paymaster
     * @param _token The token contract to withdraw from
     * @param _target The recipient address
     * @param _amount The amount to withdraw
     */
    function withdrawERC20(IERC20 _token, address _target, uint256 _amount) external onlyOwner nonReentrant {
        _withdrawERC20(_token, _target, _amount);
    }

    /**
     * return the hash we're going to sign off-chain (and validate on-chain)
     * this method is called by the off-chain service, to sign the request.
     * it is called on-chain from the validatePaymasterUserOp, to validate the signature.
     * note that this signature covers all fields of the UserOperation, except the "paymasterAndData",
     * which will carry the signature itself.
     */
    function getHash(PackedUserOperation calldata userOp, uint48 validUntil, uint48 validAfter)
        public
        view
        returns (bytes32)
    {
        //can't use userOp.hash(), since it contains also the paymasterAndData itself.
        address sender = userOp.getSender();
        return keccak256(
            abi.encode(
                sender,
                userOp.nonce,
                keccak256(userOp.initCode),
                keccak256(userOp.callData),
                userOp.accountGasLimits,
                uint256(bytes32(userOp.paymasterAndData[PAYMASTER_VALIDATION_GAS_OFFSET:PAYMASTER_DATA_OFFSET])),
                userOp.preVerificationGas,
                userOp.gasFees,
                block.chainid,
                address(this),
                validUntil,
                validAfter
            )
        );
    }

    /**
     * @notice Validates the UserOperation and deducts the required gas sponsorship amount
     * @param _userOp The UserOperation being validated
     * @return Encoded context for post-operation handling and validationData for EntryPoint
     */
    function _validatePaymasterUserOp(
        PackedUserOperation calldata _userOp,
        bytes32 userOpHash,
        uint256 /*_requiredPreFund*/
    ) internal override returns (bytes memory, uint256) {
        (uint48 validUntil, uint48 validAfter, bytes calldata signature) =
            parsePaymasterAndData(_userOp.paymasterAndData);

        if (signature.length != 64 && signature.length != 65) {
            revert PaymasterSignatureLengthInvalid();
        }

        address recoveredSigner =
            ((getHash(_userOp, validUntil, validAfter).toEthSignedMessageHash()).tryRecover(signature));

        if (recoveredSigner == address(0)) {
            revert PotentiallyMalformedSignature();
        }

        bool isValidSig = signers[recoveredSigner];

        // Review: If we need to emit additional details
        // We could potentially get project specific details  from the paymasterAndData
        emit UserOperationSponsored(userOpHash, _userOp.getSender());

        return ("", _packValidationData(!isValidSig, validUntil, validAfter));
    }

    function parsePaymasterAndData(bytes calldata paymasterAndData)
        public
        pure
        returns (uint48 validUntil, uint48 validAfter, bytes calldata signature)
    {
        (validUntil, validAfter) = abi.decode(paymasterAndData[VALID_TIMESTAMP_OFFSET:], (uint48, uint48));
        signature = paymasterAndData[SIGNATURE_OFFSET:];
    }

    /**
     * @notice Internal function to withdraw ERC20 tokens
     * @param _token The token to withdraw
     * @param _target The address to send tokens to
     * @param _amount The amount to withdraw
     */
    function _withdrawERC20(IERC20 _token, address _target, uint256 _amount) private {
        if (_target == address(0)) revert InvalidWithdrawalAddress();
        SafeTransferLib.safeTransfer(address(_token), _target, _amount);
        emit TokensWithdrawn(address(_token), _target, msg.sender, _amount);
    }
}
