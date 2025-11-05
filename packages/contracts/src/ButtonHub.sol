// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

contract ButtonHub is ReentrancyGuard, Ownable {
  using SafeERC20 for IERC20;

  uint256 private constant MAX_FEE_BPS = 5_000; // 5000 bps = 50%
  uint256 private constant BPS_DIVISOR = 10_000;
  uint8 internal constant PRICING_FIXED = 0;
  uint64 private constant MAX_ROUND_DURATION = 12 hours;

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

  struct DurationReductionSchedule {
    uint64 reduceBySeconds;
    uint32 everyNRound;
    uint64 minDuration;
    uint64 initialDuration;
    bool initialDurationCaptured;
    bool configured;
  }

  bool public permissionlessRoundStart;
  bool public lastRoundLocked;
  address public defaultToken;

  constructor(address initialOwner, address gameToken) Ownable(initialOwner) {
    if (gameToken == address(0)) revert InvalidToken();
    defaultToken = gameToken;
  }

  /// @notice Emitted when a new round begins.
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

  /// @notice Emitted when the base price is updated by the owner.
  event BasePriceUpdated(uint256 indexed roundId, uint256 newPrice);

  /// @notice Emitted when the automatic duration reduction schedule changes.
  event DurationScheduleUpdated(uint64 reduceBySeconds, uint32 everyNRound, uint64 minDuration);

  /// @notice Emitted when the permissionless start flag changes.
  event PermissionlessRoundStartUpdated(bool enabled);

  /// @notice Emitted when the last round lock flag changes.
  event LastRoundLockSet(bool locked);

  /// @notice Emitted when the default token is updated.
  event DefaultTokenUpdated(address token);

  /// @notice Raised when attempting to configure an invalid fee.
  error FeeTooHigh(uint16 feeBps);

  /// @notice Raised when the cooldown has not elapsed for the target series.
  error CooldownActive(uint64 nextStartTime);

  /// @notice Raised when round creation is blocked after migration planning.
  error LastRoundLocked();

  /// @notice Raised when attempting to interact with a non-active round.
  error RoundInactive();

  /// @notice Raised when trying to play after the deadline expired.
  error RoundExpired();

  /// @notice Raised when attempting to finalize before the deadline passes.
  error RoundInProgress(uint64 deadline);

  /// @notice Raised when attempting to finalize an already settled round.
  error RoundAlreadyFinalized();

  /// @notice Raised when no winner is recorded yet for finalization.
  error NoWinner();

  /// @notice Raised when a caller is not authorized for the action.
  error NotAuthorized();

  /// @notice Raised when price exceeds the caller supplied maximum.
  error PriceSlippage(uint256 price, uint256 maxPrice);

  /// @notice Raised when attempting to withdraw more fees than accrued.
  error InsufficientFees(uint256 requested, uint256 available);

  /// @notice Raised when a zero address is supplied where not allowed.
  error InvalidAddress();

  /// @notice Raised when base price is zero.
  error InvalidBasePrice();

  /// @notice Raised when round duration is zero.
  error InvalidDuration();

  /// @notice Raised when token address is invalid.
  error InvalidToken();

  /// @notice Raised when pot seed does not match required amount.
  error PotSeedMismatch(uint256 potSeed, uint256 basePrice);

  /// @notice Raised when pricing model not supported in MVP.
  error InvalidPricingModel(uint8 model);

  /// @notice Raised when referencing a round that does not exist.
  error RoundDoesNotExist(uint256 roundId);

  /// @notice Raised when duration reduction schedule parameters are invalid.
  error InvalidDurationSchedule();

  /// @notice Raised when attempting to start a round without a configured duration schedule.
  error DurationScheduleNotConfigured();

  /// @notice Raised when attempting to modify the duration schedule after rounds have begun.
  error DurationScheduleLocked(uint256 latestRoundId);

  /// @notice Tracks the next round identifier.
  uint256 private nextRoundId = 1;

  mapping(uint256 => RoundConfig) internal roundConfig;
  mapping(uint256 => RoundState) internal roundState;
  uint256 internal latestRoundId;

  DurationReductionSchedule public durationSchedule;

  /// @notice Starts a new round.
  function startRound(StartRoundParams calldata params)
    external
    nonReentrant
    returns (uint256 roundId)
  {
    if (!durationSchedule.configured) revert DurationScheduleNotConfigured();
    if (lastRoundLocked) revert LastRoundLocked();
    if (!permissionlessRoundStart && msg.sender != owner()) revert NotAuthorized();

    address token = _validateStartParams(params);

    if (latestRoundId != 0) {
      RoundState storage latestState = roundState[latestRoundId];
      if (!latestState.finalized) {
        revert RoundInProgress(latestState.deadline);
      }
      if (block.timestamp < latestState.nextStartTime) {
        revert CooldownActive(latestState.nextStartTime);
      }
    }

    roundId = nextRoundId++;

    uint64 appliedDuration = _applyDurationSchedule(roundId, params.roundDuration);

    RoundConfig storage config = roundConfig[roundId];
    config.token = token;
    config.basePrice = params.basePrice;
    config.roundDuration = appliedDuration;
    config.cooldownSeconds = params.cooldownSeconds;
    config.feeBps = params.feeBps;
    config.feeRecipient = params.feeRecipient;
    config.pricingModel = params.pricingModel;
    config.pricingData = params.pricingData;

    RoundState storage state = roundState[roundId];
    state.roundId = roundId;
    state.startTime = uint64(block.timestamp);
    state.deadline = uint64(block.timestamp + appliedDuration);
    state.active = true;

    latestRoundId = roundId;

    IERC20(token).safeTransferFrom(msg.sender, address(this), params.potSeed);
    state.potBalance = params.potSeed;

    emit RoundStarted(
      token,
      roundId,
      state.startTime,
      state.deadline,
      appliedDuration,
      params.cooldownSeconds,
      params.feeBps,
      params.basePrice,
      params.pricingModel
    );
  }

  /// @notice Presses the button for an active round.
  function play(uint256 roundId, uint256 maxPrice) external nonReentrant {
    (RoundConfig storage config, RoundState storage state) = _requireRound(roundId);
    if (!state.active) revert RoundInactive();
    if (block.timestamp > state.deadline) revert RoundExpired();

    uint256 price = _currentPrice(config, state);
    if (price > maxPrice) revert PriceSlippage(price, maxPrice);

    uint256 before = IERC20(config.token).balanceOf(address(this));
    IERC20(config.token).safeTransferFrom(msg.sender, address(this), price);
    uint256 received = IERC20(config.token).balanceOf(address(this)) - before;

    uint256 fee = (received * config.feeBps) / BPS_DIVISOR;
    uint256 potContribution = received - fee;

    state.potBalance += potContribution;
    state.feeEscrow += fee;
    state.plays += 1;
    state.currentWinner = msg.sender;

    if (block.timestamp > type(uint64).max - config.roundDuration) {
      revert InvalidDuration();
    }
    state.deadline = uint64(block.timestamp + config.roundDuration);

    emit Play(roundId, msg.sender, received, state.potBalance, state.feeEscrow, state.deadline);
  }

  /// @notice Finalizes a round whose timer has expired, paying the pot.
  function finalize(uint256 roundId) external nonReentrant {
    (RoundConfig storage config, RoundState storage state) = _requireRound(roundId);
    if (state.finalized) revert RoundAlreadyFinalized();
    if (!state.active) revert RoundInactive();
    if (block.timestamp <= state.deadline) revert RoundInProgress(state.deadline);
    if (state.currentWinner == address(0)) revert NoWinner();

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
    (RoundConfig storage config, RoundState storage state) = _requireRound(roundId);
    if (msg.sender != config.feeRecipient) revert NotAuthorized();
    if (to == address(0)) revert InvalidAddress();

    uint256 available = state.feeEscrow;
    if (amount > available) revert InsufficientFees(amount, available);

    state.feeEscrow = available - amount;
    IERC20(config.token).safeTransfer(to, amount);

    emit FeesWithdrawn(roundId, msg.sender, amount, state.feeEscrow);
  }

  /// @notice Enables or disables permissionless round starts.
  function setPermissionlessRoundStart(bool enabled) external onlyOwner {
    permissionlessRoundStart = enabled;
    emit PermissionlessRoundStartUpdated(enabled);
  }

  /// @notice Prevents any new rounds from being created once set, easing migration.
  function setLastRound(bool locked) external onlyOwner {
    lastRoundLocked = locked;
    emit LastRoundLockSet(locked);
  }

  /// @notice Updates the default token address used when params.token is zero.
  function setDefaultToken(address newToken) external onlyOwner {
    if (newToken == address(0)) revert InvalidToken();
    defaultToken = newToken;
    emit DefaultTokenUpdated(newToken);
  }

  /// @notice Allows the owner to adjust the base price for an active round.
  function updateBasePrice(uint256 roundId, uint256 newPrice) external onlyOwner {
    if (newPrice == 0) revert InvalidBasePrice();

    (RoundConfig storage config, RoundState storage state) = _requireRound(roundId);
    if (state.finalized) revert RoundAlreadyFinalized();

    config.basePrice = newPrice;
    emit BasePriceUpdated(roundId, newPrice);
  }

  /// @notice Configures or clears the automatic round duration reduction schedule.
  function setDurationReductionSchedule(
    uint64 reduceBySeconds,
    uint32 everyNRound,
    uint64 minDuration
  ) external onlyOwner {
    if (
      reduceBySeconds == 0 || everyNRound == 0 || minDuration == 0
        || minDuration > MAX_ROUND_DURATION
    ) {
      revert InvalidDurationSchedule();
    }

    if (latestRoundId != 0) {
      revert DurationScheduleLocked(latestRoundId);
    }

    durationSchedule = DurationReductionSchedule({
      reduceBySeconds: reduceBySeconds,
      everyNRound: everyNRound,
      minDuration: minDuration,
      initialDuration: 0,
      initialDurationCaptured: false,
      configured: true
    });

    emit DurationScheduleUpdated(reduceBySeconds, everyNRound, minDuration);
  }

  /// @notice Returns immutable configuration for a round.
  function getRoundConfig(uint256 roundId) external view returns (RoundConfig memory) {
    RoundConfig memory config = roundConfig[roundId];
    if (config.token == address(0)) revert RoundDoesNotExist(roundId);
    return config;
  }

  /// @notice Returns mutable state snapshot for a round.
  function getRoundState(uint256 roundId) external view returns (RoundState memory) {
    (, RoundState storage stateStorage) = _requireRound(roundId);
    return stateStorage;
  }

  /// @notice Returns the current price required to play the given round.
  function getCurrentPrice(uint256 roundId) external view returns (uint256) {
    (RoundConfig storage config, RoundState storage state) = _requireRound(roundId);
    return _currentPrice(config, state);
  }

  /// @notice Returns remaining time before the round can be finalized.
  function getTimeRemaining(uint256 roundId) external view returns (uint256) {
    (, RoundState storage state) = _requireRound(roundId);
    if (block.timestamp >= state.deadline) return 0;
    return state.deadline - block.timestamp;
  }

  /// @notice Returns accrued fee escrow for the round.
  function getFeeEscrow(uint256 roundId) external view returns (uint256) {
    (, RoundState storage state) = _requireRound(roundId);
    return state.feeEscrow;
  }

  /// @notice Returns the next eligible start timestamp for the next round.
  function getNextStartTime() external view returns (uint256) {
    if (latestRoundId == 0) return 0;
    return roundState[latestRoundId].nextStartTime;
  }

  /// @notice Returns the latest round id (0 if none).
  function getLatestRoundId() external view returns (uint256) {
    return latestRoundId;
  }

  /// @notice Validates input parameters for starting a round.
  function _validateStartParams(StartRoundParams calldata params)
    internal
    view
    returns (address token)
  {
    if (params.feeBps > MAX_FEE_BPS) revert FeeTooHigh(params.feeBps);
    if (params.feeRecipient == address(0)) revert InvalidAddress();
    if (params.roundDuration == 0) revert InvalidDuration();
    if (params.roundDuration > MAX_ROUND_DURATION) revert InvalidDuration();
    if (params.basePrice == 0) revert InvalidBasePrice();
    if (params.potSeed != params.basePrice) {
      revert PotSeedMismatch(params.potSeed, params.basePrice);
    }

    if (block.timestamp > type(uint64).max - params.roundDuration) {
      revert InvalidDuration();
    }
    if (params.pricingModel != PRICING_FIXED) revert InvalidPricingModel(params.pricingModel);

    token = params.token == address(0) ? defaultToken : params.token;
    if (token == address(0)) revert InvalidToken();
  }

  /// @notice Computes the current price for the round.
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

  function _applyDurationSchedule(uint256 roundId, uint64 proposedDuration)
    internal
    returns (uint64)
  {
    DurationReductionSchedule storage schedule = durationSchedule;
    if (!schedule.configured) {
      return proposedDuration;
    }

    if (!schedule.initialDurationCaptured) {
      schedule.initialDuration = proposedDuration;
      schedule.initialDurationCaptured = true;
    }

    if (schedule.everyNRound == 0) {
      return proposedDuration;
    }

    if (roundId == 0) {
      return proposedDuration;
    }

    uint256 reductions = (roundId - 1) / schedule.everyNRound;
    if (reductions == 0) {
      return proposedDuration;
    }

    uint256 reductionTotal = uint256(schedule.reduceBySeconds) * reductions;
    uint64 baseDuration = schedule.initialDuration;
    uint64 targetDuration;

    if (reductionTotal >= baseDuration) {
      targetDuration = schedule.minDuration;
    } else {
      // casting to uint64 is safe; reductionTotal < baseDuration (uint64), so reductionTotal <= type(uint64).max
      // forge-lint: disable-next-line(unsafe-typecast)
      uint64 reductionTotal64 = uint64(reductionTotal);
      uint64 candidate = baseDuration - reductionTotal64;
      targetDuration = candidate < schedule.minDuration ? schedule.minDuration : candidate;
    }

    return targetDuration < proposedDuration ? targetDuration : proposedDuration;
  }

  /// @notice Ensures the round exists and returns storage references.
  function _requireRound(uint256 roundId)
    internal
    view
    returns (RoundConfig storage config, RoundState storage state)
  {
    config = roundConfig[roundId];
    if (config.token == address(0)) revert RoundDoesNotExist(roundId);
    state = roundState[roundId];
  }
}
