# Local Testing with Anvil

Complete guide for testing the ButtonHub contract locally using Anvil.

## Quick Start (5 Steps)

```bash
# 1. Start Anvil (in one terminal)
npm run anvil:reset

# 2. Create .env.local (in packages/contracts/)
cat > .env.local << EOF
PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
INITIAL_OWNER=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
FEE_RECIPIENT=0x70997970C51812dc3A010C7d01b50e0d17dc79C8
USDC_ADDRESS=0x0000000000000000000000000000000000000000
HUB_ADDRESS=0x0000000000000000000000000000000000000000
EOF

# 3. Deploy Mock USDC
npm run deploy:local:mock
# Copy the USDC_ADDRESS from output and update .env.local

# 4. Deploy ButtonHub
npm run deploy:local
# Copy the HUB_ADDRESS from output and update .env.local

# 5. Start a round
npm run start-round:local
```

## Prerequisites

1. Make sure Foundry is installed: `forge --version`
2. Navigate to the contracts directory: `cd packages/contracts`

## Step 1: Start Anvil Node

Start Anvil with deterministic accounts (for repeatable testing):

```bash
# In one terminal
npm run anvil
# OR
anvil
```

**Better: Use deterministic accounts for testing:**

```bash
anvil --host 0.0.0.0 --port 8545 \
  --mnemonic "test test test test test test test test test test test junk" \
  --steps-tracing
```

This will give you:
- **10 accounts** with 10,000 ETH each
- **Private keys** printed in the output
- **RPC URL**: `http://127.0.0.1:8545` or `http://localhost:8545`

**Save the output!** You'll need:
- Account addresses (especially the first one: `0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266`)
- Private keys (especially the first one: `0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80`)

## Step 2: Create Local Environment File

Create a `.env.local` file in `packages/contracts/`:

```bash
# Copy from Anvil output - first account is usually the deployer
PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

# Use the first Anvil account as owner
INITIAL_OWNER=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266

# Anvil RPC URL
ANVIL_RPC_URL=http://127.0.0.1:8545

# Use the second account for fee recipient
FEE_RECIPIENT=0x70997970C51812dc3A010C7d01b50e0d17dc79C8

# We'll deploy a mock USDC token first, then use its address
USDC_ADDRESS=0x0000000000000000000000000000000000000000
```

## Step 3: Deploy Mock USDC Token (Optional but Recommended)

Since your contract needs a USDC address, deploy a mock ERC20 first:

```bash
# Source the local env
source .env.local

# Deploy MockERC20 (you have this in test/mocks/MockERC20.sol)
forge script script/DeployMockUSDC.s.sol \
  --rpc-url http://127.0.0.1:8545 \
  --broadcast \
  --private-key $PRIVATE_KEY
```

**OR** create a quick deploy script:

```bash
# Quick deploy using forge create
forge create test/mocks/MockERC20.sol:MockERC20 \
  --rpc-url http://127.0.0.1:8545 \
  --private-key $PRIVATE_KEY \
  --constructor-args "Mock USDC" "USDC" 6
```

**Update `.env.local`** with the deployed token address:
```bash
USDC_ADDRESS=<deployed_token_address>
```

## Step 4: Deploy ButtonHub Contract

```bash
# Make sure .env.local is sourced
source .env.local

# Deploy
forge script script/Deploy.s.sol \
  --rpc-url http://127.0.0.1:8545 \
  --broadcast \
  --private-key $PRIVATE_KEY
```

**Save the deployed contract address!** Update `.env.local`:
```bash
HUB_ADDRESS=<deployed_hub_address>
```

## Step 5: Test All Scripts

### 5.1 Start a Round (Owner)

```bash
source .env.local

forge script script/StartRound.s.sol \
  --rpc-url http://127.0.0.1:8545 \
  --broadcast \
  --private-key $PRIVATE_KEY
```

**With custom parameters:**
```bash
source .env.local

ROUND_DURATION=300 \
COOLDOWN_SECONDS=60 \
FEE_BPS=1000 \
BASE_PRICE=1000000 \
POT_SEED=5000000 \
forge script script/StartRound.s.sol \
  --rpc-url http://127.0.0.1:8545 \
  --broadcast \
  --private-key $PRIVATE_KEY
```

### 5.2 Enable Permissionless Round Start

