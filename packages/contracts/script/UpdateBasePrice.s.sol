// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Script, console } from "forge-std/Script.sol";
import { ButtonHub } from "../src/ButtonHub.sol";

contract UpdateBasePrice is Script {
  function run() external {
    address hubAddress = vm.envAddress("HUB_ADDRESS");
    require(hubAddress != address(0), "HUB_ADDRESS must be set");

    uint256 roundId = vm.envUint("ROUND_ID");
    uint256 newPrice = vm.envUint("NEW_PRICE");
    require(newPrice > 0, "NEW_PRICE must be greater than 0");

    ButtonHub hub = ButtonHub(hubAddress);

    ButtonHub.RoundConfig memory config = hub.getRoundConfig(roundId);
    uint256 oldPrice = config.basePrice;

    if (oldPrice == newPrice) {
      console.log("Price is already set to:", newPrice);
      return;
    }

    vm.startBroadcast();
    hub.updateBasePrice(roundId, newPrice);
    vm.stopBroadcast();

    console.log("Base price updated for round:", roundId);
    console.log("  Old price:", oldPrice);
    console.log("  New price:", newPrice);
  }
}

