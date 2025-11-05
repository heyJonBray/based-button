#!/usr/bin/env bash
# Interactive helper script to run Forge scripts with environment-specific configuration

set -e

ENVIRONMENTS=("local" "mainnet" "testnet")

SCRIPTS=(
  "Deploy"
  "DeployMockUSDC"
  "StartRound"
  "SetPermissionlessRoundStart"
  "SetLastRound"
  "SetDefaultToken"
  "UpdateBasePrice"
)

# Prompt for environment selection
echo "What environment?"
echo "Select from:"
for i in "${!ENVIRONMENTS[@]}"; do
  echo "  $((i+1))) ${ENVIRONMENTS[$i]}"
done
read -p "Enter choice [1-${#ENVIRONMENTS[@]}]: " env_choice

if [ -z "$env_choice" ] || [ "$env_choice" -lt 1 ] || [ "$env_choice" -gt "${#ENVIRONMENTS[@]}" ]; then
  echo "Error: Invalid choice"
  exit 1
fi

ENVIRONMENT="${ENVIRONMENTS[$((env_choice-1))]}"

# If local environment, check if anvil is needed
if [ "$ENVIRONMENT" = "local" ]; then
  echo ""
  echo "⚠️  For local environment, you need to start Anvil first!"
  echo ""
  echo "Open another terminal, navigate to this directory, and run:"
  echo "  bun run anvil:reset"
  echo ""
  read -p "Press Enter once Anvil is running in another terminal..."
fi

# Prompt for broadcast/dry-run
echo ""
echo "Broadcast or dry run?"
echo "  1) Broadcast"
echo "  2) Dry run"
read -p "Enter choice [1-2]: " broadcast_choice

if [ -z "$broadcast_choice" ] || ([ "$broadcast_choice" -ne 1 ] && [ "$broadcast_choice" -ne 2 ]); then
  echo "Error: Invalid choice"
  exit 1
fi

DRY_RUN="false"
if [ "$broadcast_choice" -eq 2 ]; then
  DRY_RUN="true"
fi

# Prompt for script selection
echo ""
echo "What script?"
echo "Select from:"
for i in "${!SCRIPTS[@]}"; do
  echo "  $((i+1))) ${SCRIPTS[$i]}"
done
read -p "Enter choice [1-${#SCRIPTS[@]}]: " script_choice

if [ -z "$script_choice" ] || [ "$script_choice" -lt 1 ] || [ "$script_choice" -gt "${#SCRIPTS[@]}" ]; then
  echo "Error: Invalid choice"
  exit 1
fi

SCRIPT_NAME="${SCRIPTS[$((script_choice-1))]}"

# Determine project root (packages/contracts)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

case "$ENVIRONMENT" in
  local)
    ENV_FILE=".env.local"
    RPC_URL="http://127.0.0.1:8545"
    if [ ! -f "${SCRIPT_DIR}/${ENV_FILE}" ]; then
      echo ""
      echo "⚠️  Warning: $ENV_FILE not found!"
      echo ""
      echo "For local testing, you need to create $ENV_FILE with:"
      echo "  PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
      echo "  INITIAL_OWNER=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"
      echo "  FEE_RECIPIENT=0x70997970C51812dc3A010C7d01b50e0d17dc79C8"
      echo "  HUB_ADDRESS=0x0000000000000000000000000000000000000000"
      echo "  USDC_ADDRESS=0x0000000000000000000000000000000000000000"
      echo ""
      echo "See LOCAL_TESTING.md for more details."
      echo ""
      read -p "Continue anyway? (y/N): " continue_choice
      if [ "$continue_choice" != "y" ] && [ "$continue_choice" != "Y" ]; then
        exit 1
      fi
    fi
    ;;
  mainnet)
    ENV_FILE=".env.base"
    RPC_URL="base"
    ;;
  testnet)
    ENV_FILE=".env.base_sepolia"
    RPC_URL="base_sepolia"
    ;;
  *)
    echo "Error: Unknown environment '$ENVIRONMENT'"
    exit 1
    ;;
esac

ENV_FILE_ABS="${SCRIPT_DIR}/${ENV_FILE}"
if [ ! -f "$ENV_FILE_ABS" ]; then
  echo ""
  echo "⚠️  Error: $ENV_FILE not found!"
  echo ""
  echo "Please create $ENV_FILE with required environment variables:"
  echo "  - PRIVATE_KEY (hex-encoded private key)"
  echo "  - HUB_ADDRESS (contract address)"
  echo "  - Other script-specific variables (see script/README.md)"
  echo ""
  exit 1
fi

# Load env vars with automatic exporting for child process
set +e
set -a
source "$ENV_FILE_ABS" 2>/dev/null
set +a
set -e

if [ -z "$PRIVATE_KEY" ]; then
  echo ""
  echo "⚠️  Error: PRIVATE_KEY not found in $ENV_FILE!"
  echo ""
  echo "The script needs PRIVATE_KEY to sign transactions."
  if [ "$ENVIRONMENT" = "local" ]; then
    echo ""
    echo "For local testing with Anvil, use:"
    echo "  PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
    echo ""
    echo "This is the first account's private key from Anvil's deterministic accounts."
  fi
  exit 1
fi

SCRIPT_PATH="script/${SCRIPT_NAME}.s.sol"
BROADCAST_FLAG=""
if [ "$DRY_RUN" = "false" ]; then
  BROADCAST_FLAG="--broadcast"
fi

echo ""
echo "Running:"
echo "  Environment: $ENVIRONMENT"
echo "  Mode: $([ "$DRY_RUN" = "false" ] && echo "Broadcast" || echo "Dry run")"
echo "  Script: $SCRIPT_NAME"
echo ""

(cd "$SCRIPT_DIR" && bash -lc "source '${ENV_FILE_ABS}' && forge script ${SCRIPT_PATH} --rpc-url ${RPC_URL} ${BROADCAST_FLAG}")

