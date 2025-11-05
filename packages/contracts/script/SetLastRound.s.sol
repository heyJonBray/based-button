// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Script, console } from "forge-std/Script.sol";
import { ButtonHub } from "../src/ButtonHub.sol";

contract SetLastRound is Script {
  function run() external {
    address hubAddress = vm.envAddress("HUB_ADDRESS");
    require(hubAddress != address(0), "HUB_ADDRESS must be set");

    bool locked = vm.envOr("CONTRACT_LOCKED", false);

    require(hubAddress.code.length > 0, "HUB_ADDRESS must be a contract");
    ButtonHub hub = ButtonHub(hubAddress);

    uint256 privateKey = vm.envUint("PRIVATE_KEY");

    vm.startBroadcast(privateKey);
    try hub.setLastRound(locked) {
      console.log("Successfully set last round lock");
      vm.stopBroadcast();
    } catch Error(string memory reason) {
      vm.stopBroadcast();
      console.log("Error setting last round lock:", reason);
      revert(reason);
    }

    console.log("Last round lock set to:", locked ? "locked" : "unlocked");
    console.log("Block:", block.number);
    console.log("Hub address:", hubAddress);
  }
}

