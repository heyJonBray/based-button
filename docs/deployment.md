# Deployment Plan

## Phase 1: Canonical USDC MVP (L2)

- Network: Base
- Params: 1 USDC per play, 10% dev, fixed price, 5m duration (variable)
- No retro, no vaults initially
- Seed pot (optional)

## Phase 2: Create-Your-Own Rounds

- Enable permissioned or permissionless `startRound`
- Fee caps and token allowlist
- Leaderboards and round explorer
- Subgraph indexing

## Phase 3: Curves and Vault Prizes

- Add capped cliff pricing model
- Vault prizes (ERC-20/721/1155)

## Phase 4: Retro Rewards (Claim-Based)

- Emit Merkle roots offchain
- `claimRetro` for participants

## Ops

- Multisig admin + timelock
- Potentially route through split contract
- Monitoring and alerts
- Public docs and risk disclosures
