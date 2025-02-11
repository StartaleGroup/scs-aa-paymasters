// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {PackedUserOperation} from "@account-abstraction/contracts/core/UserOperationLib.sol";
import {ISponsorshipPaymasterEventsAndErrors} from "./ISponsorshipPaymasterEventsAndErrors.sol";

interface ISponsorshipPaymaster is ISponsorshipPaymasterEventsAndErrors {
    struct WithdrawalRequest {
        uint256 amount;
        address to;
        uint256 requestSubmittedTimestamp;
    }
    // function depositFor(address sponsorAccount) external payable;

    function depositForUser() external payable;

    // addSigner
    // removeSigner

    function setFeeCollector(address newFeeCollector) external payable;

    function setUnaccountedGas(uint256 value) external payable;

    // Todo: bring back functionality to be able to withdraw stuck eth and erc20 in the paymaster contract
    // function withdrawERC20(IERC20 token, address target, uint256 amount) external;

    // function withdrawEth(address payable recipient, uint256 amount) external payable;

    function getBalance(address sponsorAccount) external view returns (uint256 balance);

    function getHash(
        PackedUserOperation calldata userOp,
        address sponsorAccount,
        uint48 validUntil,
        uint48 validAfter,
        uint32 feeMarkup
    ) external view returns (bytes32);

    function parsePaymasterAndData(bytes calldata paymasterAndData)
        external
        pure
        returns (
            address sponsorAccount,
            uint48 validUntil,
            uint48 validAfter,
            uint32 feeMarkup,
            uint128 paymasterValidationGasLimit,
            uint128 paymasterPostOpGasLimit,
            bytes calldata signature
        );
}
