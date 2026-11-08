#!/usr/bin/env bash
# Весь сценарий CosmWasm (часть 2) одной командой. Нужна запущенная нода wasmd:
#   ./scripts/init-chain.sh bin/wasmd && bin/wasmd start --home ~/.wasmd-lesson
#
# Шаги: store (загрузить байткод) -> instantiate (создать токен MIPT)
#       -> execute (перевод user1 -> user2) -> query (прочитать баланс).
# В конце печатает `export CONTRACT=...` с адресом контракта для части 3 (client/).
#
# Использование: ./scripts/cw20-demo.sh [wasmd=bin/wasmd] [wasm-файл] [chain-id] [домашняя папка]
#   ./scripts/cw20-demo.sh
set -euo pipefail

WASMD=${1:-"$(dirname "$0")/../bin/wasmd"}
WASM_FILE=${2:-"$(dirname "$0")/../artifacts/cw20_base.wasm"}
CHAIN_ID=${3:-lesson}
CHAIN_HOME=${4:-"$HOME/.wasmd-lesson"}

# jq нужен, чтобы доставать поля из JSON-ответов ноды.
command -v jq > /dev/null || { echo "jq is required: brew install jq"; exit 1; }

# Все транзакции подписывает user1; gas auto = нода сама оценит газ (симуляцией), +40% запаса.
TX_FLAGS=(--from user1 --chain-id "$CHAIN_ID" --keyring-backend test --home "$CHAIN_HOME"
  --gas auto --gas-adjustment 1.4 -y -o json)
Q_FLAGS=(--home "$CHAIN_HOME" -o json)

USER1=$("$WASMD" keys show user1 -a --keyring-backend test --home "$CHAIN_HOME")
USER2=$("$WASMD" keys show user2 -a --keyring-backend test --home "$CHAIN_HOME")

# Отправляет транзакцию и ждёт, пока она попадёт в блок.
# Ответ на отправку это только результат CheckTx (транзакция принята в мемпул),
# поэтому дальше опрашиваем `q tx`, пока транзакция не появится в блоке, и проверяем её code (0 = успех).
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

# 1. Store: байткод контракта сохраняется в чейне, ему выдаётся code_id. Сам по себе он ничего не делает.
echo "1. Store $WASM_FILE"
send_tx store "$WASM_FILE"
CODE_ID=$("$WASMD" q wasm list-code "${Q_FLAGS[@]}" | jq -r '.code_infos[-1].code_id')
echo "  code_id $CODE_ID"

# 2. Instantiate: создаём экземпляр контракта со своим адресом и хранилищем.
#    Параметры: JSON из InstantiateMsg контракта cw20-base. --no-admin: контракт нельзя будет мигрировать.
echo "2. Instantiate cw20 token MIPT"
INIT_MSG=$(jq -nc --arg owner "$USER1" \
  '{name: "MIPT token", symbol: "MIPT", decimals: 6, initial_balances: [{address: $owner, amount: "1000000000000"}]}')
send_tx instantiate "$CODE_ID" "$INIT_MSG" --label mipt --no-admin
CONTRACT=$("$WASMD" q wasm list-contract-by-code "$CODE_ID" "${Q_FLAGS[@]}" | jq -r '.contracts[-1]')
echo "  contract $CONTRACT"

# 3. Execute: обычная транзакция с сообщением MsgExecuteContract, внутри JSON ExecuteMsg контракта.
echo "3. Transfer 10000 MIPT from user1 to user2"
send_tx execute "$CONTRACT" "$(jq -nc --arg to "$USER2" '{transfer: {recipient: $to, amount: "10000"}}')"

# 4. Query: чтение через функцию query контракта, без транзакции и бесплатно.
echo "4. Query"
echo "  token_info: $("$WASMD" q wasm contract-state smart "$CONTRACT" '{"token_info":{}}' "${Q_FLAGS[@]}" | jq -c .data)"
echo "  user2 balance: $("$WASMD" q wasm contract-state smart "$CONTRACT" \
  "$(jq -nc --arg a "$USER2" '{balance: {address: $a}}')" "${Q_FLAGS[@]}" | jq -c .data)"
echo
echo "export CONTRACT=$CONTRACT"
