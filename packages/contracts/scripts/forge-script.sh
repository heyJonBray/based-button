#!/usr/bin/env bash
# Interactive helper script to run Forge scripts with environment-specific configuration.
#
# Author: Jon Bray <me@jonbray.dev>
#
# 1. Place script in the root of your Foundry project
# 2. Create a .env.<chain> file for any network you want to interact with
#    - e.g. .env.local .env.ethereum .env.base .env.base_sepolia
# 3. Fill out env vars required by your scripts
#
# This script will automatically detect all scripts in your `/script` directory,
# add them to the interactive selection, create `forge` commands to run them, and source
# the correct .env file.
#
# Supports --broadcast and dry-run
#
# If chaining multiple scripts together that involve deployed contract addresses from
# previous steps, simply the .env file as you go before each run.
# Enjoy!

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}" )/.." && pwd)"
FORGE_SCRIPTS_DIR="${PROJECT_ROOT}/script"

if [ -t 1 ]; then
  BOLD=$(printf '\033[1m')
  DIM=$(printf '\033[2m')
  CYAN=$(printf '\033[36m')
  GREEN=$(printf '\033[32m')
  YELLOW=$(printf '\033[33m')
  RESET=$(printf '\033[0m')
else
  BOLD=""
  DIM=""
  CYAN=""
  GREEN=""
  YELLOW=""
  RESET=""
fi

print_header() {
  printf '\n%s%sForge Script Runner%s\n' "$BOLD" "$CYAN" "$RESET"
  printf '%sRun any Foundry script with a guided prompt%s\n' "$DIM" "$RESET"
}

print_section() {
  printf '\n%s%s%s\n' "$BOLD" "$1" "$RESET"
}

print_tip() {
  printf '%s%s%s\n' "$DIM" "$1" "$RESET"
}

speak_success() {
  printf '\n%s%s%s\n' "$GREEN" "$1" "$RESET"
}

print_header
print_tip "Create a .env.<chain_name> file in ${PROJECT_ROOT} for every chain you want to target (e.g. .env.base, .env.base_sepolia, .env.ethereum, or .env.local for Anvil)."

shopt -s nullglob
ENV_FILE_PATHS=("${PROJECT_ROOT}"/.env.*)
shopt -u nullglob

ENVIRONMENTS=()
for path in "${ENV_FILE_PATHS[@]}"; do
  filename="$(basename "$path")"
  env_name="${filename#.env.}"
  if [ -z "$env_name" ]; then
    continue
  fi
  case "$env_name" in
    example|template|sample)
      continue
      ;;
  esac
  ENVIRONMENTS+=("$env_name")
done

