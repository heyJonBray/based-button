# Parameters & Economics

## 1. Defaults (USDC)

- `basePrice`: 1 USDC
- `roundDuration`: 10m
- `cooldownSeconds`: 0 (start next round immediately)
- `feeBps`: 1000 (10%) routed to dev/treasury vault
- `pricingModel`: fixed
- `potSeed`: optional (0–100 USDC)

## 2. Per-Play Split Examples

- 1 USDC play, 10% fee:
  - Pot: 0.90 USDC
  - Fee vault: 0.10 USDC

- 1 USDC play, 20% fee:
  - Pot: 0.80 USDC
  - Fee vault: 0.20 USDC

Ensure `feeBps ≤ 10000`.

## 3. Future: Bonding Curve

Cliff model:
- Params: `cliffSize`, `incrementBpsPerCliff`, `maxMarkupBps`.
- Price:
  - `markupBps = (plays / cliffSize) * incrementBpsPerCliff`
  - `markupBps = min(markupBps, maxMarkupBps)`
  - `price = basePrice * (10000 + markupBps) / 10000`

Cap max price growth (e.g., 25%) for UX and fairness.

## 4. Future: Retro Rewards

- Retro pool: X% of pot at finalize (e.g., 10–30%).
- Distribution:
  - Inline last-N with geometric decay (gas-bounded).
  - Merkle claims for broader sets.
- Winner share typically ≥70–90%.

## 5. Future: Prize Vaults

- Sponsor-funded ERC-20/721/1155.
- Distributed at finalize.
- Use safe transfer hooks and events for offchain display.
