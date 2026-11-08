#!/usr/bin/env bash
# Runs the whole CosmWasm flow against a running local wasmd node:
# store -> instantiate -> execute (transfer) -> query.
#
# Usage: ./scripts/cw20-demo.sh <wasmd-binary> [wasm-file] [chain-id] [home]
#   ./scripts/cw20-demo.sh ./bin/wasmd
set -euo pipefail

WASMD=${1:?"usage: $0 <wasmd-binary> [wasm-file] [chain-id] [home]"}
WASM_FILE=${2:-"$(dirname "$0")/../artifacts/cw20_base.wasm"}
CHAIN_ID=${3:-lesson}
CHAIN_HOME=${4:-"$HOME/.wasmd-lesson"}

command -v jq > /dev/null || { echo "jq is required: brew install jq"; exit 1; }

TX_FLAGS=(--from user1 --chain-id "$CHAIN_ID" --keyring-backend test --home "$CHAIN_HOME"
  --gas auto --gas-adjustment 1.4 -y -o json)
Q_FLAGS=(--home "$CHAIN_HOME" -o json)

USER1=$("$WASMD" keys show user1 -a --keyring-backend test --home "$CHAIN_HOME")
USER2=$("$WASMD" keys show user2 -a --keyring-backend test --home "$CHAIN_HOME")

# Broadcasts a tx, waits for it to land in a block and fails loudly on a non-zero code.
send_tx() {
  local hash
  hash=$("$WASMD" tx wasm "$@" "${TX_FLAGS[@]}" | jq -r 'if .code == 0 then .txhash else error(.raw_log) end')
  for _ in $(seq 1 15); do
    if result=$("$WASMD" q tx "$hash" "${Q_FLAGS[@]}" 2> /dev/null); then
      echo "$result" | jq -e '.code == 0' > /dev/null || { echo "$result" | jq -r .raw_log; exit 1; }
      echo "  tx $hash, gas used $(echo "$result" | jq -r .gas_used)"
      return
    fi
    sleep 1
  done
  echo "tx $hash was not included in a block"; exit 1
}

echo "1. Store $WASM_FILE"
send_tx store "$WASM_FILE"
CODE_ID=$("$WASMD" q wasm list-code "${Q_FLAGS[@]}" | jq -r '.code_infos[-1].code_id')
echo "  code_id $CODE_ID"

echo "2. Instantiate cw20 token MIPT"
INIT_MSG=$(jq -nc --arg owner "$USER1" \
  '{name: "MIPT token", symbol: "MIPT", decimals: 6, initial_balances: [{address: $owner, amount: "1000000000000"}]}')
send_tx instantiate "$CODE_ID" "$INIT_MSG" --label mipt --no-admin
CONTRACT=$("$WASMD" q wasm list-contract-by-code "$CODE_ID" "${Q_FLAGS[@]}" | jq -r '.contracts[-1]')
echo "  contract $CONTRACT"

echo "3. Transfer 10000 MIPT from user1 to user2"
send_tx execute "$CONTRACT" "$(jq -nc --arg to "$USER2" '{transfer: {recipient: $to, amount: "10000"}}')"

echo "4. Query"
echo "  token_info: $("$WASMD" q wasm contract-state smart "$CONTRACT" '{"token_info":{}}' "${Q_FLAGS[@]}" | jq -c .data)"
echo "  user2 balance: $("$WASMD" q wasm contract-state smart "$CONTRACT" \
  "$(jq -nc --arg a "$USER2" '{balance: {address: $a}}')" "${Q_FLAGS[@]}" | jq -c .data)"
echo
echo "export CONTRACT=$CONTRACT"
