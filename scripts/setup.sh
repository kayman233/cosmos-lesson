#!/usr/bin/env bash
# Готовит всё к семинару одной командой:
#   1. проверяет инструменты (Go, git, make, jq обязательны; Node и Docker по желанию);
#   2. клонирует исходники трёх нод РЯДОМ с репозиторием и собирает их параллельно:
#        simd   ../cosmos-sdk  (эталонный чейн на Cosmos SDK)
#        wasmd  ../wasmd       (чейн с модулем CosmWasm)
#        evmd   ../evm         (чейн с EVM, ставится в $(go env GOPATH)/bin)
#   3. кладёт ссылки на бинарники в bin/, чтобы все команды были короткими: bin/simd, bin/wasmd, bin/evmd;
#   4. ставит npm-зависимости для client/ (часть 3) и evm/ (часть 4).
#
# Использование: ./scripts/setup.sh [simd] [wasmd] [evmd]     (без аргументов собирает всё)
# Можно запускать повторно: уже скачанное и собранное пропускается. Логи сборки: logs/<имя>.log.
set -uo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
DEPS=$(dirname "$ROOT")            # sources are cloned next to the repo: ../cosmos-sdk, ../wasmd, ../evm
GOBIN_DIR=$(go env GOPATH 2> /dev/null)/bin
TARGETS=("$@"); [ ${#TARGETS[@]} -eq 0 ] && TARGETS=(simd wasmd evmd)

# Для каждой ноды: репозиторий, версия (git-тег), папка, команда сборки, где окажется бинарник.
repo()   { case $1 in simd) echo https://github.com/cosmos/cosmos-sdk;; wasmd) echo https://github.com/CosmWasm/wasmd;; evmd) echo https://github.com/cosmos/evm;; esac; }
tag()    { case $1 in simd) echo v0.54.4;; wasmd) echo v0.70.5;; evmd) echo v0.7.4;; esac; }
dir()    { case $1 in simd) echo "$DEPS/cosmos-sdk";; wasmd) echo "$DEPS/wasmd";; evmd) echo "$DEPS/evm";; esac; }
build()  { case $1 in evmd) echo "make install";; *) echo "make build";; esac; }
binary() { case $1 in simd) echo "$DEPS/cosmos-sdk/build/simd";; wasmd) echo "$DEPS/wasmd/build/wasmd";; evmd) echo "$GOBIN_DIR/evmd";; esac; }

ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*"; }
fail() { printf '  \033[31m✗\033[0m %s\n' "$*"; FAILED=1; }

# Шаг 1. Проверка инструментов. ✗: без этого не собрать, !: предупреждение, можно продолжать.
echo "1. Checking tools"
FAILED=0
if command -v go > /dev/null; then
  GOV=$(go env GOVERSION | sed 's/^go//')
  IFS=. read -r MAJ MIN PATCH <<< "$GOV"
  if [ "$MAJ" -eq 1 ] && [ "$MIN" -lt 26 ]; then
    fail "Go $GOV is too old, install Go 1.26: https://go.dev/dl/"
  elif [ "$MAJ" -eq 1 ] && [ "$MIN" -eq 26 ] && [ "${PATCH:-0}" -lt 7 ]; then
    warn "Go $GOV builds the nodes, but Ignite needs 1.26.7+"
  elif [ "$MIN" -gt 26 ]; then
    warn "Go $GOV works, but every command prints a harmless 'sonic/ast' warning (Go 1.26 avoids it)"
  else
    ok "Go $GOV"
  fi
else
  fail "Go is not installed: https://go.dev/dl/"
fi
for t in git make jq; do command -v $t > /dev/null && ok "$t" || fail "$t is not installed (macOS: brew install $t)"; done
command -v node > /dev/null && ok "Node $(node -v)" || warn "Node.js is not installed: needed for client/ and evm/ (parts 3-4)"
docker info > /dev/null 2>&1 && ok "Docker" || warn "Docker is not running: needed only to compile contracts yourself (part 2 works without it)"
[ "$FAILED" -eq 0 ] || { echo; echo "Install the missing tools and run the script again."; exit 1; }

# Шаг 2. Клонирование и сборка. Каждая нода собирается в фоне (&), потом ждём все (wait).
echo
echo "2. Building ${TARGETS[*]} (in parallel, 2-5 minutes on the first run)"
mkdir -p "$ROOT/logs" "$ROOT/bin"
PIDS=()
for name in "${TARGETS[@]}"; do
  [ -n "$(repo "$name")" ] || { fail "unknown target '$name' (use simd, wasmd, evmd)"; exit 1; }
  if [ -x "$(binary "$name")" ]; then
    ok "$name already built"
    continue
  fi
  (
    set -e
    d=$(dir "$name")
    [ -d "$d" ] || git clone --quiet --depth 1 --branch "$(tag "$name")" "$(repo "$name")" "$d"
    cd "$d" && $(build "$name")
  ) > "$ROOT/logs/$name.log" 2>&1 &
  PIDS+=("$!:$name")
  echo "  … $name: cloning $(tag "$name") into $(dir "$name") and running '$(build "$name")' (log: logs/$name.log)"
done
START=$SECONDS
for entry in ${PIDS[@]+"${PIDS[@]}"}; do
  pid=${entry%%:*}; name=${entry#*:}
  if wait "$pid"; then ok "$name built in $((SECONDS - START))s"; else fail "$name failed, see logs/$name.log"; fi
done
[ "$FAILED" -eq 0 ] || exit 1

# Шаг 3. Ссылки bin/<имя> -> настоящий бинарник.
echo
echo "3. Linking binaries into bin/"
for name in "${TARGETS[@]}"; do
  ln -sf "$(binary "$name")" "$ROOT/bin/$name"
  ok "bin/$name -> $(binary "$name") ($("$ROOT/bin/$name" version 2>&1 | tail -1))"
done

if command -v node > /dev/null; then
  # Шаг 4. npm install в client/ и evm/.
  echo
  echo "4. Installing npm dependencies"
  for d in client evm; do
    (cd "$ROOT/$d" && npm install --silent > /dev/null 2>&1) && ok "$d/" || warn "npm install failed in $d/"
  done
fi

echo
echo "Done. Next step (part 1):"
echo "  ./scripts/init-chain.sh bin/simd"
echo "  bin/simd start --home ~/.simd-lesson"
