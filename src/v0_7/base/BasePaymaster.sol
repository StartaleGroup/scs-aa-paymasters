// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IPaymaster} from "@account-abstraction/v0_7/contracts/interfaces/IPaymaster.sol";

contract BasePaymaster is IPaymaster, Ownable {

}
