# Deployment Plan

## Phase 1: Canonical USDC MVP

- Network: Base
- Params: 1 USDC per play, 10% fee vault, fixed price, 5m duration (can be changed by admin)
- `cooldownSeconds = 0` so rounds can restart immediately after finalize
- Seed pot (optional)
- Fee recipient withdraws via `withdrawFees` on demand (multisig recommended)

## Phase 2: Create-Your-Own Rounds

- Enable permissioned or permissionless `startRound`
- Fee caps and token allowlist
- Leaderboards and round explorer
- Subgraph indexing

## Ops

- Multisig admin + timelock
- Potentially route through split contract
- Monitoring and alerts
- Public docs and risk disclosures
