# Based Button

An onchain, last-deposit-wins button game with round-based lifecycle and multi-token support. Default UX uses USDC at $1 per play with a 80-90% pot and 10–20% dev/treasury fees. Supports fixed pricing, optional pool seeding, variable round duration decay, and permissionless triggering of new games (when enabled by owner). Eventually, token projects will be able to launch their own rounds via a factory, and enable retroactive reward strategies.

- Status: Draft v1.0
- Author: Jon Bray
- Date: 2025-11-04

## Quick Links

- [Game Spec](./docs/spec.md)
- [Contract Architecture](./docs/architecture.md)
- [Parameters & Economics](./docs/economics.md)
- [Security & Risks](./docs/security.md)
- [Deployment Plan](./docs/deployment.md)
- [API & Events](./docs/api.md)
- [Variants & Roadmap](./docs/roadmap.md)
- [Testing Strategy](./docs/testing.md)
- [Compliance Notes](./docs/compliance.md)

## TL;DR

- Last to press the button before the timer expires wins the pot.
- Each play costs a fixed token amount (default 1 USDC).
- 80-90% goes to the pot, 10–20% to dev/treasury.
- Rounds finalize on expiry; payouts are automatic and deterministic.

### Future Plans

- Launch your own round with your token via a central factory.
- Retroactive pot prizes (spread prize pool across last N players).

## How It Works

Each round is orchestrated by the `ButtonHub` contract. When a new round starts, the Hub holds the pot, tracks the active timer, and records each play. Pressing the button transfers the play price, extends the deadline by the configured round duration, and records the new leading player. Once the timer expires, anyone can finalize the round to pay the pot to the last player and queue the cooldown before the next round.

Round durations can automatically shorten over time using the Hub's duration reduction schedule. You set three parameters before the first round: how many seconds to subtract (`reduceBySeconds`), how many rounds between reductions (`everyNRound`), and the minimum duration (`minDuration`). The contract applies the schedule on the next round after the requisite number of plays, never dropping below the minimum.

**Example:** Let's say we want to start with 60-minute rounds to give the game a chance to build momentum, and want to eventually drop down to 10-minuteute rounds for quicker play.

We decide on a reduction of 15 seconds every 10 rounds until we reach the target duration of 10 minutes.

Starting from 60-minute rounds (3600-second) and reducing by 15-second every 10 rounds means you need 200 reductions to reach 10-minute rounds (600-second). At one reduction per 10 rounds, the 2001st round is the first to run at the 600-secondecond duration. Every round after that will continue to run at the 600-secondecond duration.

## Commands

- Start chain: `./scripts/anvil.sh`
- Build contracts: `bun -C packages/contracts run build`
- Test contracts: `bun -C packages/contracts run test`
- Run mini-app: `bun -C apps/web dev`
