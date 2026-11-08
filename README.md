# Семинар: разработка в экосистеме Cosmos

Материалы к семинару МФТИ «Разработка в Cosmos ecosystem». Всё проверено в ноябре 2026 года на macOS (Apple Silicon).

| Часть | Что делаем | Инструменты |
|---|---|---|
| 1 | Поднимаем блокчейн на Cosmos SDK и отправляем токены | `simd` из cosmos-sdk **v0.54.4** (CometBFT v0.39) |
| 2 | Компилируем, загружаем и вызываем смарт-контракт CosmWasm | `wasmd` **v0.70.5**, cw-plus v2.0.0, `cosmwasm/optimizer` 0.17.0 |
| 3 | Работаем с чейном из кода | CosmJS **0.39** |
| 4 | Деплоим Solidity-контракт на Cosmos-чейн | Cosmos EVM **v0.7.4** (`evmd`), ethers.js |
| 5 | Генерируем свой чейн и модуль | Ignite CLI **v29.10.1** (Cosmos SDK v0.53) |

## Что нужно установить

- **Go 1.26.7 или новее**: https://go.dev/dl/ (Ignite требует именно его; `wasmd` и `simd` собираются и на 1.25)
- **Docker**: только для компиляции контрактов в части 2
- **Node.js 20+**: части 3 и 4
- **jq**: `brew install jq`

```bash
git clone https://github.com/kayman233/cosmos-lesson.git
cd cosmos-lesson
```

Все тестовые чейны создаются скриптом `scripts/init-chain.sh`. Он поднимает одну ноду-валидатор и четыре аккаунта с балансом: `validator`, `user1`, `user2`, `user3`. Мнемоники лежат в скрипте и годятся **только** для локальной сети.

---

## Часть 1. Cosmos SDK: `simd`

`simd` — эталонное приложение из репозитория cosmos-sdk со всеми стандартными модулями.

```bash
git clone --depth 1 --branch v0.54.4 https://github.com/cosmos/cosmos-sdk.git ../cosmos-sdk
(cd ../cosmos-sdk && make build)        # бинарник появится в ../cosmos-sdk/build/simd

./scripts/init-chain.sh ../cosmos-sdk/build/simd lesson ~/.simd-lesson
../cosmos-sdk/build/simd start --home ~/.simd-lesson
```

> Собирайте тег релиза, а не `main`: в `main` идёт разработка следующей версии, и он может не собраться.

В соседнем терминале, подождав пару блоков:

```bash
export SIMD=../cosmos-sdk/build/simd
export FLAGS="--home $HOME/.simd-lesson --keyring-backend test --chain-id lesson"
export TO=cosmos185fflsvwrz0cx46w6qada7mdy92m6kx4gqx0ny   # user2

$SIMD tx bank send user1 $TO 100stake --gas auto --gas-adjustment 1.4 -y $FLAGS
$SIMD q tx <hash> --home ~/.simd-lesson
$SIMD q bank balances $TO --home ~/.simd-lesson

# То же через REST API:
curl -s localhost:1317/cosmos/bank/v1beta1/balances/$TO | jq
```

На что посмотреть в коде: `simapp/app.go` (какие модули подключены), `x/bank/keeper/msg_server.go` (обработка `MsgSend`).

## Часть 2. CosmWasm: `wasmd`

`wasmd` — эталонный чейн с подключённым модулем `x/wasm`. Раньше для этого генерировали чейн через Ignite и плагин wasm, но плагин застрял на старой версии wasmd, поэтому теперь берём wasmd напрямую.

```bash
git clone --depth 1 --branch v0.70.5 https://github.com/CosmWasm/wasmd.git ../wasmd
(cd ../wasmd && make build)             # ../wasmd/build/wasmd

./scripts/init-chain.sh ../wasmd/build/wasmd lesson ~/.wasmd-lesson
../wasmd/build/wasmd start --home ~/.wasmd-lesson
```

### Компиляция контракта

Готовый `artifacts/cw20_base.wasm` уже лежит в репозитории, так что этот шаг можно пропустить.

```bash
git clone --depth 1 --branch v2.0.0 https://github.com/CosmWasm/cw-plus.git ../cw-plus
cd ../cw-plus

# Важно: cw-plus v2.0.0 зафиксирован на cosmwasm-std 2.0.0. С новым Rust (1.86 в optimizer 0.17)
# такой контракт загружается, но падает при instantiate с паникой аллокатора (dlmalloc).
# Обновляем std до последней 2.x:
docker run --rm -v "$(pwd)":/code --entrypoint cargo cosmwasm/optimizer:0.17.0 \
  update -p cosmwasm-std -p cosmwasm-schema

# На Apple Silicon используйте образ cosmwasm/optimizer-arm64:0.17.0 (на amd64-образе через эмуляцию сборка ~8 минут)
docker run --rm -v "$(pwd)":/code \
  --mount type=volume,source="$(basename "$(pwd)")_cache",target=/target \
  --mount type=volume,source=registry_cache,target=/usr/local/cargo/registry \
  cosmwasm/optimizer:0.17.0

cd -
```

### Загрузка, инициализация, вызов