```bash
source .env.local

PERMISSIONLESS_ROUND_ENABLED=true \
forge script script/SetPermissionlessRoundStart.s.sol \
  --rpc-url http://127.0.0.1:8545 \
  --broadcast \
  --private-key $PRIVATE_KEY
```

### 5.3 Update Base Price

```bash
source .env.local

ROUND_ID=1 \
NEW_PRICE=2000000 \
forge script script/UpdateBasePrice.s.sol \
  --rpc-url http://127.0.0.1:8545 \
  --broadcast \
  --private-key $PRIVATE_KEY
```

### 5.4 Set Default Token

```bash
source .env.local

DEFAULT_TOKEN=$USDC_ADDRESS \
forge script script/SetDefaultToken.s.sol \
  --rpc-url http://127.0.0.1:8545 \
  --broadcast \
  --private-key $PRIVATE_KEY
```

### 5.5 Lock Last Round (for migration testing)

```bash
source .env.local

CONTRACT_LOCKED=true \
forge script script/SetLastRound.s.sol \
  --rpc-url http://127.0.0.1:8545 \
  --broadcast \
  --private-key $PRIVATE_KEY
```

## Step 6: Interact with Contract (Using Cast)

### Check Round State

```bash
source .env.local

# Get round config
cast call $HUB_ADDRESS "getRoundConfig(uint256)" 1 --rpc-url http://127.0.0.1:8545

# Get round state
cast call $HUB_ADDRESS "getRoundState(uint256)" 1 --rpc-url http://127.0.0.1:8545

# Get current price
cast call $HUB_ADDRESS "getCurrentPrice(uint256)" 1 --rpc-url http://127.0.0.1:8545

# Get time remaining
cast call $HUB_ADDRESS "getTimeRemaining(uint256)" 1 --rpc-url http://127.0.0.1:8545
```

### Play the Button (Using a different account)

```bash
source .env.local

# Get second account from Anvil (or use your own)
PLAYER_KEY=0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d
PLAYER_ADDRESS=0x70997970C51812dc3A010C7d01b50e0d17dc79C8

# Approve USDC first
cast send $USDC_ADDRESS \
  "approve(address,uint256)" \
  $HUB_ADDRESS \
  1000000000 \
  --rpc-url http://127.0.0.1:8545 \
  --private-key $PLAYER_KEY

# Play the button
cast send $HUB_ADDRESS \
  "play(uint256,uint256)" \
  1 \
  2000000 \
  --rpc-url http://127.0.0.1:8545 \
  --private-key $PLAYER_KEY
```

### Finalize Round

```bash
source .env.local

# Fast forward time (use Anvil's --steps-tracing or cast)
cast rpc anvil_increaseTime 700 --rpc-url http://127.0.0.1:8545

# Finalize
cast send $HUB_ADDRESS \
  "finalize(uint256)" \
  1 \
  --rpc-url http://127.0.0.1:8545 \
  --private-key $PLAYER_KEY
```

## Step 7: Add NPM Scripts for Local Testing (Optional)

Add to `package.json`:

```json
"deploy:local": "bash -lc 'source .env.local && forge script script/Deploy.s.sol --rpc-url http://127.0.0.1:8545 --broadcast'",
"start-round:local": "bash -lc 'source .env.local && forge script script/StartRound.s.sol --rpc-url http://127.0.0.1:8545 --broadcast'",
"anvil:reset": "anvil --host 0.0.0.0 --port 8545 --mnemonic 'test test test test test test test test test test test junk' --steps-tracing"
```

## Quick Reference: Anvil Accounts

With the default mnemonic, these are the first 3 accounts:

| Index | Address | Private Key |
|-------|---------|-------------|
| 0 | `0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266` | `0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80` |
| 1 | `0x70997970C51812dc3A010C7d01b50e0d17dc79C8` | `0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d` |
| 2 | `0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC` | `0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a` |

## Troubleshooting

### "Insufficient funds"

- Make sure you're using Anvil accounts (they have 10,000 ETH each)
- Check you're using the correct private key

### "Contract not found"

- Make sure Anvil is running
- Check the RPC URL is correct
- Verify the contract was deployed

### "Invalid token address"

- Deploy a mock USDC token first
- Update `.env.local` with the correct address

### "Time not advancing"

- Use `cast rpc anvil_increaseTime <seconds>` to fast forward
- Or restart Anvil with `anvil --block-time 1` for faster blocks
