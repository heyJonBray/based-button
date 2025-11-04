# Security & Risks

## 1. Controls

- ReentrancyGuard on `play` and `finalize`.
- `withdrawFees` gated by fee recipient and guarded by ReentrancyGuard.
- SafeERC20 and return-value checks.
- Fee caps and parameter bounds.
- Deadline monotonicity (no backward movement).
- Slippage control with `maxPrice`.

## 2. Token Safety

- Start with allowlisted, non-rebasing, non-fee tokens (USDC).
- Handle decimals and potential fee-on-transfer behaviors.

## 3. Gas Safety

- Keep `finalize` O(1) by default.
- Retro distributions should be last-N inline or claim-based.

## 4. Admin Safety

- Multisig for admin roles.
- If upgradeable, use timelocked upgrades and publish policy.
- Pausable emergency brake.

## 5. Testing & Audits

- Unit, fuzz, and property tests.
- External review/audit before mainnet.
