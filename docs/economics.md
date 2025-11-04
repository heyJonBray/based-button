# Parameters & Economics

## 1. Defaults (USDC)

- `basePrice`: 1 USDC
- `roundDuration`: 10m
- `devFeeBps`: 1000 (10%)
- `treasuryFeeBps`: 0 (can be configured)
- `pricingModel`: fixed
- `potSeed`: optional (0–100 USDC)

## 2. Per-Play Split Examples

- 1 USDC play, 10% dev:
  - Pot: 0.90 USDC
  - Dev: 0.10 USDC

- 1 USDC play, 20% dev:
  - Pot: 0.80 USDC
  - Dev: 0.20 USDC

Ensure `devFeeBps + treasuryFeeBps ≤ 10000`.

## 3. Bonding Curve

Cliff model:
- Params: `cliffSize`, `incrementBpsPerCliff`, `maxMarkupBps`.
- Price:
  - `markupBps = (plays / cliffSize) * incrementBpsPerCliff`
  - `markupBps = min(markupBps, maxMarkupBps)`
  - `price = basePrice * (10000 + markupBps) / 10000`

Cap max price growth (e.g., 25%) for UX and fairness.

## 4. Retro Rewards (Optional)

- Retro pool: X% of pot at finalize (e.g., 10–30%).
- Distribution:
  - Inline last-N with geometric decay (gas-bounded).
  - Merkle claims for broader sets.
- Winner share typically ≥70–90%.

## 5. Prize Vaults

- Sponsor-funded ERC-20/721/1155.
- Distributed at finalize.
- Use safe transfer hooks and events for offchain display.
