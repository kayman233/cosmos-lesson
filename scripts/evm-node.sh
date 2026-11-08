#!/usr/bin/env bash
# Запускает локальную ноду Cosmos EVM (часть 4): chainId 262144, Ethereum JSON-RPC на localhost:8545,
# несколько dev-аккаунтов с балансом (dev0, dev1, …).
#
# Это обёртка над local_node.sh из репозитория cosmos/evm: тот скрипт ищет `evmd` в PATH,
# поэтому подставляем bin/ в PATH и отключаем его собственный `make install` (--no-install).
# Данные чейна лежат в ~/.evmd и создаются заново при каждом запуске (-y).
#
# Использование: ./scripts/evm-node.sh      (сначала ./scripts/setup.sh)
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
EVM_SRC=$(dirname "$ROOT")/evm
[ -x "$ROOT/bin/evmd" ] && [ -f "$EVM_SRC/local_node.sh" ] || { echo "evmd is not built yet: ./scripts/setup.sh evmd"; exit 1; }

export PATH="$ROOT/bin:$PATH"
cd "$EVM_SRC"
exec ./local_node.sh -y --no-install
