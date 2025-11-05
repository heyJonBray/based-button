// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Script, console } from "forge-std/Script.sol";
import { MockERC20 } from "../test/mocks/MockERC20.sol";

contract DeployMockUSDC is Script {
  function run() external {
    uint256 privateKey = vm.envUint("PRIVATE_KEY");
    require(privateKey != 0, "PRIVATE_KEY must be set");

    vm.startBroadcast(privateKey);
    MockERC20 usdc = new MockERC20("Mock USDC", "USDC", 6);
    vm.stopBroadcast();

    console.log("MockUSDC deployed at:", address(usdc));
    console.log("Add this to .env.local:");
    console.log("USDC_ADDRESS=", address(usdc));
  }
}

