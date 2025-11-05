# ButtonHub Scripts

Scripts for interacting with the ButtonHub contract.

## Common Setup

All scripts require the `HUB_ADDRESS` environment variable:

```bash
export HUB_ADDRESS=0x...
```

## Scripts

### StartRound.s.sol

Starts a new round on the ButtonHub.

**Required Environment Variables:**
- `HUB_ADDRESS` - Address of the deployed ButtonHub contract
- `FEE_RECIPIENT` - Address that will receive fees

**Optional Environment Variables (with defaults):**
- `ROUND_TOKEN` - Token address (default: address(0), uses hub.defaultToken())
- `ROUND_DURATION` - Round duration in seconds (default: 600 = 10 minutes)
- `COOLDOWN_SECONDS` - Cooldown before next round (default: 0 = immediate)
- `FEE_BPS` - Fee in basis points (default: 1000 = 10%)
- `BASE_PRICE` - Base price per play (default: 1000000 = 1 USDC with 6 decimals)
- `POT_SEED` - Initial pot seed amount (default: 0 = no seed)

**Example:**
```bash
# Basic round start (uses defaults)
HUB_ADDRESS=0x... FEE_RECIPIENT=0x... forge script script/StartRound.s.sol --rpc-url base_sepolia --broadcast

# Custom round with pot seed
HUB_ADDRESS=0x... FEE_RECIPIENT=0x... BASE_PRICE=2000000 ROUND_DURATION=300 POT_SEED=10000000 \
  forge script script/StartRound.s.sol --rpc-url base_sepolia --broadcast
```

### SetPermissionlessRoundStart.s.sol

Enables or disables permissionless round starts.

**Required Environment Variables:**
- `HUB_ADDRESS` - Address of the deployed ButtonHub contract

**Optional Environment Variables:**
- `PERMISSIONLESS_ROUND_ENABLED` - Set to true to enable, false to disable (default: true)

**Example:**
```bash
# Enable permissionless starts
HUB_ADDRESS=0x... forge script script/SetPermissionlessRoundStart.s.sol --rpc-url base_sepolia --broadcast

# Disable permissionless starts
HUB_ADDRESS=0x... PERMISSIONLESS_ROUND_ENABLED=false forge script script/SetPermissionlessRoundStart.s.sol --rpc-url base_sepolia --broadcast
```

### SetLastRound.s.sol

Locks the contract to prevent new rounds from starting (useful for migration).

**Required Environment Variables:**
- `HUB_ADDRESS` - Address of the deployed ButtonHub contract

**Optional Environment Variables:**
- `CONTRACT_LOCKED` - Set to true to lock, false to unlock (default: true)

**Example:**
```bash
# Lock contract (prevent new rounds)
HUB_ADDRESS=0x... forge script script/SetLastRound.s.sol --rpc-url base_sepolia --broadcast

# Unlock contract
HUB_ADDRESS=0x... CONTRACT_LOCKED=false forge script script/SetLastRound.s.sol --rpc-url base_sepolia --broadcast
```

### SetDefaultToken.s.sol

Updates the default token address used when starting rounds.

**Required Environment Variables:**
- `HUB_ADDRESS` - Address of the deployed ButtonHub contract
- `DEFAULT_TOKEN` - New default token address

**Example:**
```bash
# Switch to mainnet USDC
HUB_ADDRESS=0x... DEFAULT_TOKEN=0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913 \
  forge script script/SetDefaultToken.s.sol --rpc-url base --broadcast

# Switch to testnet USDC
HUB_ADDRESS=0x... DEFAULT_TOKEN=0x036CbD53842c5426634e7929541eC2318f3dCF7e \
  forge script script/SetDefaultToken.s.sol --rpc-url base_sepolia --broadcast
```

### UpdateBasePrice.s.sol

Updates the base price for an active round.

**Required Environment Variables:**
- `HUB_ADDRESS` - Address of the deployed ButtonHub contract
- `ROUND_ID` - ID of the round to update
- `NEW_PRICE` - New base price

**Example:**
```bash
# Update round 1 to 2 USDC per play
HUB_ADDRESS=0x... ROUND_ID=1 NEW_PRICE=2000000 \
  forge script script/UpdateBasePrice.s.sol --rpc-url base_sepolia --broadcast
```

## Usage Tips

1. **Dry Run First**: Use `--dry-run` flag to simulate without broadcasting:
   ```bash
   forge script script/StartRound.s.sol --rpc-url base_sepolia
   ```

2. **Verify Transactions**: After broadcasting, verify on block explorer

3. **Gas Estimation**: Use `--gas-estimate-multiplier` to adjust gas:
   ```bash
   forge script script/StartRound.s.sol --rpc-url base_sepolia --broadcast --gas-estimate-multiplier 200
   ```

4. **Private Key**: Set via `--private-key` or use `--ledger` for hardware wallet:
   ```bash
   forge script script/StartRound.s.sol --rpc-url base_sepolia --broadcast --private-key $PRIVATE_KEY
   ```
