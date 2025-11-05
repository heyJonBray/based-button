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
  uint256 constant MAX_PRICE_BUFFER = BASE_PRICE * 2;

  event RoundStarted(
    address indexed token,
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

  event RoundEnded(uint256 indexed roundId, address indexed winner, uint64 endTime);

  event Finalized(
    uint256 indexed roundId, address indexed winner, uint256 potPaid, uint64 nextStartTime
  );

  event FeesWithdrawn(
    uint256 indexed roundId, address indexed recipient, uint256 amount, uint256 feeEscrowAfter
  );

  event BasePriceUpdated(uint256 indexed roundId, uint256 newPrice);
  event PermissionlessRoundStartUpdated(bool enabled);
  event LastRoundLockSet(bool locked);
  event DefaultTokenUpdated(address token);

  function setUp() public {
    vm.startPrank(owner);
    token = new MockERC20("Test USDC", "USDC", 6);
    hub = new ButtonHub(owner, address(token));
    vm.stopPrank();

    // Fund players
    token.mint(player1, 1000e6);
    token.mint(player2, 1000e6);
    token.mint(owner, 1000e6);
    token.mint(feeRecipient, 1000e6);

    vm.prank(owner);
    token.approve(address(hub), type(uint256).max);
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

  function _approveAndPlay(address player, uint256 roundId, uint256 maxPrice) internal {
    vm.startPrank(player);
    IERC20(token).approve(address(hub), maxPrice);
    hub.play(roundId, maxPrice);
    vm.stopPrank();
  }

  // ========== Deployment Tests ==========

  function test_Deployment_SetsOwnerAndToken() public view {
    assertEq(hub.owner(), owner);
    assertEq(hub.defaultToken(), address(token));
  }

  function test_Deployment_RevertsOnZeroToken() public {
    vm.expectRevert(ButtonHub.InvalidToken.selector);
    new ButtonHub(owner, address(0));
  }

  // ========== StartRound Tests ==========

  function test_StartRound_OwnerCanStart() public {
    ButtonHub.StartRoundParams memory params = _getStartRoundParams();
    vm.prank(owner);
    IERC20(token).approve(address(hub), type(uint256).max);

    vm.expectEmit(true, true, false, false);
    emit RoundStarted(
      address(token),
      1, // roundId
      uint64(block.timestamp),
      uint64(block.timestamp + ROUND_DURATION),
      ROUND_DURATION,
      COOLDOWN,
      FEE_BPS,
      BASE_PRICE,
      0 // pricingModel
    );

    vm.prank(owner);
    uint256 roundId = hub.startRound(params);

    assertEq(roundId, 1);
    (ButtonHub.RoundConfig memory config, ButtonHub.RoundState memory state) =
      _getRoundData(roundId);
    assertEq(config.token, address(token));
    assertEq(config.basePrice, BASE_PRICE);
    assertEq(config.feeBps, FEE_BPS);
    assertTrue(state.active);
    assertFalse(state.finalized);
    assertEq(state.potBalance, BASE_PRICE);
  }

  function test_StartRound_NonOwnerRevertsWhenNotPermissionless() public {
    vm.prank(player1);
    ButtonHub.StartRoundParams memory params = _getStartRoundParams();
    vm.expectRevert(ButtonHub.NotAuthorized.selector);
    hub.startRound(params);
  }

  function test_StartRound_PermissionlessEnabled() public {
    vm.prank(owner);
    hub.setPermissionlessRoundStart(true);

    ButtonHub.StartRoundParams memory params = _getStartRoundParams();
    vm.startPrank(player1);
    IERC20(token).approve(address(hub), params.potSeed);
    uint256 roundId = hub.startRound(params);
    vm.stopPrank();

    (, ButtonHub.RoundState memory state) = _getRoundData(roundId);
    assertEq(state.potBalance, params.potSeed);
  }

  function test_StartRound_RevertsWhenLastRoundLocked() public {
    vm.prank(owner);
    hub.setLastRound(true);

    vm.prank(owner);
    ButtonHub.StartRoundParams memory params = _getStartRoundParams();
    vm.expectRevert(ButtonHub.LastRoundLocked.selector);
    hub.startRound(params);
  }

  function test_StartRound_WithPotSeed() public {
    ButtonHub.StartRoundParams memory params = _getStartRoundParams();
    params.basePrice = 50e6;
    params.potSeed = 50e6;
    vm.startPrank(owner);
    IERC20(token).approve(address(hub), 50e6);
    uint256 roundId = hub.startRound(params);
    vm.stopPrank();

    (, ButtonHub.RoundState memory state) = _getRoundData(roundId);
    assertEq(state.potBalance, 50e6);
  }

  function test_StartRound_RevertsWhenPotSeedMismatch() public {
    ButtonHub.StartRoundParams memory params = _getStartRoundParams();
    params.potSeed = params.basePrice / 2;

    vm.prank(owner);
    IERC20(token).approve(address(hub), params.potSeed);

    vm.expectRevert(
      abi.encodeWithSelector(ButtonHub.PotSeedMismatch.selector, params.potSeed, params.basePrice)
    );
    vm.prank(owner);
    hub.startRound(params);
  }

  function test_StartRound_RevertsWhenPreviousRoundActive() public {
    _startRoundAsOwner();
    vm.warp(block.timestamp + 100); // 100 seconds in

    (, ButtonHub.RoundState memory state) = _getRoundData(1);
    vm.prank(owner);
    ButtonHub.StartRoundParams memory params = _getStartRoundParams();
    vm.expectRevert(abi.encodeWithSelector(ButtonHub.RoundInProgress.selector, state.deadline));
    hub.startRound(params);
  }

  function test_StartRound_RevertsWhenCooldownActive() public {
    uint256 round1 = _startRoundAsOwner();
    _approveAndPlay(player1, round1, MAX_PRICE_BUFFER);
    vm.warp(block.timestamp + ROUND_DURATION + 1);
    vm.prank(player2);
    hub.finalize(round1);

    vm.prank(owner);
    hub.setPermissionlessRoundStart(false);

    uint32 cooldown = 3600; // 1 hour
    vm.prank(owner);
    ButtonHub.StartRoundParams memory params = _getStartRoundParams();
    params.cooldownSeconds = cooldown;
    uint256 round2 = hub.startRound(params);

    _approveAndPlay(player1, round2, MAX_PRICE_BUFFER);
    vm.warp(block.timestamp + ROUND_DURATION + 1);
    vm.prank(player2);
    hub.finalize(round2);

    (, ButtonHub.RoundState memory state) = _getRoundData(round2);
    vm.prank(owner);
    params.cooldownSeconds = COOLDOWN;
    vm.expectRevert(abi.encodeWithSelector(ButtonHub.CooldownActive.selector, state.nextStartTime));
    hub.startRound(params);
  }

  function test_StartRound_ValidationErrors() public {
    ButtonHub.StartRoundParams memory params = _getStartRoundParams();

    // Test max fee: 50%
    params.feeBps = 5000;
    vm.prank(owner);
    hub.startRound(params);
    vm.prank(owner);
    hub.setLastRound(true);

    // Test > max fee
    params.feeBps = 5001;
    vm.prank(owner);
    hub.setLastRound(false);
    vm.prank(owner);
    vm.expectRevert(abi.encodeWithSelector(ButtonHub.FeeTooHigh.selector, uint16(5001)));
    hub.startRound(params);

    params.feeBps = FEE_BPS;
    params.feeRecipient = address(0);
    vm.prank(owner);
    vm.expectRevert(ButtonHub.InvalidAddress.selector);
    hub.startRound(params);

    params.feeRecipient = feeRecipient;
    params.roundDuration = 0;
    vm.prank(owner);
    vm.expectRevert(ButtonHub.InvalidDuration.selector);
    hub.startRound(params);

    params.roundDuration = ROUND_DURATION;
    params.basePrice = 0;
    vm.prank(owner);
    vm.expectRevert(ButtonHub.InvalidBasePrice.selector);
    hub.startRound(params);

    params.basePrice = BASE_PRICE;
    params.pricingModel = 99;
    vm.prank(owner);
    vm.expectRevert(abi.encodeWithSelector(ButtonHub.InvalidPricingModel.selector, uint8(99)));
    hub.startRound(params);
  }

  // ========== Play Tests ==========

  function test_Play_Success() public {
    uint256 roundId = _startRoundAsOwner();
    uint256 initialPot = BASE_PRICE;
    uint256 initialFeeEscrow = 0;

    uint256 expectedPot = initialPot + (BASE_PRICE * 90 / 100);
    uint256 expectedFeeEscrow = initialFeeEscrow + (BASE_PRICE * 10 / 100);

    vm.startPrank(player1);
    IERC20(token).approve(address(hub), MAX_PRICE_BUFFER);

    vm.expectEmit(true, true, false, false, address(hub));
    emit Play(
      roundId,
      player1,
      BASE_PRICE,
      expectedPot,
      expectedFeeEscrow,
      uint64(block.timestamp + ROUND_DURATION)
    );

    hub.play(roundId, MAX_PRICE_BUFFER);
    vm.stopPrank();

    (, ButtonHub.RoundState memory state) = _getRoundData(roundId);
    assertEq(state.currentWinner, player1);
    assertEq(state.plays, 1);
    assertEq(state.potBalance, expectedPot);
    assertEq(state.feeEscrow, expectedFeeEscrow);
    assertEq(state.deadline, block.timestamp + ROUND_DURATION);
  }

  function test_Play_ExtendsDeadline() public {
    uint256 roundId = _startRoundAsOwner();
    uint64 initialDeadline = uint64(block.timestamp + ROUND_DURATION);

    vm.warp(block.timestamp + 300); // 5 minutes in
    _approveAndPlay(player1, roundId, MAX_PRICE_BUFFER);

    (, ButtonHub.RoundState memory state) = _getRoundData(roundId);
    assertEq(state.deadline, block.timestamp + ROUND_DURATION);
    assertGt(state.deadline, initialDeadline);
  }

  function test_Play_RevertsWhenRoundInactive() public {
    uint256 roundId = _startRoundAsOwner();
    _approveAndPlay(player1, roundId, MAX_PRICE_BUFFER);
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

    _approveAndPlay(player1, roundId, MAX_PRICE_BUFFER);
    (, ButtonHub.RoundState memory state) = _getRoundData(roundId);
    assertEq(state.currentWinner, player1);

    vm.warp(block.timestamp + 100);
    _approveAndPlay(player2, roundId, MAX_PRICE_BUFFER);
    (, state) = _getRoundData(roundId);
    assertEq(state.currentWinner, player2);
  }

  function test_Play_WithUpdatedPrice() public {
    uint256 roundId = _startRoundAsOwner();
    uint256 newPrice = MAX_PRICE_BUFFER;

    vm.prank(owner);
    hub.updateBasePrice(roundId, newPrice);

    _approveAndPlay(player1, roundId, newPrice * 2);

    uint256 currentPrice = hub.getCurrentPrice(roundId);
    assertEq(currentPrice, newPrice);
  }

  // ========== Finalize Tests ==========

  function test_Finalize_Success() public {
    uint256 roundId = _startRoundAsOwner();
    _approveAndPlay(player1, roundId, MAX_PRICE_BUFFER);

    (, ButtonHub.RoundState memory stateBefore) = _getRoundData(roundId);
    uint256 potBefore = stateBefore.potBalance;
    uint256 playerBalanceBefore = token.balanceOf(player1);
    vm.warp(block.timestamp + ROUND_DURATION + 1);

    vm.expectEmit(true, true, false, false);
    emit RoundEnded(roundId, player1, uint64(block.timestamp));

    vm.expectEmit(true, true, false, false);
    emit Finalized(roundId, player1, potBefore, uint64(block.timestamp + COOLDOWN));

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
    _approveAndPlay(player1, roundId, MAX_PRICE_BUFFER);

    (, ButtonHub.RoundState memory state) = _getRoundData(roundId);
    vm.prank(player2);
    vm.expectRevert(abi.encodeWithSelector(ButtonHub.RoundInProgress.selector, state.deadline));
    hub.finalize(roundId);
  }

  function test_Finalize_RevertsWhenAlreadyFinalized() public {
    uint256 roundId = _startRoundAsOwner();
    _approveAndPlay(player1, roundId, MAX_PRICE_BUFFER);
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
    _approveAndPlay(player1, roundId, MAX_PRICE_BUFFER);
    vm.warp(block.timestamp + ROUND_DURATION + 1);
    vm.prank(player1);
    hub.finalize(roundId);

    (, ButtonHub.RoundState memory state) = _getRoundData(roundId);
    assertEq(state.nextStartTime, block.timestamp + COOLDOWN);
  }

  // ========== WithdrawFees Tests ==========

  function test_WithdrawFees_Success() public {
    uint256 roundId = _startRoundAsOwner();
    _approveAndPlay(player1, roundId, MAX_PRICE_BUFFER);

    uint256 feeAmount = BASE_PRICE * FEE_BPS / 10000;
    uint256 withdrawAmount = feeAmount / 2;
    uint256 expectedFeeEscrowAfter = feeAmount - withdrawAmount;

    vm.expectEmit(true, true, false, false);
    emit FeesWithdrawn(roundId, feeRecipient, withdrawAmount, expectedFeeEscrowAfter);

    vm.prank(feeRecipient);
    hub.withdrawFees(roundId, withdrawAmount, feeRecipient);

    (, ButtonHub.RoundState memory state) = _getRoundData(roundId);
    assertEq(state.feeEscrow, expectedFeeEscrowAfter);
    assertEq(token.balanceOf(feeRecipient), 1000e6 + withdrawAmount);
  }

  function test_WithdrawFees_RevertsWhenNotRecipient() public {
    uint256 roundId = _startRoundAsOwner();
    _approveAndPlay(player1, roundId, MAX_PRICE_BUFFER);

    vm.prank(player1);
    vm.expectRevert(ButtonHub.NotAuthorized.selector);
    hub.withdrawFees(roundId, 1, player1);
  }

  function test_WithdrawFees_RevertsWhenInsufficient() public {
    uint256 roundId = _startRoundAsOwner();
    _approveAndPlay(player1, roundId, MAX_PRICE_BUFFER);

    uint256 feeAmount = BASE_PRICE * FEE_BPS / 10000;

    vm.prank(feeRecipient);
    vm.expectRevert(
      abi.encodeWithSelector(ButtonHub.InsufficientFees.selector, feeAmount + 1, feeAmount)
    );
    hub.withdrawFees(roundId, feeAmount + 1, feeRecipient);
  }

  function test_WithdrawFees_RevertsOnZeroAddress() public {
    uint256 roundId = _startRoundAsOwner();
    _approveAndPlay(player1, roundId, MAX_PRICE_BUFFER);

    vm.prank(feeRecipient);
    vm.expectRevert(ButtonHub.InvalidAddress.selector);
    hub.withdrawFees(roundId, 1, address(0));
  }

  // ========== Owner Functions Tests ==========

  function test_SetPermissionlessRoundStart() public {
    assertFalse(hub.permissionlessRoundStart());

    vm.expectEmit(false, false, false, true);
    emit PermissionlessRoundStartUpdated(true);

    vm.prank(owner);
    hub.setPermissionlessRoundStart(true);
    assertTrue(hub.permissionlessRoundStart());

    vm.expectEmit(false, false, false, true);
    emit PermissionlessRoundStartUpdated(false);

    vm.prank(owner);
    hub.setPermissionlessRoundStart(false);
    assertFalse(hub.permissionlessRoundStart());
  }

  function test_SetLastRound() public {
    assertFalse(hub.lastRoundLocked());

    vm.expectEmit(false, false, false, true);
    emit LastRoundLockSet(true);

    vm.prank(owner);
    hub.setLastRound(true);
    assertTrue(hub.lastRoundLocked());
  }

  function test_UpdateBasePrice() public {
    uint256 roundId = _startRoundAsOwner();
    uint256 newPrice = MAX_PRICE_BUFFER;

    vm.expectEmit(true, false, false, false);
    emit BasePriceUpdated(roundId, newPrice);

    vm.prank(owner);
    hub.updateBasePrice(roundId, newPrice);

    ButtonHub.RoundConfig memory config = hub.getRoundConfig(roundId);
    assertEq(config.basePrice, newPrice);
  }

  function test_UpdateBasePrice_RevertsWhenFinalized() public {
    uint256 roundId = _startRoundAsOwner();
    _approveAndPlay(player1, roundId, MAX_PRICE_BUFFER);
    vm.warp(block.timestamp + ROUND_DURATION + 1);
    vm.prank(player2);
    hub.finalize(roundId);

    vm.prank(owner);
    vm.expectRevert(ButtonHub.RoundAlreadyFinalized.selector);
    hub.updateBasePrice(roundId, MAX_PRICE_BUFFER);
  }

  function test_SetDefaultToken() public {
    MockERC20 newToken = new MockERC20("New USDC", "USDC", 6);

    vm.expectEmit(false, false, false, true);
    emit DefaultTokenUpdated(address(newToken));

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
  }

  function test_GetCurrentPrice() public {
    uint256 roundId = _startRoundAsOwner();
    assertEq(hub.getCurrentPrice(roundId), BASE_PRICE);

    vm.prank(owner);
    hub.updateBasePrice(roundId, MAX_PRICE_BUFFER);
    assertEq(hub.getCurrentPrice(roundId), MAX_PRICE_BUFFER);
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

    _approveAndPlay(player1, roundId, MAX_PRICE_BUFFER);
    uint256 expectedFee = BASE_PRICE * FEE_BPS / 10000;
    assertEq(hub.getFeeEscrow(roundId), expectedFee);
  }

  function test_GetNextStartTime() public {
    assertEq(hub.getNextStartTime(), 0);

    uint256 roundId = _startRoundAsOwner();
    _approveAndPlay(player1, roundId, MAX_PRICE_BUFFER);
    vm.warp(block.timestamp + ROUND_DURATION + 1);
    vm.prank(player1);
    hub.finalize(roundId);

    assertEq(hub.getNextStartTime(), block.timestamp + COOLDOWN);
  }

  function test_GetLatestRoundId() public {
    assertEq(hub.getLatestRoundId(), 0);

    uint256 roundId = _startRoundAsOwner();
    assertEq(hub.getLatestRoundId(), roundId);
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

