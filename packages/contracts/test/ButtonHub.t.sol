// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";
import { ButtonHub } from "../src/ButtonHub.sol";
import { MockERC20 } from "./mocks/MockERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract ButtonHubTest is Test {
  ButtonHub public hub;
  MockERC20 public token;
  address public owner = address(0x1);
  address public feeRecipient = address(0x2);
  address public player1 = address(0x3);
  address public player2 = address(0x4);

  uint256 constant BASE_PRICE = 1e6;
  uint64 constant ROUND_DURATION = 600; // 10 minutes
  uint32 constant COOLDOWN = 0;
  uint16 constant FEE_BPS = 1000; // 10%
  uint64 constant SERIES_ID = 1;

  event RoundStarted(
    address indexed token,
    uint64 indexed seriesId,
    uint256 indexed roundId,
    uint64 startTime,
    uint64 deadline,
    uint64 roundDuration,
    uint32 cooldownSeconds,
    uint16 feeBps,
    uint256 basePrice,
    uint8 pricingModel
  );

  event Play(
    uint256 indexed roundId,
    address indexed player,
    uint256 pricePaid,
    uint256 potAfter,
    uint256 feeEscrowAfter,
    uint64 newDeadline
  );

  event Finalized(
    uint256 indexed roundId, address indexed winner, uint256 potPaid, uint64 nextStartTime
  );

  event FeesWithdrawn(
    uint256 indexed roundId, address indexed recipient, uint256 amount, uint256 feeEscrowAfter
  );

  function setUp() public {
    vm.prank(owner);
    token = new MockERC20("Test USDC", "USDC", 6);
    vm.prank(owner);
    hub = new ButtonHub(owner, address(token));

    // Fund players
    token.mint(player1, 1000e6);
    token.mint(player2, 1000e6);
    token.mint(owner, 1000e6);
    token.mint(feeRecipient, 1000e6);
  }

  function _getStartRoundParams() internal view returns (ButtonHub.StartRoundParams memory) {
    return ButtonHub.StartRoundParams({
      token: address(0), // Use default token
      roundDuration: ROUND_DURATION,
      cooldownSeconds: COOLDOWN,
      feeBps: FEE_BPS,
      feeRecipient: feeRecipient,
      pricingModel: 0,
      pricingData: "",
      basePrice: BASE_PRICE,
      potSeed: 0
    });
  }

  function _startRoundAsOwner() internal returns (uint256 roundId) {
    vm.prank(owner);
    ButtonHub.StartRoundParams memory params = _getStartRoundParams();
    return hub.startRound(SERIES_ID, params);
  }

  function _approveAndPlay(address player, uint256 roundId, uint256 maxPrice) internal {
    vm.startPrank(player);
    IERC20(token).approve(address(hub), maxPrice);
    hub.play(roundId, maxPrice);
    vm.stopPrank();
  }

  // ========== Deployment Tests ==========

  function test_Deployment_SetsOwnerAndToken() public {
    assertEq(hub.owner(), owner);
    assertEq(hub.defaultToken(), address(token));
  }

  function test_Deployment_RevertsOnZeroToken() public {
    vm.expectRevert(ButtonHub.InvalidToken.selector);
    new ButtonHub(owner, address(0));
  }

  // ========== StartRound Tests ==========

  function test_StartRound_OwnerCanStart() public {
    vm.prank(owner);
    ButtonHub.StartRoundParams memory params = _getStartRoundParams();
    uint256 roundId = hub.startRound(SERIES_ID, params);

    assertEq(roundId, 1);
    (ButtonHub.RoundConfig memory config, ButtonHub.RoundState memory state) =
      _getRoundData(roundId);
    assertEq(config.token, address(token));
    assertEq(config.basePrice, BASE_PRICE);
    assertEq(config.feeBps, FEE_BPS);
    assertTrue(state.active);
    assertFalse(state.finalized);
  }

  function test_StartRound_NonOwnerRevertsWhenNotPermissionless() public {
    vm.prank(player1);
    ButtonHub.StartRoundParams memory params = _getStartRoundParams();
    vm.expectRevert(ButtonHub.NotAuthorized.selector);
    hub.startRound(SERIES_ID, params);
  }

  function test_StartRound_PermissionlessEnabled() public {
    vm.prank(owner);
    hub.setPermissionlessRoundStart(true);

    ButtonHub.StartRoundParams memory params = _getStartRoundParams();
    params.potSeed = 10e6; // Player deposits initial pot
    vm.startPrank(player1);
    IERC20(token).approve(address(hub), 10e6);
    uint256 roundId = hub.startRound(SERIES_ID, params);
    vm.stopPrank();

    (ButtonHub.RoundConfig memory config, ButtonHub.RoundState memory state) =
      _getRoundData(roundId);
    assertEq(state.potBalance, 10e6);
  }

  function test_StartRound_RevertsWhenLastRoundLocked() public {
    vm.prank(owner);
    hub.setLastRound(true);

    vm.prank(owner);
    ButtonHub.StartRoundParams memory params = _getStartRoundParams();
    vm.expectRevert(ButtonHub.LastRoundLocked.selector);
    hub.startRound(SERIES_ID, params);
  }

  function test_StartRound_WithPotSeed() public {
    ButtonHub.StartRoundParams memory params = _getStartRoundParams();
    params.potSeed = 50e6;
    vm.startPrank(owner);
    IERC20(token).approve(address(hub), 50e6);
    uint256 roundId = hub.startRound(SERIES_ID, params);
    vm.stopPrank();

    (, ButtonHub.RoundState memory state) = _getRoundData(roundId);
    assertEq(state.potBalance, 50e6);
  }

  function test_StartRound_RevertsWhenPreviousRoundActive() public {
    _startRoundAsOwner();
    vm.warp(block.timestamp + 100); // 100 seconds in

    (, ButtonHub.RoundState memory state) = _getRoundData(1);
    vm.prank(owner);
    ButtonHub.StartRoundParams memory params = _getStartRoundParams();
    vm.expectRevert(abi.encodeWithSelector(ButtonHub.RoundInProgress.selector, state.deadline));
    hub.startRound(SERIES_ID, params);
  }

  function test_StartRound_RevertsWhenCooldownActive() public {
    uint256 round1 = _startRoundAsOwner();
    _approveAndPlay(player1, round1, BASE_PRICE * 2);
    vm.warp(block.timestamp + ROUND_DURATION + 1);
    vm.prank(player2);
    hub.finalize(round1);

    vm.prank(owner);
    hub.setPermissionlessRoundStart(false);

    uint32 cooldown = 3600; // 1 hour
    vm.prank(owner);
    ButtonHub.StartRoundParams memory params = _getStartRoundParams();
    params.cooldownSeconds = cooldown;
    uint256 round2 = hub.startRound(SERIES_ID, params);

    _approveAndPlay(player1, round2, BASE_PRICE * 2);
    vm.warp(block.timestamp + ROUND_DURATION + 1);
    vm.prank(player2);
    hub.finalize(round2);

    (, ButtonHub.RoundState memory state) = _getRoundData(round2);
    vm.prank(owner);
    params.cooldownSeconds = COOLDOWN;
    vm.expectRevert(abi.encodeWithSelector(ButtonHub.CooldownActive.selector, state.nextStartTime));
    hub.startRound(SERIES_ID, params);
  }

  function test_StartRound_ValidationErrors() public {
    ButtonHub.StartRoundParams memory params = _getStartRoundParams();

    params.feeBps = 10001;
    vm.prank(owner);
    vm.expectRevert(abi.encodeWithSelector(ButtonHub.FeeTooHigh.selector, uint16(10001)));
    hub.startRound(SERIES_ID, params);

    params.feeBps = FEE_BPS;
    params.feeRecipient = address(0);
    vm.prank(owner);
    vm.expectRevert(ButtonHub.InvalidAddress.selector);
    hub.startRound(SERIES_ID, params);

    params.feeRecipient = feeRecipient;
    params.roundDuration = 0;
    vm.prank(owner);
    vm.expectRevert(ButtonHub.InvalidDuration.selector);
    hub.startRound(SERIES_ID, params);

    params.roundDuration = ROUND_DURATION;
    params.basePrice = 0;
    vm.prank(owner);
    vm.expectRevert(ButtonHub.InvalidBasePrice.selector);
    hub.startRound(SERIES_ID, params);

    params.basePrice = BASE_PRICE;
    params.pricingModel = 99;
    vm.prank(owner);
    vm.expectRevert(abi.encodeWithSelector(ButtonHub.InvalidPricingModel.selector, uint8(99)));
    hub.startRound(SERIES_ID, params);
  }

  // ========== Play Tests ==========

  function test_Play_Success() public {
    uint256 roundId = _startRoundAsOwner();
    uint256 initialPot = 0;
    uint256 initialFeeEscrow = 0;

    _approveAndPlay(player1, roundId, BASE_PRICE * 2);

    (, ButtonHub.RoundState memory state) = _getRoundData(roundId);
    assertEq(state.currentWinner, player1);
    assertEq(state.plays, 1);
    assertEq(state.potBalance, initialPot + (BASE_PRICE * 90 / 100)); // 90% to pot
    assertEq(state.feeEscrow, initialFeeEscrow + (BASE_PRICE * 10 / 100)); // 10% to fees
    assertEq(state.deadline, block.timestamp + ROUND_DURATION);
  }

  function test_Play_ExtendsDeadline() public {
    uint256 roundId = _startRoundAsOwner();
    uint64 initialDeadline = uint64(block.timestamp + ROUND_DURATION);

    vm.warp(block.timestamp + 300); // 5 minutes in
    _approveAndPlay(player1, roundId, BASE_PRICE * 2);

    (, ButtonHub.RoundState memory state) = _getRoundData(roundId);
    assertEq(state.deadline, block.timestamp + ROUND_DURATION);
    assertGt(state.deadline, initialDeadline);
  }

  function test_Play_RevertsWhenRoundInactive() public {
    uint256 roundId = _startRoundAsOwner();
    _approveAndPlay(player1, roundId, BASE_PRICE * 2);
    vm.warp(block.timestamp + ROUND_DURATION + 1);
    vm.prank(player2);
    hub.finalize(roundId);

    vm.prank(player1);
    IERC20(token).approve(address(hub), BASE_PRICE);
    vm.expectRevert(ButtonHub.RoundInactive.selector);
    hub.play(roundId, BASE_PRICE);
  }

  function test_Play_RevertsWhenRoundExpired() public {
    uint256 roundId = _startRoundAsOwner();
    vm.warp(block.timestamp + ROUND_DURATION + 1);

    vm.prank(player1);
    IERC20(token).approve(address(hub), BASE_PRICE);
    vm.expectRevert(ButtonHub.RoundExpired.selector);
    hub.play(roundId, BASE_PRICE);
  }

  function test_Play_RevertsOnPriceSlippage() public {
    uint256 roundId = _startRoundAsOwner();

    vm.prank(player1);
    IERC20(token).approve(address(hub), BASE_PRICE);
    vm.expectRevert(
      abi.encodeWithSelector(ButtonHub.PriceSlippage.selector, BASE_PRICE, BASE_PRICE - 1)
    );
    hub.play(roundId, BASE_PRICE - 1);
  }

  function test_Play_UpdatesWinner() public {
    uint256 roundId = _startRoundAsOwner();

    _approveAndPlay(player1, roundId, BASE_PRICE * 2);
    (, ButtonHub.RoundState memory state) = _getRoundData(roundId);
    assertEq(state.currentWinner, player1);

    vm.warp(block.timestamp + 100);
    _approveAndPlay(player2, roundId, BASE_PRICE * 2);
    (, state) = _getRoundData(roundId);
    assertEq(state.currentWinner, player2);
  }

  function test_Play_WithUpdatedPrice() public {
    uint256 roundId = _startRoundAsOwner();
    uint256 newPrice = BASE_PRICE * 2;

    vm.prank(owner);
    hub.updateBasePrice(roundId, newPrice);

    _approveAndPlay(player1, roundId, newPrice * 2);

    uint256 currentPrice = hub.getCurrentPrice(roundId);
    assertEq(currentPrice, newPrice);
  }

  // ========== Finalize Tests ==========

  function test_Finalize_Success() public {
    uint256 roundId = _startRoundAsOwner();
    _approveAndPlay(player1, roundId, BASE_PRICE * 2);

    (, ButtonHub.RoundState memory stateBefore) = _getRoundData(roundId);
    uint256 potBefore = stateBefore.potBalance;
    uint256 playerBalanceBefore = token.balanceOf(player1);
    vm.warp(block.timestamp + ROUND_DURATION + 1);

    vm.prank(player2);
    hub.finalize(roundId);

    (, ButtonHub.RoundState memory state) = _getRoundData(roundId);
    assertTrue(state.finalized);
    assertFalse(state.active);
    assertEq(token.balanceOf(player1), playerBalanceBefore + potBefore);
    assertEq(state.potBalance, 0);
  }

  function test_Finalize_RevertsWhenRoundInProgress() public {
    uint256 roundId = _startRoundAsOwner();
    _approveAndPlay(player1, roundId, BASE_PRICE * 2);

    (, ButtonHub.RoundState memory state) = _getRoundData(roundId);
    vm.prank(player2);
    vm.expectRevert(abi.encodeWithSelector(ButtonHub.RoundInProgress.selector, state.deadline));
    hub.finalize(roundId);
  }

  function test_Finalize_RevertsWhenAlreadyFinalized() public {
    uint256 roundId = _startRoundAsOwner();
    _approveAndPlay(player1, roundId, BASE_PRICE * 2);
    vm.warp(block.timestamp + ROUND_DURATION + 1);
    vm.prank(player2);
    hub.finalize(roundId);

    vm.prank(player2);
    vm.expectRevert(ButtonHub.RoundAlreadyFinalized.selector);
    hub.finalize(roundId);
  }

  function test_Finalize_RevertsWhenNoWinner() public {
    uint256 roundId = _startRoundAsOwner();
    vm.warp(block.timestamp + ROUND_DURATION + 1);

    vm.prank(player1);
    vm.expectRevert(ButtonHub.NoWinner.selector);
    hub.finalize(roundId);
  }

  function test_Finalize_SetsCooldown() public {
    uint256 roundId = _startRoundAsOwner();
    _approveAndPlay(player1, roundId, BASE_PRICE * 2);
    vm.warp(block.timestamp + ROUND_DURATION + 1);
    vm.prank(player1);
    hub.finalize(roundId);

    (, ButtonHub.RoundState memory state) = _getRoundData(roundId);
    assertEq(state.nextStartTime, block.timestamp + COOLDOWN);
  }

  // ========== WithdrawFees Tests ==========

  function test_WithdrawFees_Success() public {
    uint256 roundId = _startRoundAsOwner();
    _approveAndPlay(player1, roundId, BASE_PRICE * 2);

    uint256 feeAmount = BASE_PRICE * FEE_BPS / 10000;
    uint256 withdrawAmount = feeAmount / 2;

    vm.prank(feeRecipient);
    hub.withdrawFees(roundId, withdrawAmount, feeRecipient);

    (, ButtonHub.RoundState memory state) = _getRoundData(roundId);
    assertEq(state.feeEscrow, feeAmount - withdrawAmount);
    assertEq(token.balanceOf(feeRecipient), 1000e6 + withdrawAmount);
  }

  function test_WithdrawFees_RevertsWhenNotRecipient() public {
    uint256 roundId = _startRoundAsOwner();
    _approveAndPlay(player1, roundId, BASE_PRICE * 2);

    vm.prank(player1);
    vm.expectRevert(ButtonHub.NotAuthorized.selector);
    hub.withdrawFees(roundId, 1, player1);
  }

  function test_WithdrawFees_RevertsWhenInsufficient() public {
    uint256 roundId = _startRoundAsOwner();
    _approveAndPlay(player1, roundId, BASE_PRICE * 2);

    uint256 feeAmount = BASE_PRICE * FEE_BPS / 10000;

    vm.prank(feeRecipient);
    vm.expectRevert(
      abi.encodeWithSelector(ButtonHub.InsufficientFees.selector, feeAmount + 1, feeAmount)
    );
    hub.withdrawFees(roundId, feeAmount + 1, feeRecipient);
  }

  function test_WithdrawFees_RevertsOnZeroAddress() public {
    uint256 roundId = _startRoundAsOwner();
    _approveAndPlay(player1, roundId, BASE_PRICE * 2);

    vm.prank(feeRecipient);
    vm.expectRevert(ButtonHub.InvalidAddress.selector);
    hub.withdrawFees(roundId, 1, address(0));
  }

  // ========== Owner Functions Tests ==========

  function test_SetPermissionlessRoundStart() public {
    assertFalse(hub.permissionlessRoundStart());

    vm.prank(owner);
    hub.setPermissionlessRoundStart(true);
    assertTrue(hub.permissionlessRoundStart());

    vm.prank(owner);
    hub.setPermissionlessRoundStart(false);
    assertFalse(hub.permissionlessRoundStart());
  }

  function test_SetLastRound() public {
    assertFalse(hub.lastRoundLocked());

    vm.prank(owner);
    hub.setLastRound(true);
    assertTrue(hub.lastRoundLocked());
  }

  function test_UpdateBasePrice() public {
    uint256 roundId = _startRoundAsOwner();
    uint256 newPrice = BASE_PRICE * 2;

    vm.prank(owner);
    hub.updateBasePrice(roundId, newPrice);

    ButtonHub.RoundConfig memory config = hub.getRoundConfig(roundId);
    assertEq(config.basePrice, newPrice);
  }

  function test_UpdateBasePrice_RevertsWhenFinalized() public {
    uint256 roundId = _startRoundAsOwner();
    _approveAndPlay(player1, roundId, BASE_PRICE * 2);
    vm.warp(block.timestamp + ROUND_DURATION + 1);
    vm.prank(player2);
    hub.finalize(roundId);

    vm.prank(owner);
    vm.expectRevert(ButtonHub.RoundAlreadyFinalized.selector);
    hub.updateBasePrice(roundId, BASE_PRICE * 2);
  }

  function test_SetDefaultToken() public {
    MockERC20 newToken = new MockERC20("New USDC", "USDC", 6);

    vm.prank(owner);
    hub.setDefaultToken(address(newToken));
    assertEq(hub.defaultToken(), address(newToken));
  }

  // ========== Read Helper Tests ==========

  function test_GetRoundConfig() public {
    uint256 roundId = _startRoundAsOwner();
    ButtonHub.RoundConfig memory config = hub.getRoundConfig(roundId);
    assertEq(config.token, address(token));
    assertEq(config.basePrice, BASE_PRICE);
    assertEq(config.feeBps, FEE_BPS);
  }

  function test_GetRoundState() public {
    uint256 roundId = _startRoundAsOwner();
    ButtonHub.RoundState memory state = hub.getRoundState(roundId);
    assertTrue(state.active);
    assertEq(state.seriesId, SERIES_ID);
  }

  function test_GetCurrentPrice() public {
    uint256 roundId = _startRoundAsOwner();
    assertEq(hub.getCurrentPrice(roundId), BASE_PRICE);

    vm.prank(owner);
    hub.updateBasePrice(roundId, BASE_PRICE * 2);
    assertEq(hub.getCurrentPrice(roundId), BASE_PRICE * 2);
  }

  function test_GetTimeRemaining() public {
    uint256 roundId = _startRoundAsOwner();
    assertEq(hub.getTimeRemaining(roundId), ROUND_DURATION);

    vm.warp(block.timestamp + 100);
    assertEq(hub.getTimeRemaining(roundId), ROUND_DURATION - 100);

    vm.warp(block.timestamp + ROUND_DURATION);
    assertEq(hub.getTimeRemaining(roundId), 0);
  }

  function test_GetFeeEscrow() public {
    uint256 roundId = _startRoundAsOwner();
    assertEq(hub.getFeeEscrow(roundId), 0);

    _approveAndPlay(player1, roundId, BASE_PRICE * 2);
    uint256 expectedFee = BASE_PRICE * FEE_BPS / 10000;
    assertEq(hub.getFeeEscrow(roundId), expectedFee);
  }

  function test_GetNextStartTime() public {
    assertEq(hub.getNextStartTime(SERIES_ID), 0);

    uint256 roundId = _startRoundAsOwner();
    _approveAndPlay(player1, roundId, BASE_PRICE * 2);
    vm.warp(block.timestamp + ROUND_DURATION + 1);
    vm.prank(player1);
    hub.finalize(roundId);

    assertEq(hub.getNextStartTime(SERIES_ID), block.timestamp + COOLDOWN);
  }

  function test_GetLatestRoundId() public {
    assertEq(hub.getLatestRoundId(SERIES_ID), 0);

    uint256 roundId = _startRoundAsOwner();
    assertEq(hub.getLatestRoundId(SERIES_ID), roundId);
  }

  // ========== Helper Functions ==========

  function _getRoundData(uint256 roundId)
    internal
    view
    returns (ButtonHub.RoundConfig memory config, ButtonHub.RoundState memory state)
  {
    config = hub.getRoundConfig(roundId);
    state = hub.getRoundState(roundId);
  }
}

