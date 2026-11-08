#!/usr/bin/env bash
# Создаёт локальный блокчейн из одного валидатора и четырёх аккаунтов с балансом.
# Работает с любым чейном на Cosmos SDK: simd, wasmd и т.д.
#
# Использование: ./scripts/init-chain.sh <бинарник> [chain-id] [домашняя папка] [denom]
#   ./scripts/init-chain.sh bin/simd                  -> чейн "lesson", данные в ~/.simd-lesson
#   ./scripts/init-chain.sh bin/wasmd                 -> чейн "lesson", данные в ~/.wasmd-lesson
#
# Домашняя папка ноды (--home) это не бинарник, а всё, что относится к чейну:
#   config/genesis.json  начальное состояние: балансы, валидатор, параметры модулей
#   config/config.toml   настройки CometBFT (сеть, консенсус, время блока)
#   config/app.toml      настройки приложения (REST API, минимальная цена газа)
#   keyring-test/        ключи аккаунтов
#   data/                база блоков и состояния (появится после `start`)
#
# После скрипта нода запускается командой: <бинарник> start --home <домашняя папка>
set -euo pipefail

BINARY=${1:?"usage: $0 <binary> [chain-id] [home] [denom]"}
CHAIN_ID=${2:-lesson}
CHAIN_HOME=${3:-"$HOME/.$(basename "$BINARY")-lesson"}
DENOM=${4:-stake}

# --keyring-backend test: ключи хранятся на диске без пароля. Только для локальной сети!
# Этот флаг (и --chain-id для транзакций) нужно указывать в каждой команде CLI.
KEYRING=(--keyring-backend test --home "$CHAIN_HOME")
GENESIS_COINS="10000000000000$DENOM"

# Тестовые мнемоники: одинаковые у всех студентов, поэтому адреса тоже совпадают.
# Никогда не используйте их для настоящих денег.
MNEMONIC_VALIDATOR="guard cream sadness conduct invite crumble clock pudding hole grit liar hotel maid produce squeeze return argue turtle know drive eight casino maze host"
MNEMONIC_USER1="friend excite rough reopen cover wheel spoon convince island path clean monkey play snow number walnut pull lock shoot hurry dream divide concert discover"
MNEMONIC_USER2="fuel obscure melt april direct second usual hair leave hobby beef bacon solid drum used law mercy worry fat super must ritual bring faculty"
MNEMONIC_USER3="silly rebel tattoo style furnace gorilla giggle engine grass ticket friend act spell film achieve usage fatal crew notice seminar cute eagle grit consider"

# 0. Начинаем с чистого листа: старый чейн с теми же настройками удаляется.
if [ -d "$CHAIN_HOME" ]; then
  echo "Removing previous chain data in $CHAIN_HOME"
  rm -rf "$CHAIN_HOME"
fi

# 1. init: создаёт config/ и пустой genesis.json, генерирует ключ ноды (для CometBFT).
"$BINARY" init lesson-node --chain-id "$CHAIN_ID" --default-denom "$DENOM" --home "$CHAIN_HOME" > /dev/null 2>&1

# 2. Для каждого аккаунта: восстановить ключ из мнемоники и записать стартовый баланс в genesis.json.
add_key() {
  echo "$2" | "$BINARY" keys add "$1" --recover "${KEYRING[@]}" > /dev/null 2>&1
  "$BINARY" genesis add-genesis-account "$("$BINARY" keys show "$1" -a "${KEYRING[@]}")" "$GENESIS_COINS" --home "$CHAIN_HOME"
}

add_key validator "$MNEMONIC_VALIDATOR"
add_key user1 "$MNEMONIC_USER1"
add_key user2 "$MNEMONIC_USER2"
add_key user3 "$MNEMONIC_USER3"

# 3. gentx: подписанная транзакция «хочу быть валидатором, ставлю 100000000stake в стейк».
#    collect-gentxs: кладёт её в genesis.json. Без валидатора чейн не начнёт выпускать блоки.
"$BINARY" genesis gentx validator "100000000$DENOM" --chain-id "$CHAIN_ID" "${KEYRING[@]}" > /dev/null 2>&1
"$BINARY" genesis collect-gentxs --home "$CHAIN_HOME" > /dev/null 2>&1

# 4. Настройки для удобной локальной разработки.
CONFIG="$CHAIN_HOME/config"
# Блок раз в секунду (по умолчанию 5 секунд).
sed -i.bak -E 's/^timeout_commit = .*/timeout_commit = "1s"/' "$CONFIG/config.toml"
# Бесплатный газ: нода принимает транзакции с нулевой комиссией.
sed -i.bak -E 's/^minimum-gas-prices = .*/minimum-gas-prices = "0'"$DENOM"'"/' "$CONFIG/app.toml"
# Включить REST API на :1317 (первый ключ "enable" в секции [api]) и CORS для браузерных клиентов.
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
