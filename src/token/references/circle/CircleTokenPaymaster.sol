/*
 * Copyright 2024 Circle Internet Group, Inc. All rights reserved.

 * SPDX-License-Identifier: GPL-3.0-or-later

 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.

 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.

 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */
pragma solidity ^0.8.24;

import {IEntryPoint, CircleBasePaymaster} from "./CircleBasePaymaster.sol";
import {IWETH} from "@uniswap/swap-router-contracts/contracts/interfaces/IWETH.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {FeeLibV1} from "./FeeLibV1.sol";
import {CirclePriceOracleHelper, IOracle} from "./CirclePriceOracleHelper.sol";
import {ISwapRouter} from "./ISwapRouter.sol";
import {IPermit} from "./IPermit.sol";
import {Denylistable} from "./Denylistable.sol";
import {Rescuable} from "./Rescuable.sol";
import {PackedUserOperation} from "@account-abstraction/contracts/interfaces/PackedUserOperation.sol";
import {UserOperationLib} from "@account-abstraction/contracts/core/UserOperationLib.sol";

uint256 constant PAYMASTER_TOKEN_ADDRESS_OFFSET = UserOperationLib.PAYMASTER_DATA_OFFSET + 1; // reserve a 1 byte gap for future use
uint256 constant PAYMASTER_PERMIT_AMOUNT_OFFSET = PAYMASTER_TOKEN_ADDRESS_OFFSET + 20;
uint256 constant PAYMASTER_PERMIT_SIGNATURE_OFFSET = PAYMASTER_PERMIT_AMOUNT_OFFSET + 32;

/**
 * @notice A token paymaster that allows compatible SCAs to pay for gas using ERC-20 tokens.
 */
