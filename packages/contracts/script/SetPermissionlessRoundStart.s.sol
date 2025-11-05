// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Script, console } from "forge-std/Script.sol";
import { ButtonHub } from "../src/ButtonHub.sol";

contract SetPermissionlessRoundStart is Script {
  function run() external {
    address hubAddress = vm.envAddress("HUB_ADDRESS");
    require(hubAddress != address(0), "HUB_ADDRESS must be set");

    bool enabled = vm.envOr("PERMISSIONLESS_ROUND_ENABLED", false);

    require(hubAddress.code.length > 0, "HUB_ADDRESS is not a contract");
    ButtonHub hub = ButtonHub(hubAddress);

    vm.startBroadcast();
    hub.setPermissionlessRoundStart(enabled);
    vm.stopBroadcast();

    console.log("Permissionless round start set to:", enabled);
  }
}