if [ ${#ENVIRONMENTS[@]} -eq 0 ]; then
  printf '\n%s⚠️  No environment files found in %s%s\n' "$YELLOW" "$PROJECT_ROOT" "$RESET"
  printf '%sCreate files like .env.local, .env.base, or .env.sepolia before running this helper.%s\n' "$DIM" "$RESET"
  exit 1
fi

IFS=$'\n' ENVIRONMENTS=($(printf '%s\n' "${ENVIRONMENTS[@]}" | sort))
unset IFS

print_section "Detected environments"
for env in "${ENVIRONMENTS[@]}"; do
  printf '  • .env.%s\n' "$env"
done

shopt -s nullglob
SCRIPT_FILE_PATHS=("${FORGE_SCRIPTS_DIR}"/*.s.sol)
shopt -u nullglob

if [ ${#SCRIPT_FILE_PATHS[@]} -eq 0 ]; then
  printf '\n%s⚠️  No Forge scripts found in %s%s\n' "$YELLOW" "$FORGE_SCRIPTS_DIR" "$RESET"
  exit 1
fi

SCRIPTS=()
for path in "${SCRIPT_FILE_PATHS[@]}"; do
  filename="$(basename "$path")"
  SCRIPTS+=("${filename%.s.sol}")
done

IFS=$'\n' SCRIPTS=($(printf '%s\n' "${SCRIPTS[@]}" | sort))
unset IFS

print_section "Available scripts"
for script in "${SCRIPTS[@]}"; do
  printf '  • %s\n' "$script"
done

print_section "Choose environment"
for i in "${!ENVIRONMENTS[@]}"; do
  printf '  %2d) %s\n' "$((i + 1))" "${ENVIRONMENTS[$i]}"
done
printf '\n'
read -rp "${BOLD}Environment${RESET} > " env_choice

if ! [[ "$env_choice" =~ ^[0-9]+$ ]] || [ "$env_choice" -lt 1 ] || [ "$env_choice" -gt "${#ENVIRONMENTS[@]}" ]; then
  printf '\n%sInvalid choice.%s\n' "$YELLOW" "$RESET"
  exit 1
fi

ENVIRONMENT="${ENVIRONMENTS[$((env_choice - 1))]}"
ENV_FILE=".env.${ENVIRONMENT}"
ENV_FILE_ABS="${PROJECT_ROOT}/${ENV_FILE}"

if [ "$ENVIRONMENT" = "local" ]; then
  print_section "Local environment setup"
  printf '  %s▶️ Start Anvil in another terminal%s\n' "$DIM" "$RESET"
  printf '    cd %s\n' "$PROJECT_ROOT"
  printf '    anvil --host 0.0.0.0 --port 8545 --steps-tracing\n'
  printf '\n'
  read -rp "🕒 Press Enter once Anvil is running..."
fi

print_section "Choose mode"
printf '  1) Broadcast (write to chain)\n'
printf '  2) Dry run (simulates)\n'
printf '\n'
read -rp "${BOLD}Mode${RESET} > " broadcast_choice

if ! [[ "$broadcast_choice" =~ ^[1-2]$ ]]; then
  printf '\n%sInvalid choice.%s\n' "$YELLOW" "$RESET"
  exit 1
fi

DRY_RUN="false"
if [ "$broadcast_choice" -eq 2 ]; then
  DRY_RUN="true"
fi

MODE_LABEL="broadcast"
if [ "$DRY_RUN" = "true" ]; then
  MODE_LABEL="dry run"
fi

while true; do
  print_section "Choose script"
  for i in "${!SCRIPTS[@]}"; do
    printf '  %2d) %s\n' "$((i + 1))" "${SCRIPTS[$i]}"
  done
  printf '\n'
  read -rp "${BOLD}Script${RESET} > " script_choice

  if ! [[ "$script_choice" =~ ^[0-9]+$ ]] || [ "$script_choice" -lt 1 ] || [ "$script_choice" -gt "${#SCRIPTS[@]}" ]; then
    printf '\n%sInvalid choice.%s\n' "$YELLOW" "$RESET"
    exit 1
  fi

  SCRIPT_NAME="${SCRIPTS[$((script_choice - 1))]}"

  if [ ! -f "$ENV_FILE_ABS" ]; then
    printf '\n%s⚠️  %s not found in %s%s\n' "$YELLOW" "$ENV_FILE" "$PROJECT_ROOT" "$RESET"
    printf '%sCreate the file with the required environment variables before proceeding.%s\n' "$DIM" "$RESET"
    exit 1
  fi

  set +e
  set -a
  source "$ENV_FILE_ABS" 2>/dev/null
  set +a
  set -e

  if [ -z "${PRIVATE_KEY:-}" ]; then
    printf '\n%s⚠️  PRIVATE_KEY not found in %s%s\n' "$YELLOW" "$ENV_FILE" "$RESET"
    printf '%sAdd a PRIVATE_KEY value so Forge can sign transactions.%s\n' "$DIM" "$RESET"
    if [ "$ENVIRONMENT" = "local" ]; then
      printf '\n'
      printf '%s💡 Anvil tip:%s PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80\n' "$DIM" "$RESET"
      printf '\n'
      read -rp "🕒 Press Enter once PRIVATE_KEY has been added to .env.local..."
      set +e
      set -a
      source "$ENV_FILE_ABS" 2>/dev/null
      set +a
      set -e
      if [ -z "${PRIVATE_KEY:-}" ]; then
        printf '\n%s⚠️  PRIVATE_KEY still not found in %s%s\n' "$YELLOW" "$ENV_FILE" "$RESET"
        exit 1
      fi
    else
      exit 1
    fi
  fi

  RPC_URL="$ENVIRONMENT"
  if [ "$ENVIRONMENT" = "local" ]; then
    RPC_URL="http://127.0.0.1:8545"
  fi

  SCRIPT_PATH="script/${SCRIPT_NAME}.s.sol"
  BROADCAST_FLAG=""
  if [ "$DRY_RUN" = "false" ]; then
    BROADCAST_FLAG="--broadcast"
  fi

  print_section "Summary"
  printf '  Environment : %s\n' "$ENVIRONMENT"
  printf '  Mode        : %s\n' "$MODE_LABEL"
  printf '  Script      : %s\n' "$SCRIPT_NAME"
  printf '  RPC URL     : %s\n' "$RPC_URL"

  set +e
  (cd "$PROJECT_ROOT" && bash -lc "source '${ENV_FILE_ABS}' && forge script ${SCRIPT_PATH} --rpc-url ${RPC_URL} ${BROADCAST_FLAG}")
  FORGE_EXIT_CODE=$?
  set -e

  speak_success "🫡 Done."

  print_section "Would you like to run another script?"
  printf '  1) Yes\n'
  printf '  2) No\n'
  printf '\n'
  read -rp "${BOLD}Choice${RESET} > " continue_choice

  if ! [[ "$continue_choice" =~ ^[1-2]$ ]]; then
    printf '\n%sInvalid choice. Exiting.%s\n' "$YELLOW" "$RESET"
    exit $FORGE_EXIT_CODE
  fi

  if [ "$continue_choice" -eq 2 ]; then
    exit $FORGE_EXIT_CODE
  fi
done
