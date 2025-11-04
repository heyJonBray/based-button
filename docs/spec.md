# Based Button — Game Spec

Version: 1.0 (Draft)
Date: 2025-11-04

## 1. Executive Summary

Based Button is an onchain, last-deposit-wins game. Each play costs a fixed amount (default: 1 USDC). A portion of each play feeds the pot (e.g., 90%), and the rest accrues to the dev fee vault (generally 10–20%). Each play resets the timer; if no one plays before the deadline, the last player wins the pot. The system is round-based and Hub-driven so sequential rounds can be launched per token as soon as the prior round is finalized. Advanced mechanics like bonding curves, retro rewards, and sponsor vault prizes are tracked as post-MVP enhancements.

## 2. Terminology

- Play: A user action to press the Button by paying the required token amount.
- Round: Self-contained game instance with immutable parameters once started.
- Pot: Accumulated assets available to the winner at round end.
- Dev Fee: Percentage of each play directed to a designated dev/treasury.
- Fee Vault: Escrow of accumulated fees for the dev/treasury.
- Winner: Last address to successfully play before timer expiration.
- Timer: Countdown measured in seconds; resets on each play.
- Game Token: ERC-20 token used for play (e.g., USDC).
- Factory: Contract that deploys parameterized ButtonGame clones.
- Hub: Central controller offering per-token rounds via registry and round IDs.

## 3. Scope

### 3.1 MVP Scope

- Fixed-price rounds with a single ERC-20 token (USDC default).
- Single fee recipient (dev/treasury) with on-demand withdrawals.
- Hub-coordinated sequential rounds with optional cooldowns.
- Finalize transfers the entire pot to the winning player.
- Events and read helpers for analytics, countdown, and pricing.

### 3.2 Deferred for Later Iterations

- Retroactive rewards or split payouts to prior players.
- Sponsor vault prizes or NFT/1155 rewards.
- Multi-recipient fee splits and referral rebates.
- Complex pricing/bonding curves beyond fixed price.
- Free play promotions and Merkle voucher plumbing.

## 4. Goals and Non-Goals

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

## 5. Core Game Design

### 5.1 Mechanics

- Each play charges `currentPrice`.
- Split play amount across pot and fee vault (dev/treasury).
- On play:
  - Update `currentWinner = msg.sender`.
  - Reset `deadline = now + roundDuration`.
  - Increment play count; pricing stays fixed in MVP but hooks remain for future curves.

### 5.2 Timing and Resolution

- Use `block.timestamp` for deadlines.
- `roundDuration`: recommended 240 seconds (configurable).
- Anyone can call `finalize()` after expiry; winner can call `claim()` if exposed.
- Plays are rejected after expiry.

### 5.3 Pricing Models

- MVP: fixed pricing (`price = basePrice`).
- Future: cliff curves or other capped bonding curves once spec'd.

### 5.4 Fees and Splits

- `feeBps` = 1000–2000 (10–20% typical) routed to a single fee recipient.
- Fee amount accrues on the round and can be withdrawn by the fee recipient anytime via `withdrawFees`.
- Ensure `feeBps ≤ 10000`; remainder goes to pot.
- Multi-recipient splits are future work.

### 5.5 Free Plays and Promotions (Future)

- Track as backlog; MVP excludes free plays.
- When implemented, free plays should reset the timer and may require sponsor-funded pot contributions.

### 5.6 Payouts

- `finalize` transfers the full pot to `currentWinner`.
- Fee recipient can call `withdrawFees(roundId, amount, to)` at any time after fees accrue.
- Contract retains fees until withdrawn, enabling batched dev payouts.

### 5.7 Round Lifecycle

States:
- NotStarted → Active → Ended → Finalized → Ready

Transitions:
- `startRound`: sets parameters and initial deadline.
- `play`: updates pot, fees, winner, deadline.
- `finalize`: transfers pot to the winner, marks round finalized, and records cooldown unlock time.
- `startNextRound`: allowed once prior round is `Ready` and optional cooldown has elapsed.

Cooldown:
- `cooldownSeconds` defaults to 0 (start immediately) but can be set per round.
- On finalize, `nextStartTime = endTime + cooldownSeconds`.
- Hub rejects `startRound` if attempting to reuse the same series before `nextStartTime`.
- `Ready` = `finalized` and `block.timestamp ≥ nextStartTime`.

## 6. Multi-Token and Third-Party Launch

- Hub: multiple sequential rounds per token/series via a central contract.
- Factory: deploy minimal proxies per project/token for isolation (post-MVP).
- Hybrid: canonical USDC on Hub; partner-branded instances via Factory.

## 7. UX Notes

- Approve or permit flows for ERC-20.
- Show live countdown, current pot, and projected deadline.
- Leaderboards: wins, total plays, total winnings per address.
- Create-round wizard with safety rails.
