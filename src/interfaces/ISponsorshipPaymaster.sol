// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {PackedUserOperation} from "@account-abstraction/contracts/core/UserOperationLib.sol";
import {ISponsorshipPaymasterEventsAndErrors} from "./ISponsorshipPaymasterEventsAndErrors.sol";

interface ISponsorshipPaymaster is ISponsorshipPaymasterEventsAndErrors {
    // function depositFor(address fundingId) external payable;
    function depositForUser() external payable;

    // Review: Note previously this was done by addSigner of MultiSigner
    // function setSigner(address newVerifyingSigner) external payable;

    function setFeeCollector(address newFeeCollector) external payable;

    function setUnaccountedGas(uint256 value) external payable;

    // Todo: bring back functionality to be able to withdraw stuck eth and erc20 in the paymaster contract
    // function withdrawERC20(IERC20 token, address target, uint256 amount) external;

    // function withdrawEth(address payable recipient, uint256 amount) external payable;

    function getBalance(address fundingId) external view returns (uint256 balance);

    function getHash(
        PackedUserOperation calldata userOp,
        address fundingId,
        uint48 validUntil,
        uint48 validAfter,
        uint32 priceMarkup
    ) external view returns (bytes32);

    function parsePaymasterAndData(bytes calldata paymasterAndData)
        external
        pure
        returns (
            address fundingId,
            uint48 validUntil,
            uint48 validAfter,
            uint32 priceMarkup,
            uint128 paymasterValidationGasLimit,
            uint128 paymasterPostOpGasLimit,
            bytes calldata signature
        );
}
