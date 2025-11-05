// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Script, console } from "forge-std/Script.sol";
import { ButtonHub } from "../src/ButtonHub.sol";

contract SetDefaultToken is Script {
  function run() external {
    address hubAddress = vm.envAddress("HUB_ADDRESS");
    require(hubAddress != address(0), "HUB_ADDRESS must be set");

    address newToken = vm.envAddress("DEFAULT_TOKEN");
    require(newToken != address(0), "DEFAULT_TOKEN must be set");

    ButtonHub hub = ButtonHub(hubAddress);

    address oldToken = hub.defaultToken();

    vm.startBroadcast();
    hub.setDefaultToken(newToken);
    vm.stopBroadcast();

    console.log("Default token updated:");
    console.log("  Old token:", oldToken);
    console.log("  New token:", newToken);
  }
}