contract CircleTokenPaymaster is CircleBasePaymaster, CirclePriceOracleHelper, Denylistable, Rescuable {
    using SafeERC20 for IERC20;
    using UserOperationLib for PackedUserOperation;

    /**
     * @notice The ERC20 token this paymaster accepts as payment. This token should also support permit.
     */
    IERC20 public immutable token;

    /**
     * @notice The native token wrapper used by the swap router.
     */
    IWETH public immutable wrappedNativeToken;

    /**
     * @notice Additional gas to charge per UserOp (based on gas of postOp).
     */
    uint256 public additionalGasCharge;

    /**
     * @notice Address of the privileged pauser role.
     */
    address public pauser;

    /**
     * @notice Address of the privileged swapper role.
     */
    address public swapper;

    /**
     * @notice The contract to execute swaps against.
     */
    ISwapRouter public swapRouter;

    /**
     * @notice Emitted when a UserOp is succesfully sponsored.
     * @param token the token paid by the sender.
     * @param sender the sender address.
     * @param userOpHash the hash of the UserOp.
     * @param nativeTokenPrice The price of 1 ether = 1e18 wei, denominated in token.
     * @param actualTokenNeeded the final transaction cost to the SCA, denominated in token.
     */
    event UserOperationSponsored(
        IERC20 indexed token,
        address indexed sender,
        bytes32 userOpHash,
        uint256 nativeTokenPrice,
        uint256 actualTokenNeeded
    );
    /**
     * @notice Emitted when the pauser has been changed.
     * @param oldPauser the old pauser.
     * @param newPauser the new pauser.
     */
    event PauserChanged(address indexed oldPauser, address indexed newPauser);

    /**
     * @notice Emitted when the swapper has been changed.
     * @param oldSwapper the old swapper.
     * @param newSwapper the new swapper.
     */
    event SwapperChanged(address indexed oldSwapper, address indexed newSwapper);

    /**
     * @notice Emitted when token has been swapped for native token.
     * @param token the input token.
     * @param amountIn the amount of token sent.
     * @param amountOut the amount of native token received.
     */
    event TokenSwappedForNative(IERC20 indexed token, uint256 amountIn, uint256 amountOut);

    /**
     * @notice Emitted when the swap router contract has been changed.
     * @param oldSwapRouter the old swap router.
     * @param newSwapRouter the new swap router.
     */
    event SwapRouterChanged(ISwapRouter oldSwapRouter, ISwapRouter newSwapRouter);

    /**
     * @notice Emitted when the additional gas charge has been changed.
     * @param oldAdditionalGasCharge the old additional gas charge.
     * @param newAdditionalGasCharge the new additional gas charge.
     */
    event AdditionalGasChargeChanged(uint256 oldAdditionalGasCharge, uint256 newAdditionalGasCharge);

    /**
     * @notice Reverts when the pauser is expected, but an unauthorized caller is used.
     * @param account the unauthorized caller.
     */
    error UnauthorizedPauser(address account);

    /**
     * @notice Reverts when the swapper is expected, but an unauthorized caller is used.
     * @param account the unauthorized caller.
     */
    error UnauthorizedSwapper(address account);

    /**
     * @notice Reverts when the slippage is set too high.
     * @param bips the unsupported slippage bips.
     */
    error InvalidSlippageBips(uint256 bips);

    /**
     * @notice Reverts when the paymasterAndData specifies an unsupported token.
     * @param token the unsupported token.
     */
    error UnsupportedToken(address token);

    /**
     * @notice Reverts when the paymasterAndData is malformed.
     */
    error MalformedPaymasterData();

    /**
     * @notice Reverts when the UserOp does not specify enough gas to execute the postOp
     * @param actual the given postOpGasLimit.
     * @param expected the minimum postOpGasLimit expected.
     */
    error PostOpGasLimitTooLow(uint256 actual, uint256 expected);

    /**
     * @notice Reverts if an invalid address is set.
     */
    error InvalidAddress();

    modifier onlyPauser() {
        if (pauser != _msgSender()) {
            revert UnauthorizedPauser(_msgSender());
        }
        _;
    }

    modifier onlySwapper() {
        if (swapper != _msgSender()) {
            revert UnauthorizedSwapper(_msgSender());
        }
        _;
    }

    function _authorizeUpdateDenylister() internal virtual override onlyOwner {}

    function _authorizeUpdateRescuer() internal virtual override onlyOwner {}

    function _authorizeUpdateOracle() internal virtual override onlyOwner {}

    function _authorizeUserOpSender(address sender) internal virtual notDenylisted(sender) {}

    function _checkNotZeroAddress(address addr) internal virtual {
        if (addr == address(0)) {
            revert InvalidAddress();
        }
    }

    // for immutable values in implementations
    constructor(IEntryPoint _newEntryPoint, IERC20Metadata _token, IWETH _wrappedNativeToken)
        CircleBasePaymaster(_newEntryPoint)
        CirclePriceOracleHelper(_token.decimals())
    {
        token = IERC20(_token);
        wrappedNativeToken = _wrappedNativeToken;
        // lock the implementation contract so it can only be called from proxies
        _disableInitializers();
    }

    function initialize(address _owner, uint256 _additionalGasCharge, IOracle _oracle, ISwapRouter _swapRouter)
        public
        reinitializer(2)
    {
        __BasePaymaster_init(_owner);
        __PriceOracleHelper_init(_oracle);
        additionalGasCharge = _additionalGasCharge;
        pauser = _owner;
        swapper = _owner;
        denylister = _owner;
        rescuer = _owner;
        swapRouter = _swapRouter;
    }

    /**
     * @dev Implementation of validatePaymasterUserOp that attempts to withdraw the equivalent gas fees priced in token from the sender.
     * Supports using permit to increase the sender's token allowance with the paymaster without having to call approve.
     */
    function _validatePaymasterUserOp(PackedUserOperation calldata userOp, bytes32 userOpHash, uint256 maxCost)
        internal
        virtual
        override
        returns (bytes memory context, uint256 validationData)
    {
        address sender = userOp.getSender();
        _authorizeUserOpSender(sender);

        uint256 postOpGasLimit = userOp.unpackPostOpGasLimit();
        if (postOpGasLimit < additionalGasCharge) {
            revert PostOpGasLimitTooLow(postOpGasLimit, additionalGasCharge);
        }

        if (userOp.paymasterAndData.length > PAYMASTER_TOKEN_ADDRESS_OFFSET) {
            if (userOp.paymasterAndData.length < PAYMASTER_PERMIT_SIGNATURE_OFFSET) {
                revert MalformedPaymasterData();
            }
            (address tokenAddress, uint256 permitAmount, bytes calldata permitSignature) =
                parsePermitData(userOp.paymasterAndData);

            if (tokenAddress != address(token)) {
                revert UnsupportedToken(tokenAddress);
            }

            IPermit permitToken = IPermit(tokenAddress);
            try permitToken.permit(sender, address(this), permitAmount, type(uint256).max, permitSignature) {
                // continue as normal
            } catch (bytes memory) /* reason */ {
                // Because the permitSignature enters a mempool, it may be frontrun.
                // Instead, we allow failed permits to continue expecting the permit was already run.
            }
        }

        uint256 nativeTokenPrice = fetchPrice();
        uint256 prefundTokenAmount =
            FeeLibV1.calculateUserCharge(nativeTokenPrice, additionalGasCharge, userOp.unpackMaxFeePerGas(), maxCost);
        token.safeTransferFrom(sender, address(this), prefundTokenAmount);

        // Save some state to help calculate the expected penalty during postOp
        uint256 preOpGasApproximation = userOp.preVerificationGas + userOp.unpackVerificationGasLimit()
            + userOp.unpackPaymasterVerificationGasLimit();
        uint256 executionGasLimit = userOp.unpackCallGasLimit() + userOp.unpackPostOpGasLimit();

        // returns context as needed.
        context = abi.encode(
            sender, prefundTokenAmount, nativeTokenPrice, preOpGasApproximation, executionGasLimit, userOpHash
        );
        // zero to indicate validation was a success.
        validationData = 0;
    }

    /**
     * @dev Implementation of postOp that refunds the sender of any token originally received in excess of the actual amount needed.
     */
    function _postOp(PostOpMode mode, bytes calldata context, uint256 actualGasCost, uint256 actualUserOpFeePerGas)
        internal
        virtual
        override
    {
        // unused
        (mode);

        (
            address sender,
            uint256 prefundTokenAmount,
            uint256 nativeTokenPrice,
            uint256 preOpGasApproximation,
            uint256 executionGasLimit,
            bytes32 userOpHash
        ) = abi.decode(context, (address, uint256, uint256, uint256, uint256, bytes32));

        uint256 actualGas = actualGasCost / actualUserOpFeePerGas;

        uint256 executionGasUsed;
        if (actualGas + additionalGasCharge > preOpGasApproximation) {
            executionGasUsed = actualGas + additionalGasCharge - preOpGasApproximation;
        }

        uint256 expectedPenaltyGas;
        if (executionGasLimit > executionGasUsed) {
            expectedPenaltyGas = (executionGasLimit - executionGasUsed) * 10 / 100;
        }

        uint256 actualTokenNeeded = FeeLibV1.calculateUserCharge(
            nativeTokenPrice, additionalGasCharge + expectedPenaltyGas, actualUserOpFeePerGas, actualGasCost
        );

        // Remainder is refunded to user SCA
        if (prefundTokenAmount > actualTokenNeeded) {
            token.safeTransfer(sender, prefundTokenAmount - actualTokenNeeded);
        }

        emit UserOperationSponsored(token, sender, userOpHash, nativeTokenPrice, actualTokenNeeded);
    }

    /**
     * @notice A helper function for parsing permit data from paymasterAndData.
     */
    function parsePermitData(bytes calldata paymasterAndData)
        public
        pure
        returns (address tokenAddress, uint256 permitAmount, bytes calldata permitSignature)
    {
        return (
            address(bytes20(paymasterAndData[PAYMASTER_TOKEN_ADDRESS_OFFSET:PAYMASTER_PERMIT_AMOUNT_OFFSET])),
            uint256(bytes32(paymasterAndData[PAYMASTER_PERMIT_AMOUNT_OFFSET:PAYMASTER_PERMIT_SIGNATURE_OFFSET])),
            paymasterAndData[PAYMASTER_PERMIT_SIGNATURE_OFFSET:]
        );
    }

    /**
     * @notice triggers paused state that prevents usage of the paymaster.
     */
    function pause() public onlyPauser whenNotPaused {
        _pause();
    }

    /**
     * @notice resumes usability of the paymaster after being paused.
     */
    function unpause() public onlyPauser whenPaused {
        _unpause();
    }

    /**
     * @notice Swaps token for native token and deposits the received amount into the EntryPoint contract.
     * Only callable by the swapper role.
     * @param amountIn the amount of token to swap.
     * @param slippageBips the amount of acceptable slippage, in basis points (e.g 1 bip = 0.01%).
     * @param poolFee the pool fee to use for swaps, in hundredths of a basis point.
     */
    function swapForNative(uint256 amountIn, uint256 slippageBips, uint24 poolFee)
        external
        onlySwapper
        returns (uint256 amountOut)
    {
        if (slippageBips > FeeLibV1.BIPS_DENOMINATOR) {
            revert InvalidSlippageBips(slippageBips);
        }
        uint256 nativePrice = fetchPrice();
        uint256 amountOutMinimum = FeeLibV1.calculateNativeAmountOut(amountIn, slippageBips, nativePrice);

        token.safeIncreaseAllowance(address(swapRouter), amountIn);
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: address(token),
            tokenOut: address(wrappedNativeToken),
            fee: poolFee,
            recipient: address(this),
            amountIn: amountIn,
            amountOutMinimum: amountOutMinimum,
            sqrtPriceLimitX96: 0
        });

        amountOut = swapRouter.exactInputSingle(params);
        emit TokenSwappedForNative(token, amountIn, amountOut);

        wrappedNativeToken.withdraw(amountOut);
        entryPoint.depositTo{value: amountOut}(address(this));
    }

    /**
     * @notice Updates the privileged pauser address.
     * Only callable by the owner.
     * @param newPauser the new pauser address.
     */
    function updatePauser(address newPauser) external onlyOwner {
        _checkNotZeroAddress(newPauser);

        address oldPauser = pauser;
        pauser = newPauser;
        emit PauserChanged(oldPauser, newPauser);
    }

    /**
     * @notice Updates the privileged swapper address.
     * Only callable by the owner.
     * @param newSwapper the new swapper address.
     */
    function updateSwapper(address newSwapper) external onlyOwner {
        _checkNotZeroAddress(newSwapper);

        address oldSwapper = swapper;
        swapper = newSwapper;
        emit SwapperChanged(oldSwapper, newSwapper);
    }

    /**
     * @notice Updates the swap router contract.
     * Only callable by the owner.
     * @param newSwapRouter the new swap router contract.
     */
    function updateSwapRouter(ISwapRouter newSwapRouter) external onlyOwner {
        _checkNotZeroAddress(address(newSwapRouter));

        ISwapRouter oldSwapRouter = swapRouter;
        swapRouter = newSwapRouter;
        emit SwapRouterChanged(oldSwapRouter, newSwapRouter);
    }

    /**
     * @notice Updates the additional gas charge.
     * Only callable by the owner.
     * @param newAdditionalGasCharge the new additional gas charge.
     */
    function updateAdditionalGasCharge(uint256 newAdditionalGasCharge) external onlyOwner {
        uint256 oldAdditionalGasCharge = additionalGasCharge;
        additionalGasCharge = newAdditionalGasCharge;
        emit AdditionalGasChargeChanged(oldAdditionalGasCharge, newAdditionalGasCharge);
    }

    /**
     * @notice Implement receive function to allow WETH to be unwrapped to this contract.
     */
    receive() external payable {}
}
