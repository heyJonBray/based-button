// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Script, console } from "forge-std/Script.sol";
import { ButtonHub } from "../src/ButtonHub.sol";

contract SetLastRound is Script {
  function run() external {
    address hubAddress = vm.envAddress("HUB_ADDRESS");
    require(hubAddress != address(0), "HUB_ADDRESS must be set");

    bool locked = vm.envOr("CONTRACT_LOCKED", false);

    ButtonHub hub = ButtonHub(hubAddress);

    vm.startBroadcast();
    hub.setLastRound(locked);
    vm.stopBroadcast();

    console.log("Last round lock set to:", locked);
    if (locked) {
      console.log("WARNING: No new rounds can be started after the current round ends!");
    }
  }
}

