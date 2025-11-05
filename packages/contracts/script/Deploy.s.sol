// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Script } from "forge-std/Script.sol";
import { ButtonHub } from "../src/ButtonHub.sol";

contract Deploy is Script {
  address jon = 0xef00A763368C98C361a9a30cE44D24c8Fed43844;
  address baseSepoliaUsdcAddress = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;
  address usdcToken = vm.envOr("BASE_USDC_ADDRESS", baseSepoliaUsdcAddress);

  function run() external {
    vm.startBroadcast();
    new ButtonHub(jon, usdcToken);
    vm.stopBroadcast();
  }
}
