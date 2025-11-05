// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Script } from "forge-std/Script.sol";
import { ButtonHub } from "../src/ButtonHub.sol";

contract Deploy is Script {
  address constant JON = 0xef00A763368C98C361a9a30cE44D24c8Fed43844;
  address constant BASE_SEPOLIA_USDC_ADDRESS = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;

  function run() external {
    address owner = vm.envOr("INITIAL_OWNER", JON);
    address usdcToken = vm.envOr("USDC_ADDRESS", BASE_SEPOLIA_USDC_ADDRESS);
    uint256 privateKey = vm.envUint("PRIVATE_KEY");

    require(owner != address(0), "Invalid owner address");
    require(usdcToken != address(0), "Invalid USDC address");

    vm.startBroadcast(privateKey);
    new ButtonHub(owner, usdcToken);
    vm.stopBroadcast();
  }
}
