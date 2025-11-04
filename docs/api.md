# Contract API & Events

## 1. Read Methods

- `getRound(roundId)`: round summary.
- `getCurrentPrice(roundId)`: price if played now.
- `getTimeRemaining(roundId)`: seconds until deadline (0 if ended).

## 2. Write Methods

- `startRound(params) → roundId`
  - Validates fee bounds, token allowlist (if any), and seeds pot if provided.
- `play(roundId, maxPrice)`
  - Pulls tokens, splits fees, updates winner, resets deadline.
- `finalize(roundId)`
  - After expiry, pays pot and distributes vault/retro.

## 3. Events

- `RoundStarted(token, roundId, params, startTime, deadline)`
- `Play(roundId, player, pricePaid, potAfter, newDeadline)`
- `RoundEnded(roundId, winner, endTime)`
- `Finalized(roundId, winner, potPaid, devPaid, treasuryPaid)`
- `RetroClaim(roundId, player, amount)`
- `VaultAdded(roundId, asset, amountOrId)`

## 4. Example Pseudocode

```solidity
function play(uint256 id, uint256 maxPrice) external nonReentrant {
  Round storage r = rounds[id];
  require(!r.finalized, "finalized");
  require(block.timestamp <= r.deadline, "ended");

  uint256 price = currentPrice(r);
  require(price <= maxPrice, "slippage");

  uint256 beforeBal = IERC20(r.token).balanceOf(address(this));
  IERC20(r.token).safeTransferFrom(msg.sender, address(this), price);
  uint256 received = IERC20(r.token).balanceOf(address(this)) - beforeBal;

  uint256 devAmt = (received * r.devFeeBps) / 10000;
  uint256 treasAmt = (received * r.treasuryFeeBps) / 10000;
  uint256 potAmt = received - devAmt - treasAmt;

  r.pot += potAmt;
  if (devAmt > 0) IERC20(r.token).safeTransfer(r.dev, devAmt);
  if (treasAmt > 0) IERC20(r.token).safeTransfer(r.treasury, treasAmt);

  r.plays += 1;
  r.currentWinner = msg.sender;
  r.deadline = uint64(block.timestamp + r.roundDuration);

  emit Play(id, msg.sender, received, r.pot, r.deadline);
}

function finalize(uint256 id) external nonReentrant {
  Round storage r = rounds[id];
  require(!r.finalized, "finalized");
  require(block.timestamp > r.deadline, "not ended");

  r.finalized = true;
  r.endTime = uint64(block.timestamp);

  address winner = r.currentWinner;
  uint256 potAmt = r.pot;

  IERC20(r.token).safeTransfer(winner, potAmt);

  emit RoundEnded(id, winner, r.endTime);
  emit Finalized(id, winner, potAmt, 0, 0);
}
