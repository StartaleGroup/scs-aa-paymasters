// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IStartaleTokenPaymaster} from "../interfaces/IStartaleTokenPaymaster.sol";
import {UserOperationLib, PackedUserOperation} from "@account-abstraction/contracts/core/UserOperationLib.sol";

library TokenPaymasterParserLib {
    // Start offset of mode in PND
    uint256 private constant PAYMASTER_MODE_OFFSET = UserOperationLib.PAYMASTER_DATA_OFFSET;

    function parsePaymasterAndData(bytes calldata _paymasterAndData)
        internal
        pure
        returns (IStartaleTokenPaymaster.PaymasterMode mode, bytes calldata modeSpecificData)
    {
        unchecked {
            mode = IStartaleTokenPaymaster.PaymasterMode(uint8(bytes1(_paymasterAndData[PAYMASTER_MODE_OFFSET])));
            modeSpecificData = _paymasterAndData[PAYMASTER_MODE_OFFSET + 1:];
        }
    }

    function parseIndependentModeSpecificData(bytes calldata modeSpecificData)
        internal
        pure
        returns (address tokenAddress)
    {
        tokenAddress = address(bytes20(modeSpecificData[:20]));
    }

    function parseExternalModeSpecificData(bytes calldata modeSpecificData)
        internal
        pure
        returns (
            uint48 validUntil,
            uint48 validAfter,
            address tokenAddress,
            uint256 exchangeRate,
            uint48 appliedFeeMarkup,
            bytes calldata signature
        )
    {
        validUntil = uint48(bytes6(modeSpecificData[:6]));
        validAfter = uint48(bytes6(modeSpecificData[6:12]));
        tokenAddress = address(bytes20(modeSpecificData[12:32]));
        exchangeRate = uint256(bytes32(modeSpecificData[32:64]));
        appliedFeeMarkup = uint48(bytes6(modeSpecificData[64:70]));
        signature = modeSpecificData[70:];
    }
}
