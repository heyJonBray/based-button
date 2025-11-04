# Based Button — Game Spec

Version: 1.0 (Draft)
Date: 2025-11-04

## 1. Executive Summary

Based Button is an onchain, last-deposit-wins game. Each play costs a fixed amount (default: 1 USDC). A portion of each play feeds the pot (e.g., 90%), and the rest goes to the dev/treasury (10–20%). Each play resets the timer; if no one plays before the deadline, the last player wins the pot. The system is round-based, supports multiple tokens, bonding curves, optional retroactive rewards, and sponsor vault prizes.

## 2. Terminology

- Play: A user action to press the Button by paying the required token amount.
- Round: Self-contained game instance with immutable parameters once started.
- Pot: Accumulated assets available to the winner at round end.
- Dev Fee: Percentage of each play directed to a designated dev/treasury.
- Treasury Split: Optional split to a project treasury or split contract.
- Winner: Last address to successfully play before timer expiration.
- Timer: Countdown measured in seconds; resets on each play.
- Game Token: ERC-20 token used for play (e.g., USDC).
- Factory: Contract that deploys parameterized ButtonGame clones.
- Hub: Central controller offering per-token rounds via registry and round IDs.

## 3. Goals and Non-Goals

### Goals

- Simple, fun rounds with transparent rules and payouts.
- Configurable token, pricing, and fee parameters.
- Composable architecture (Hub or Factory) for third-party launches.
- Gas-efficient, secure state updates and payouts.
- Clean round resets and strong event indexing for analytics.

### Non-Goals

- Not a regulated lottery.
- Not an AMM or lending protocol.
- Not offchain-timed; onchain timestamps are the source of truth.

## 4. Core Game Design

### 4.1 Mechanics

- Each play charges `currentPrice`.
- Split play amount across pot and fees (dev/treasury).
- On play:
  - Update `currentWinner = msg.sender`.
  - Reset `deadline = now + roundDuration`.
  - Increment play count and adjust price if using a curve.

### 4.2 Timing and Resolution

- Use `block.timestamp` for deadlines.
- `roundDuration`: recommended 240 seconds (configurable).
- Anyone can call `finalize()` after expiry; winner can call `claim()` if exposed.
- Plays are rejected after expiry.

### 4.3 Pricing Models

- Fixed: `price = basePrice`.
- Cliff curve: Increase by small increments at play-count cliffs.
- Cap maximum markup (e.g., 25%) to avoid runaway costs.
- Parameters:
  - `basePrice`, `cliffSize`, `incrementBpsPerCliff`, `maxMarkupBps`.

### 4.4 Fees and Splits

- `devFeeBps` = 1000–2000 (10–20%).
- `treasuryFeeBps` optional.
- Ensure fees ≤ 10000 bps; remainder goes to pot.

### 4.5 Free Plays and Promotions

- Early wallets can get a free play via Merkle allowlist or signed vouchers.
- Free plays reset timer and update winner.
- Free play pot contribution can be 0 or sponsor-funded.

### 4.6 Retroactive Rewards (Optional)

- Winner gets majority; retro pool distributes to previous participants.
- Use last-N inline payouts for gas control and/or Merkle claims for the rest.
- Geometric decay or flat-per-unique-wallet options.

### 4.7 Additional Prizes (Vaults)

- Sponsors can add ERC-20/721/1155 prizes to a round.
- Vault is paid at finalize to winner or split by retro rules.

### 4.8 Round Lifecycle

States:
- NotStarted → Active → Ended → Finalized → Archived

Transitions:
- `startRound`: sets parameters and initial deadline.
- `play`: updates pot, fees, winner, deadline.
- `finalize`: transfers pot, distributes prizes/retro, locks round.

## 5. Multi-Token and Third-Party Launch

- Hub: multiple rounds per token via a central contract.
- Factory: deploy minimal proxies per project/token for isolation.
- Hybrid: canonical USDC on Hub; partner-branded instances via Factory.

## 6. UX Notes

- Approve or permit flows for ERC-20.
- Show live countdown, current pot, and projected deadline.
- Leaderboards: wins, total plays, total winnings per address.
- Create-round wizard with safety rails.
