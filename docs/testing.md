# Testing Strategy

## 1. Unit Tests

- Price calc: fixed and cliff models.
- Fee splits and pot accumulation.
- Deadline updates and edge cases.
- Finalization and payouts.
- Vault additions and payouts.

## 2. Property Tests

- Timer never moves backward.
- No plays accepted post-deadline.
- Sum of payouts equals pot + fees exactly.
- Price caps respected.

## 3. Fuzz Tests

- Random play sequences/durations.
- Tokens with different decimals.
- Edge-case parameters near bounds.

## 4. Integration Tests

- USDC test token on L2 testnet.
- Approve/permit flows.
- Frontend countdown drift vs onchain.
