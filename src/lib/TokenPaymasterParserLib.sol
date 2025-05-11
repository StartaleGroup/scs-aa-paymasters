// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {IStartaleTokenPaymaster} from "../interfaces/IStartaleTokenPaymaster.sol";
import {UserOperationLib, PackedUserOperation} from "@account-abstraction/contracts/core/UserOperationLib.sol";

/**
 * @title TokenPaymasterParserLib
 * @notice Library for parsing paymaster data in token-based paymasters
 * @dev Provides utility functions to decode binary paymaster data
 */
library TokenPaymasterParserLib {
    // Constants
    /// @dev Start offset of mode in paymaster and data
    uint256 private constant PAYMASTER_MODE_OFFSET = UserOperationLib.PAYMASTER_DATA_OFFSET;

    error InvalidPaymasterData();

    /**
     * @notice Parses the paymaster mode and specific data from paymasterAndData
     * @param _paymasterAndData The packed paymaster data from the UserOperation
     * @return mode The paymaster mode (Independent or External)
     * @return modeSpecificData The remaining data specific to the mode
     */
    function parsePaymasterAndData(bytes calldata _paymasterAndData)
        internal
        pure
        returns (IStartaleTokenPaymaster.PaymasterMode mode, bytes calldata modeSpecificData)
    {
        if (_paymasterAndData.length < PAYMASTER_MODE_OFFSET + 1) {
            revert InvalidPaymasterData();
        }
        unchecked {
            mode = IStartaleTokenPaymaster.PaymasterMode(uint8(bytes1(_paymasterAndData[PAYMASTER_MODE_OFFSET])));
            modeSpecificData = _paymasterAndData[PAYMASTER_MODE_OFFSET + 1:];
        }
    }

    /**
     * @notice Parses data specific to Independent mode
     * @param modeSpecificData The mode-specific portion of paymaster data
     * @return tokenAddress The address of the token being used for the gas payment
     */
    function parseIndependentModeSpecificData(bytes calldata modeSpecificData)
        internal
        pure
        returns (address tokenAddress)
    {
        if (modeSpecificData.length < 20) {
            revert InvalidPaymasterData();
        }
        tokenAddress = address(bytes20(modeSpecificData[:20]));
    }

    /**
     * @notice Parses data specific to External mode
     * @param modeSpecificData The mode-specific portion of paymaster data
     * @return validUntil Timestamp until which the signed data is valid
     * @return validAfter Timestamp after which the signed data is valid
     * @return tokenAddress The address of the token being used for the gas payment
     * @return exchangeRate The exchange rate between the token and native currency
     * @return appliedFeeMarkup The markup percentage applied to the gas fee
     * @return signature The signature validating this paymaster data
     */
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
        if (modeSpecificData.length < 70) {
            revert InvalidPaymasterData();
        }
        validUntil = uint48(bytes6(modeSpecificData[:6]));
        validAfter = uint48(bytes6(modeSpecificData[6:12]));
        tokenAddress = address(bytes20(modeSpecificData[12:32]));
        exchangeRate = uint256(bytes32(modeSpecificData[32:64]));
        appliedFeeMarkup = uint48(bytes6(modeSpecificData[64:70]));
        signature = modeSpecificData[70:];
    }
}
