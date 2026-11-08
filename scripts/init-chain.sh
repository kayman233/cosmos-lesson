#!/usr/bin/env bash
# Initializes a single-validator local chain with four funded test accounts.
#
# Usage: ./scripts/init-chain.sh <binary> [chain-id] [home] [denom]
#   ./scripts/init-chain.sh ./bin/simd
#   ./scripts/init-chain.sh ./bin/wasmd wasm-local ~/.wasmd-lesson stake
#
# Then start the node with: <binary> start --home <home>
set -euo pipefail

BINARY=${1:?"usage: $0 <binary> [chain-id] [home] [denom]"}
CHAIN_ID=${2:-lesson}
CHAIN_HOME=${3:-"$HOME/.$(basename "$BINARY")-lesson"}
DENOM=${4:-stake}

KEYRING=(--keyring-backend test --home "$CHAIN_HOME")
GENESIS_COINS="10000000000000$DENOM"

# Test-only mnemonics. Never use them for real funds.
MNEMONIC_VALIDATOR="guard cream sadness conduct invite crumble clock pudding hole grit liar hotel maid produce squeeze return argue turtle know drive eight casino maze host"
MNEMONIC_USER1="friend excite rough reopen cover wheel spoon convince island path clean monkey play snow number walnut pull lock shoot hurry dream divide concert discover"
MNEMONIC_USER2="fuel obscure melt april direct second usual hair leave hobby beef bacon solid drum used law mercy worry fat super must ritual bring faculty"
MNEMONIC_USER3="silly rebel tattoo style furnace gorilla giggle engine grass ticket friend act spell film achieve usage fatal crew notice seminar cute eagle grit consider"

if [ -d "$CHAIN_HOME" ]; then
  echo "Removing previous chain data in $CHAIN_HOME"
  rm -rf "$CHAIN_HOME"
fi

"$BINARY" init lesson-node --chain-id "$CHAIN_ID" --default-denom "$DENOM" --home "$CHAIN_HOME" > /dev/null 2>&1

add_key() {
  echo "$2" | "$BINARY" keys add "$1" --recover "${KEYRING[@]}" > /dev/null 2>&1
  "$BINARY" genesis add-genesis-account "$("$BINARY" keys show "$1" -a "${KEYRING[@]}")" "$GENESIS_COINS" --home "$CHAIN_HOME"
}

add_key validator "$MNEMONIC_VALIDATOR"
add_key user1 "$MNEMONIC_USER1"
add_key user2 "$MNEMONIC_USER2"
add_key user3 "$MNEMONIC_USER3"

"$BINARY" genesis gentx validator "100000000$DENOM" --chain-id "$CHAIN_ID" "${KEYRING[@]}" > /dev/null 2>&1
"$BINARY" genesis collect-gentxs --home "$CHAIN_HOME" > /dev/null 2>&1

# Faster blocks and open endpoints for local development.
CONFIG="$CHAIN_HOME/config"
sed -i.bak -E 's/^timeout_commit = .*/timeout_commit = "1s"/' "$CONFIG/config.toml"
sed -i.bak -E 's/^minimum-gas-prices = .*/minimum-gas-prices = "0'"$DENOM"'"/' "$CONFIG/app.toml"
# Enable the REST API (first "enable" key in the [api] section) and CORS for browser clients.
sed -i.bak -E '/^\[api\]/,/^\[/ s/^enable = false/enable = true/' "$CONFIG/app.toml"
sed -i.bak -E 's/^enabled-unsafe-cors = false/enabled-unsafe-cors = true/' "$CONFIG/app.toml"
sed -i.bak -E 's/^cors_allowed_origins = .*/cors_allowed_origins = ["*"]/' "$CONFIG/config.toml"
rm -f "$CONFIG"/*.bak

echo
echo "Chain '$CHAIN_ID' initialized in $CHAIN_HOME"
for name in validator user1 user2 user3; do
  printf '  %-9s %s\n' "$name" "$("$BINARY" keys show "$name" -a "${KEYRING[@]}")"
done
echo
echo "Start it with:"
echo "  $BINARY start --home $CHAIN_HOME"
