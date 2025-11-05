// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Script, console } from "forge-std/Script.sol";
import { ButtonHub } from "../src/ButtonHub.sol";

contract SetDefaultToken is Script {
  function run() external {
    address hubAddress = vm.envAddress("HUB_ADDRESS");
    require(hubAddress != address(0), "HUB_ADDRESS must be set");
    require(hubAddress.code.length > 0, "HUB_ADDRESS must be a contract");

    address newToken = vm.envAddress("DEFAULT_TOKEN");
    require(newToken != address(0), "DEFAULT_TOKEN must be set");
    require(newToken.code.length > 0, "DEFAULT_TOKEN must be a contract");

    ButtonHub hub = ButtonHub(hubAddress);

    address oldToken = hub.defaultToken();
    require(newToken != oldToken, "New token is already the default");

    vm.startBroadcast();
    hub.setDefaultToken(newToken);
    vm.stopBroadcast();

    console.log("Default token updated:");
    console.log("  Old token:", oldToken);
    console.log("  New token:", newToken);
    console.log("  Block:", block.number);
  }
}

