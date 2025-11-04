# Contract Architecture

## 1. Components

- ButtonHub (preferred MVP):
  - Manages multiple rounds across tokens.
  - Stores per-round configuration and state.
- ButtonGameFactory (optional):
  - Deploys minimal proxies (EIP-1167) for per-project instances.
- Libraries:
  - Pricing library (fixed, cliff).
  - Safe token ops (OpenZeppelin SafeERC20).

## 2. Data Model (Hub)

```text
Round {
  address token;
  uint256 roundId;
  uint256 basePrice;       // token units, e.g., USDC 6 decimals
  uint64   roundDuration;  // seconds
  uint64   deadline;       // epoch seconds
  uint64   startTime;
  uint64   endTime;        // set on finalize
  uint16   devFeeBps;
  uint16   treasuryFeeBps;
  address  dev;
  address  treasury;
  address  currentWinner;
  uint256  pot;            // net pot available to winner/retro
  uint256  plays;
  uint8    pricingModel;   // 0 fixed, 1 cliff
  uint256  priceState;     // model-specific counter (e.g., plays)
  bytes    pricingData;    // abi-encoded curve params
  bool     ended;
  bool     finalized;
  bytes32  retroConfigHash;
  bytes32  vaultId;
}
