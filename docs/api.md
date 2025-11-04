# Contract API & Events

## 1. Read Methods

- `getRoundConfig(roundId)`: immutable params for the round.
- `getRoundState(roundId)`: mutable state (deadline, winner, balances).
- `getCurrentPrice(roundId)`: price if played now.
- `getTimeRemaining(roundId)`: seconds until deadline (0 if ended).
- `getFeeEscrow(roundId)`: accrued fees available to withdraw.
- `getNextStartTime(seriesId)`: timestamp when the next round can be started.

## 2. Write Methods

- `startRound(seriesId, params) → roundId`
  - Validates fee bounds, token allowlist (if any), and optional pot seed.
  - Requires the prior round in the series to be finalized and past cooldown.
- `play(roundId, maxPrice)`
  - Pulls tokens, splits pot vs fee escrow, updates winner, resets deadline.
- `finalize(roundId)`
  - After expiry, transfers the pot to the winner, stamps end time, and schedules the cooldown unlock.
- `withdrawFees(roundId, amount, to)`
  - Callable by the round's fee recipient to withdraw accrued fees at any time.

## 3. Events

- `RoundStarted(token, seriesId, roundId, params, startTime, deadline)`
- `Play(roundId, player, pricePaid, potAfter, feeEscrowAfter, newDeadline)`
- `RoundEnded(roundId, winner, endTime)`
- `Finalized(roundId, winner, potPaid, nextStartTime)`
- `FeesWithdrawn(roundId, recipient, amount, feeEscrowAfter)`

## 4. Example Pseudocode

```solidity
function play(uint256 id, uint256 maxPrice) external nonReentrant {
  RoundState storage s = roundState[id];
  RoundConfig storage c = roundConfig[id];
  require(s.active, "inactive");
  require(block.timestamp <= s.deadline, "ended");

  uint256 price = currentPrice(c, s);
  require(price <= maxPrice, "slippage");

  uint256 before = IERC20(c.token).balanceOf(address(this));
  IERC20(c.token).safeTransferFrom(msg.sender, address(this), price);
  uint256 received = IERC20(c.token).balanceOf(address(this)) - before;

  uint256 feeAmt = (received * c.feeBps) / 10_000;
  uint256 potAmt = received - feeAmt;

  s.potBalance += potAmt;
  s.feeEscrow += feeAmt;
  s.plays += 1;
  s.currentWinner = msg.sender;
  s.deadline = uint64(block.timestamp + c.roundDuration);

  emit Play(id, msg.sender, received, s.potBalance, s.feeEscrow, s.deadline);
}

function finalize(uint256 id) external nonReentrant {
  RoundState storage s = roundState[id];
  RoundConfig storage c = roundConfig[id];
  require(s.active, "inactive");
  require(block.timestamp > s.deadline, "not ended");

  s.active = false;
  s.finalized = true;
  s.endTime = uint64(block.timestamp);
  s.nextStartTime = uint64(block.timestamp + c.cooldownSeconds);

  IERC20(c.token).safeTransfer(s.currentWinner, s.potBalance);

  emit RoundEnded(id, s.currentWinner, s.endTime);
  emit Finalized(id, s.currentWinner, s.potBalance, s.nextStartTime);
}

function withdrawFees(uint256 id, uint256 amount, address to) external nonReentrant {
  RoundState storage s = roundState[id];
  RoundConfig storage c = roundConfig[id];
  require(msg.sender == c.feeRecipient, "unauthorized");
  require(amount <= s.feeEscrow, "exceeds balance");

  s.feeEscrow -= amount;
  IERC20(c.token).safeTransfer(to, amount);

  emit FeesWithdrawn(id, msg.sender, amount, s.feeEscrow);
}
```
