// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Script } from "forge-std/Script.sol";
import { ButtonHub } from "../src/ButtonHub.sol";

contract Deploy is Script {
  function run() external {
    vm.startBroadcast();
    new ButtonHub();
    vm.stopBroadcast();
  }
}
