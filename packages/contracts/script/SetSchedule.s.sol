// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Script, console } from "forge-std/Script.sol";
import { ButtonHub } from "../src/ButtonHub.sol";

contract SetSchedule is Script {
  function run() external {
    address hubAddress = vm.envAddress("HUB_ADDRESS");
    require(hubAddress != address(0), "HUB_ADDRESS must be set");

    uint64 reduceBySeconds = uint64(vm.envUint("SCHEDULE_REDUCE_BY_SECONDS"));
    require(reduceBySeconds > 0, "SCHEDULE_REDUCE_BY_SECONDS must be > 0");

    uint32 everyNRound = uint32(vm.envUint("SCHEDULE_EVERY_N_ROUNDS"));
    require(everyNRound > 0, "SCHEDULE_EVERY_N_ROUNDS must be > 0");

    uint64 minDuration = uint64(vm.envUint("SCHEDULE_MIN_DURATION"));
    require(minDuration > 0, "SCHEDULE_MIN_DURATION must be > 0");

    uint256 privateKey = vm.envUint("PRIVATE_KEY");
    require(privateKey != 0, "PRIVATE_KEY must be set");

    ButtonHub hub = ButtonHub(hubAddress);

    console.log("Setting new duration reduction schedule on", hubAddress);
    console.log("  reduceBySeconds:", reduceBySeconds);
    console.log("  everyNRound:", everyNRound);
    console.log("  minDuration:", minDuration);

    vm.startBroadcast(privateKey);
    hub.setDurationReductionSchedule(reduceBySeconds, everyNRound, minDuration);
    vm.stopBroadcast();

    console.log("Duration reduction schedule updated successfully.");
  }
}

