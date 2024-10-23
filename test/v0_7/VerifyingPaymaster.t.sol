// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {VerifyingPaymaster} from "../../src/v0_7/verifying/VerifyingPaymaster.sol";

contract VerifyingPaymasterTest is Test {
    VerifyingPaymaster public verifyingPaymaster;

    function setUp() public {
        // verifyingPaymaster = new VerifyingPaymaster();
    }

    function test_Increment() public {}

    function testFuzz_SetNumber(uint256 x) public {}
}
