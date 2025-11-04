// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract ButtonHub is ReentrancyGuard {
  using SafeERC20 for IERC20;

  uint256 private constant MAX_FEE_BPS = 10_000;
  uint8 internal constant PRICING_FIXED = 0;

  /// @notice Immutable parameters for a round.
  struct RoundConfig {
    address token;
    uint256 basePrice;
    uint64 roundDuration;
    uint32 cooldownSeconds;
    uint16 feeBps;
    address feeRecipient;
    uint8 pricingModel;
    bytes pricingData;
  }

  /// @notice Mutable state for a round lifecycle.
  struct RoundState {
    uint256 roundId;
    uint64 seriesId;
    uint64 startTime;
    uint64 deadline;
    uint64 endTime;
    uint64 nextStartTime;
    address currentWinner;
    uint256 potBalance;
    uint256 feeEscrow;
    uint256 plays;
    bool active;
    bool finalized;
  }

  /// @notice Parameters used when starting a new round.
  struct StartRoundParams {
    address token;
    uint64 roundDuration;
    uint32 cooldownSeconds;
    uint16 feeBps;
    address feeRecipient;
    uint8 pricingModel;
    bytes pricingData;
    uint256 basePrice;
    uint256 potSeed;
  }

  /// @notice Emitted when a new round begins.
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

  /// @notice Emitted for each successful play.
  event Play(
    uint256 indexed roundId,
    address indexed player,
    uint256 pricePaid,
    uint256 potAfter,
    uint256 feeEscrowAfter,
    uint64 newDeadline
  );

  /// @notice Emitted when a round is finalized.
  event RoundEnded(uint256 indexed roundId, address indexed winner, uint64 endTime);

  /// @notice Emitted once the pot payout is executed and cooldown scheduled.
  event Finalized(
    uint256 indexed roundId, address indexed winner, uint256 potPaid, uint64 nextStartTime
  );

  /// @notice Emitted whenever fees are withdrawn from escrow.
  event FeesWithdrawn(
    uint256 indexed roundId, address indexed recipient, uint256 amount, uint256 feeEscrowAfter
  );

  /// @notice Raised when attempting to configure an invalid fee.
  error FeeTooHigh();

  /// @notice Raised when the cooldown has not elapsed for the target series.
  error CooldownActive();

  /// @notice Raised when attempting to interact with a non-active round.
  error RoundNotActive();

  /// @notice Raised when attempting to interact with a round that has already ended.
  error RoundAlreadyFinalized();

  /// @notice Raised when a caller unauthorised for the operation attempts it.
  error Unauthorized();

  /// @notice Tracks the next round identifier.
  uint256 private nextRoundId = 1;

  mapping(uint256 => RoundConfig) internal roundConfig;
  mapping(uint256 => RoundState) internal roundState;
  mapping(uint64 => uint256) internal latestRoundIdBySeries;
  mapping(address => uint256) internal feeBalances;

  /// @notice Starts a new round for a given series.
  function startRound(uint64 seriesId, StartRoundParams calldata params)
    external
    nonReentrant
    returns (uint256 roundId)
  {
    _validateStartParams(params);

    uint256 latestRoundId = latestRoundIdBySeries[seriesId];
    if (latestRoundId != 0) {
      RoundState storage latestState = roundState[latestRoundId];
      if (!latestState.finalized || block.timestamp < latestState.nextStartTime) {
        revert CooldownActive();
      }
    }

    roundId = nextRoundId++;

    RoundConfig storage config = roundConfig[roundId];
    config.token = params.token;
    config.basePrice = params.basePrice;
    config.roundDuration = params.roundDuration;
    config.cooldownSeconds = params.cooldownSeconds;
    config.feeBps = params.feeBps;
    config.feeRecipient = params.feeRecipient;
    config.pricingModel = params.pricingModel;
    config.pricingData = params.pricingData;

    RoundState storage state = roundState[roundId];
    state.roundId = roundId;
    state.seriesId = seriesId;
    state.startTime = uint64(block.timestamp);
    state.deadline = uint64(block.timestamp + params.roundDuration);
    state.active = true;

    latestRoundIdBySeries[seriesId] = roundId;

    if (params.potSeed > 0) {
      IERC20(params.token).safeTransferFrom(msg.sender, address(this), params.potSeed);
      state.potBalance = params.potSeed;
    }

    emit RoundStarted(
      params.token,
      seriesId,
      roundId,
      state.startTime,
      state.deadline,
      params.roundDuration,
      params.cooldownSeconds,
      params.feeBps,
      params.basePrice,
      params.pricingModel
    );
  }

  /// @notice Presses the button for an active round.
  function play(uint256 roundId, uint256 maxPrice) external nonReentrant {
    RoundConfig storage config = roundConfig[roundId];
    RoundState storage state = roundState[roundId];
    if (!state.active) revert RoundNotActive();
    if (block.timestamp > state.deadline) revert RoundAlreadyFinalized();

    uint256 price = _currentPrice(config, state);
    require(price <= maxPrice, "PRICE_SLIPPAGE");

    uint256 before = IERC20(config.token).balanceOf(address(this));
    IERC20(config.token).safeTransferFrom(msg.sender, address(this), price);
    uint256 received = IERC20(config.token).balanceOf(address(this)) - before;

    uint256 fee = (received * config.feeBps) / MAX_FEE_BPS;
    uint256 potContribution = received - fee;

    state.potBalance += potContribution;
    state.feeEscrow += fee;
    state.plays += 1;
    state.currentWinner = msg.sender;
    state.deadline = uint64(block.timestamp + config.roundDuration);

    emit Play(roundId, msg.sender, received, state.potBalance, state.feeEscrow, state.deadline);
  }

  /// @notice Finalizes a round whose timer has expired, paying the pot.
  function finalize(uint256 roundId) external nonReentrant {
    RoundConfig storage config = roundConfig[roundId];
    RoundState storage state = roundState[roundId];
    if (!state.active) revert RoundNotActive();
    if (block.timestamp <= state.deadline) revert RoundAlreadyFinalized();

    state.active = false;
    state.finalized = true;
    state.endTime = uint64(block.timestamp);
    state.nextStartTime = uint64(block.timestamp + config.cooldownSeconds);

    uint256 pot = state.potBalance;
    state.potBalance = 0;

    IERC20(config.token).safeTransfer(state.currentWinner, pot);

    emit RoundEnded(roundId, state.currentWinner, state.endTime);
    emit Finalized(roundId, state.currentWinner, pot, state.nextStartTime);
  }

  /// @notice Withdraws accrued fees for a round.
  function withdrawFees(uint256 roundId, uint256 amount, address to) external nonReentrant {
    RoundConfig storage config = roundConfig[roundId];
    RoundState storage state = roundState[roundId];
    if (msg.sender != config.feeRecipient) revert Unauthorized();

    uint256 available = state.feeEscrow;
    require(amount <= available, "INSUFFICIENT_FEES");

    state.feeEscrow = available - amount;
    IERC20(config.token).safeTransfer(to, amount);

    emit FeesWithdrawn(roundId, msg.sender, amount, state.feeEscrow);
  }

  /// @notice Validates input parameters for starting a round.
  function _validateStartParams(StartRoundParams calldata params) internal pure {
    if (params.feeBps > MAX_FEE_BPS) revert FeeTooHigh();
    if (params.token == address(0) || params.feeRecipient == address(0)) {
      revert Unauthorized();
    }
    if (params.pricingModel != PRICING_FIXED) {
      revert("UNSUPPORTED_MODEL");
    }
  }

  /// @notice Computes the current price for the round (fixed pricing MVP).
  function _currentPrice(RoundConfig storage config, RoundState storage)
    internal
    view
    returns (uint256)
  {
    if (config.pricingModel == PRICING_FIXED) {
      return config.basePrice;
    }
    return config.basePrice;
  }
}
