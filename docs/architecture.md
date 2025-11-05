# Contract Architecture

## 1. Components

- ButtonHub:
  - Manages sequential rounds for a single token and enforces cooldowns.
  - Stores per-round configuration/state and escrows fees until withdrawn.
  - Exposes `startRound`, `play`, `finalize`, `withdrawFees`.
- ButtonGameFactory:
  - Deploys minimal proxies (EIP-1167) for per-project instances (post-MVP).
- Libraries:
  - Pricing library (fixed pricing today, room for curves later).
  - Safe token ops (OpenZeppelin SafeERC20).

## 2. Data Model (Hub)

Separate immutable config from mutable state for clarity and cheaper writes.

```text
RoundConfig {
  address token;            // ERC-20 used for plays
  uint256 basePrice;        // token units, e.g., USDC 6 decimals
  uint64  roundDuration;    // seconds per extension
  uint32  cooldownSeconds;  // min delay before next round
  uint16  feeBps;           // dev/treasury fee in basis points
  address feeRecipient;     // withdrawer of accrued fees
  uint8   pricingModel;     // 0 = fixed (MVP)
  bytes   pricingData;      // reserved for future models
}

RoundState {
  uint256 roundId;          // globally unique round identifier
  uint64  startTime;
  uint64  deadline;
  uint64  endTime;          // set on finalize
  uint64  nextStartTime;    // endTime + cooldownSeconds
  address currentWinner;
  uint256 potBalance;       // assets available to winner
  uint256 feeEscrow;        // accrued fees awaiting withdrawal
  uint256 plays;
  bool    active;           // true between startRound and finalize
  bool    finalized;        // true once finalize executed
}
```

Supporting storage helpers:

- `mapping(uint256 => RoundConfig) roundConfig`
- `mapping(uint256 => RoundState) roundState`
- `uint256 latestRoundId` - tracks the most recent round for cooldown enforcement

## 3. Sequential Rounds & Cooldowns

- The contract manages one round at a time for a single token.
- `startRound` checks the latest round is finalized and `block.timestamp ≥ nextStartTime`.
- `finalize` stamps `nextStartTime = block.timestamp + cooldownSeconds` and flips `active`/`finalized` flags.
- Default `cooldownSeconds = 0`, enabling immediate restarts while preserving hook for throttling.