```bash
export WASMD=../wasmd/build/wasmd
export FLAGS="--home $HOME/.wasmd-lesson --keyring-backend test --chain-id lesson --gas auto --gas-adjustment 1.4 -y"
export USER1=$($WASMD keys show user1 -a --keyring-backend test --home ~/.wasmd-lesson)
export USER2=$($WASMD keys show user2 -a --keyring-backend test --home ~/.wasmd-lesson)

# 1. Store: загружаем байткод, получаем code_id
$WASMD tx wasm store artifacts/cw20_base.wasm --from user1 $FLAGS
$WASMD q wasm list-code --home ~/.wasmd-lesson

# 2. Instantiate: создаём экземпляр контракта (токен MIPT)
$WASMD tx wasm instantiate 1 \
  "{\"name\":\"MIPT token\",\"symbol\":\"MIPT\",\"decimals\":6,\"initial_balances\":[{\"address\":\"$USER1\",\"amount\":\"1000000000000\"}]}" \
  --label mipt --no-admin --from user1 $FLAGS
export CONTRACT=$($WASMD q wasm list-contract-by-code 1 --home ~/.wasmd-lesson -o json | jq -r '.contracts[-1]')

# 3. Execute: переводим токены
$WASMD tx wasm execute $CONTRACT "{\"transfer\":{\"recipient\":\"$USER2\",\"amount\":\"10000\"}}" --from user1 $FLAGS

# 4. Query: читаем состояние
$WASMD q wasm contract-state smart $CONTRACT "{\"balance\":{\"address\":\"$USER2\"}}" --home ~/.wasmd-lesson
$WASMD q wasm contract-state all $CONTRACT --home ~/.wasmd-lesson   # сырое хранилище: ключи в hex, значения в base64
```

Если что-то пошло не так, весь сценарий выполняется одной командой:

```bash
./scripts/cw20-demo.sh ../wasmd/build/wasmd
```

## Часть 3. Клиент на CosmJS

```bash
cd client
npm install
CONTRACT=<адрес из части 2> npm run cw20
```

Скрипт `client/cw20.mjs` подключается к ноде, читает балансы и отправляет cw20-перевод: всё то же, что в части 2, только из кода. Для браузерных приложений смотрите [Interchain Kit / Hyperweb](https://hyperweb.io/stack).

> В CosmJS 0.39 пакет `@cosmjs/cosmwasm-stargate` стал обёрткой над `@cosmjs/cosmwasm` и тянет старую версию `stargate`, из-за чего ломается `GasPrice`. Импортируйте из `@cosmjs/cosmwasm`.

## Часть 4. Cosmos EVM: Solidity на Cosmos-чейне

Тот же стек (Cosmos SDK + CometBFT), но с EVM внутри: работают Solidity, MetaMask, ethers, Foundry.

```bash
git clone --depth 1 --branch v0.7.4 https://github.com/cosmos/evm.git ../evm
(cd ../evm && make install)             # ставит evmd в $(go env GOPATH)/bin
(cd ../evm && ./local_node.sh -y --no-install)
```

В соседнем терминале:

```bash
cd evm
npm install
npm run deploy
```

Скрипт компилирует `contracts/Counter.sol`, деплоит его через Ethereum JSON-RPC (`localhost:8545`, chainId 262144) и вызывает `increment()`.

Один и тот же аккаунт виден с двух сторон:

```bash
evmd keys show dev0 -a --keyring-backend test --home ~/.evmd   # cosmos1cml96...
evmd debug addr cosmos1cml96vmptgw99syqrrz8az79xer2pcgp95srxm   # 0xC6Fe5D33...
evmd q bank balances cosmos1cml96vmptgw99syqrrz8az79xer2pcgp95srxm --home ~/.evmd
```

Чтобы подключить MetaMask: RPC `http://localhost:8545`, chainId `262144`. Приватный ключ dev0 есть в `local_node.sh`.

## Часть 5. Ignite: генерация своего чейна

```bash
curl https://get.ignite.com/cli@v29.10.1! | bash
ignite scaffold chain example && cd example
ignite scaffold map post title body     # модуль с CRUD-сообщениями и запросами
ignite chain serve
```

> Не ставьте Ignite без версии: «последний» релиз сейчас v30 release candidate, в нём команды для Cosmos перенесены в `ignite cosmos ...`.
>
> Ignite требует системный Go ≥ 1.26.7: он запускает Go с `GOTOOLCHAIN=local+path` и не скачивает новый toolchain сам.

## Версии

| Компонент | 2025 | Сейчас |
|---|---|---|
| Cosmos SDK | v0.50 (через Ignite), `main` для simd | v0.54.4 (v0.55.0 уже вышел) |
| CometBFT | v0.38 | v0.39 / v0.40 |
| ibc-go | v8 | v11 |
| wasmd / wasmvm | v0.54 / v2 | v0.70.5 / v3 |
| cosmwasm optimizer | `workspace-optimizer:0.13.0` | `optimizer:0.17.0` |
| CosmJS | — | 0.39 |
| Cosmos EVM | — | v0.7.4 |
| Ignite | latest (v28/v29) | v29.10.1, v30 в RC |

## Ссылки

- Cosmos SDK: https://docs.cosmos.network
- CosmWasm: https://cosmwasm.cosmos.network
- wasmd: https://github.com/CosmWasm/wasmd
- cw-plus: https://github.com/CosmWasm/cw-plus
- Cosmos EVM: https://github.com/cosmos/evm
- CosmJS: https://github.com/cosmos/cosmjs
- Ignite: https://docs.ignite.com
