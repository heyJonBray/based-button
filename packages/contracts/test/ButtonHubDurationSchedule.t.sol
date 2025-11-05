// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";
import { ButtonHub } from "../src/ButtonHub.sol";
import { MockERC20 } from "./mocks/MockERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract ButtonHubDurationScheduleTest is Test {
  ButtonHub public hub;
  MockERC20 public token;

  address public owner = address(0x1);
  address public feeRecipient = address(0x2);
  address public player1 = address(0x3);
  address public player2 = address(0x4);

  uint256 constant BASE_PRICE = 1e6;
  uint64 constant INITIAL_DURATION = 10 minutes;
  uint32 constant COOLDOWN = 0;
  uint16 constant FEE_BPS = 1000;
  uint256 constant MAX_PRICE_BUFFER = BASE_PRICE * 2;

  event DurationScheduleUpdated(uint64 reduceBySeconds, uint32 everyNRound, uint64 minDuration);

  function setUp() public {
    vm.startPrank(owner);
    token = new MockERC20("Test USDC", "USDC", 6);
    hub = new ButtonHub(owner, address(token));
    vm.stopPrank();

    token.mint(player1, 1_000e6);
    token.mint(player2, 1_000e6);
    token.mint(owner, 1_000e6);
    token.mint(feeRecipient, 1_000e6);

    vm.prank(owner);
    token.approve(address(hub), type(uint256).max);

    vm.prank(player1);
    token.approve(address(hub), type(uint256).max);
  }

  function test_DurationSchedule_DecrementsAndClamps() public {
    uint64 reduceBy = 1 minutes;
    uint32 everyNRound = 10;
    uint64 minDuration = 1 minutes;

    vm.expectEmit(false, false, false, true);
    emit DurationScheduleUpdated(reduceBy, everyNRound, minDuration);
    vm.prank(owner);
    hub.setDurationReductionSchedule(reduceBy, everyNRound, minDuration);

    uint64 expectedDuration = INITIAL_DURATION;
    uint256 roundsAtMinimum = 0;
    uint256 totalRounds = (uint256(INITIAL_DURATION - minDuration) * everyNRound) / reduceBy + 15;

    for (uint256 roundIndex = 1; roundIndex <= totalRounds; roundIndex++) {
      if (roundIndex == everyNRound + 1) {
        assertEq(
          expectedDuration, INITIAL_DURATION - reduceBy, "round 11 should drop by one minute"
        );
      }

      if (expectedDuration == minDuration) {
        roundsAtMinimum += 1;
      }

      _simulateRound(expectedDuration);

      if (roundIndex % everyNRound == 0 && expectedDuration > minDuration) {
        expectedDuration -= reduceBy;
        if (expectedDuration < minDuration) {
          expectedDuration = minDuration;
        }
      }
    }

    assertGe(roundsAtMinimum, 15, "minimum duration should persist for 15+ rounds");
  }

  function test_SetDurationReductionSchedule_InvalidParams() public {
    vm.prank(owner);
    vm.expectRevert(ButtonHub.InvalidDurationSchedule.selector);
    hub.setDurationReductionSchedule(0, 1, 120);

    vm.prank(owner);
    vm.expectRevert(ButtonHub.InvalidDurationSchedule.selector);
    hub.setDurationReductionSchedule(30, 0, 120);

    vm.prank(owner);
    vm.expectRevert(ButtonHub.InvalidDurationSchedule.selector);
    hub.setDurationReductionSchedule(30, 1, 0);

    vm.prank(owner);
    vm.expectRevert(ButtonHub.InvalidDurationSchedule.selector);
    hub.setDurationReductionSchedule(30, 1, uint64(12 hours + 1));
  }

  function test_SetDurationReductionSchedule_LockedAfterStart() public {
    vm.prank(owner);
    hub.setDurationReductionSchedule(60, 10, 60);

    _simulateRound(INITIAL_DURATION);

    vm.prank(owner);
    vm.expectRevert(abi.encodeWithSelector(ButtonHub.DurationScheduleLocked.selector, 1));
    hub.setDurationReductionSchedule(30, 5, 60);
  }

  function _getStartRoundParams() internal view returns (ButtonHub.StartRoundParams memory) {
    return ButtonHub.StartRoundParams({
      token: address(0),
      roundDuration: INITIAL_DURATION,
      cooldownSeconds: COOLDOWN,
      feeBps: FEE_BPS,
      feeRecipient: feeRecipient,
      pricingModel: 0,
      pricingData: "",
      basePrice: BASE_PRICE,
      potSeed: BASE_PRICE
    });
  }

  function _startRoundAsOwner() internal returns (uint256 roundId) {
    ButtonHub.StartRoundParams memory params = _getStartRoundParams();
    vm.startPrank(owner);
    IERC20(token).approve(address(hub), type(uint256).max);
    roundId = hub.startRound(params);
    vm.stopPrank();
  }

  function _simulateRound(uint64 expectedDuration) internal {
    uint256 roundId = _startRoundAsOwner();
    (ButtonHub.RoundConfig memory config, ButtonHub.RoundState memory state) =
      _getRoundData(roundId);

    assertEq(config.roundDuration, expectedDuration, "unexpected configured round duration");
    assertEq(
      state.deadline, uint64(block.timestamp + expectedDuration), "unexpected initial deadline"
    );

    vm.prank(player1);
    hub.play(roundId, MAX_PRICE_BUFFER);

    (, state) = _getRoundData(roundId);
    assertEq(
      state.deadline,
      uint64(block.timestamp + expectedDuration),
      "deadline should extend by expected duration"
    );

    vm.warp(block.timestamp + expectedDuration + 1);
    vm.prank(player2);
    hub.finalize(roundId);
  }

  function _getRoundData(uint256 roundId)
    internal
    view
    returns (ButtonHub.RoundConfig memory config, ButtonHub.RoundState memory state)
  {
    config = hub.getRoundConfig(roundId);
    state = hub.getRoundState(roundId);
  }
}

