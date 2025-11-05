// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Script, console } from "forge-std/Script.sol";
import { ButtonHub } from "../src/ButtonHub.sol";

contract StartRound is Script {
  function run() external {
    address hubAddress = vm.envAddress("HUB_ADDRESS");
    require(hubAddress != address(0), "HUB_ADDRESS must be set");

    ButtonHub hub = ButtonHub(hubAddress);

    // Read parameters from environment or use defaults
    address token = vm.envOr("TOKEN", address(0)); // address(0) uses defaultToken
    uint64 roundDuration = uint64(vm.envOr("ROUND_DURATION", uint256(600))); // 10 minutes default
    require(roundDuration > 60, "ROUND_DURATION must be > 60 seconds");
    uint32 cooldownSeconds = uint32(vm.envOr("COOLDOWN_SECONDS", uint256(0))); // 0 = immediate
    uint16 feeBps = uint16(vm.envOr("FEE_BPS", uint256(1000))); // 10% default
    require(feeBps <= 10000, "FEE_BPS must be <= 10000");
    address feeRecipient = vm.envAddress("FEE_RECIPIENT");
    require(feeRecipient != address(0), "FEE_RECIPIENT must be set");
    uint256 basePrice = vm.envOr("BASE_PRICE", uint256(1e6)); // 1 USDC (6 decimals)
    uint256 potSeed = vm.envOr("POT_SEED", uint256(0)); // 0 = no seed
    uint256 privateKey = vm.envUint("PRIVATE_KEY");

    address tokenAddress = token == address(0) ? hub.defaultToken() : token;

    ButtonHub.StartRoundParams memory params = ButtonHub.StartRoundParams({
      token: token,
      roundDuration: roundDuration,
      cooldownSeconds: cooldownSeconds,
      feeBps: feeBps,
      feeRecipient: feeRecipient,
      pricingModel: 0, // Fixed pricing
      pricingData: "",
      basePrice: basePrice,
      potSeed: potSeed
    });

    require(privateKey != 0, "PRIVATE_KEY must be set");

    vm.startBroadcast(privateKey);
    uint256 roundId = hub.startRound(params);
    vm.stopBroadcast();

    console.log("Round started successfully!");
    console.log("Round ID:", roundId);
    console.log("Token:", tokenAddress);
    console.log("Base Price:", basePrice);
    console.log("Round Duration:", roundDuration, "seconds");
  }
}

