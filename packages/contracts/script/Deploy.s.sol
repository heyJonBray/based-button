// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Script } from "forge-std/Script.sol";
import { ButtonHub } from "../src/ButtonHub.sol";

address constant INITIAL_OWNER = 0x3b138FC7eC06B2A44565994CfDe5134A75915995;
address constant BASE_SEPOLIA_USDC_ADDRESS = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;
address constant BASE_USDC_ADDRESS = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;

contract Deploy is Script {
  function run() external {
    vm.startBroadcast();
    new ButtonHub(INITIAL_OWNER, BASE_SEPOLIA_USDC_ADDRESS);
    vm.stopBroadcast();
  }
}
