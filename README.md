# Based Button

An onchain, last-deposit-wins button game with round-based lifecycle and multi-token support. Default UX uses USDC at $1 per play with a 90% pot and 10–20% dev/treasury fees. Supports fixed pricing or capped bonding curves, optional retroactive rewards, and prize vaults. Projects can launch their own rounds via a Hub or Factory.

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
- 90% goes to the pot, 10–20% to dev/treasury.
- Rounds finalize on expiry; payouts are automatic and deterministic.
- Launch your own round with your token via a central Hub or a Factory.

## Commands

- Start chain: `./scripts/anvil.sh`
- Build contracts: `bun -C packages/contracts run build`
- Test contracts: `bun -C packages/contracts run test`
- Run mini-app: `bun -C apps/web dev`
