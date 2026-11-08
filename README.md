# Семинар: разработка в экосистеме Cosmos

Материалы к семинару МФТИ «Разработка в Cosmos ecosystem». Всё проверено в ноябре 2026 года на macOS (Apple Silicon).

| Часть | Что делаем | Инструменты |
|---|---|---|
| 1 | Поднимаем блокчейн на Cosmos SDK и отправляем токены | `simd` из cosmos-sdk **v0.54.4** (CometBFT v0.39) |
| 2 | Загружаем и вызываем смарт-контракт CosmWasm | `wasmd` **v0.70.5**, cw-plus v2.0.0, `cosmwasm/optimizer` 0.17.0 |
| 3 | Работаем с чейном из кода | CosmJS **0.39** |
| 4 | Деплоим Solidity-контракт на Cosmos-чейн | Cosmos EVM **v0.7.4** (`evmd`), ethers.js |
| 5 | Генерируем свой чейн и модуль (домашнее задание) | Ignite CLI **v29.10.1** (Cosmos SDK v0.53) |

## Быстрый старт

Нужно установить:

- **Go 1.26** (1.26.7 или новее): https://go.dev/dl/. Ignite требует не ниже 1.26.7. На Go 1.27 всё собирается, но каждая команда печатает безвредное предупреждение `sonic/ast`
- **jq**: `brew install jq`
- **Node.js 20+**: для частей 3 и 4
- **Docker**: только если хотите сами компилировать контракт в части 2

```bash
git clone https://github.com/kayman233/cosmos-lesson.git
cd cosmos-lesson
./scripts/setup.sh
```

`setup.sh` проверяет инструменты, скачивает исходники трёх нод **рядом с репозиторием** (`../cosmos-sdk`, `../wasmd`, `../evm`), собирает их параллельно и кладёт ссылки на бинарники в `bin/`. Первый запуск занимает 3–5 минут. Скрипт можно запускать повторно: уже собранное он пропускает. Если что-то не собралось, смотрите лог в `logs/<имя>.log`. Собрать только одну ноду: `./scripts/setup.sh simd`.

После этого все команды ниже запускаются из папки `cosmos-lesson`.

Как устроен код чейна (приложение, модули, путь транзакции через ABCI, CosmWasm и EVM внутри) разобрано в [docs/code-tour.md](docs/code-tour.md).

## Скрипты

| Скрипт | Что делает |
|---|---|
| `scripts/setup.sh [simd] [wasmd] [evmd]` | Проверяет окружение, клонирует и собирает ноды, кладёт их в `bin/`, ставит npm-зависимости для `client/` и `evm/` |
| `scripts/init-chain.sh <бинарник> [chain-id] [home]` | Создаёт локальный чейн с одним валидатором и четырьмя аккаунтами с балансом: `validator`, `user1`, `user2`, `user3`. Удаляет старые данные чейна, если они были. Ускоряет блоки до 1 секунды и включает REST API |
| `scripts/cw20-demo.sh` | Весь сценарий части 2 одной командой: store → instantiate → transfer → query. Нужна запущенная нода `wasmd` |
| `scripts/evm-node.sh` | Запускает локальную ноду Cosmos EVM с dev-аккаунтами (обёртка над `local_node.sh` из cosmos/evm) |

Что `init-chain.sh` делает внутри (то же самое можно сделать руками):

```bash
simd init lesson-node --chain-id lesson                    # config/ и пустой genesis.json
simd keys add user1 --recover --keyring-backend test       # ключи из мнемоник (лежат в скрипте)
simd genesis add-genesis-account <адрес> 10000000000000stake # начальные балансы
simd genesis gentx validator 100000000stake                # транзакция «я валидатор»
simd genesis collect-gentxs                                 # кладём её в genesis.json
```

Флаги, которые встречаются почти в каждой команде:

- `--home ~/.simd-lesson`: домашняя папка ноды с конфигами, ключами и базой блоков (не путать с бинарником `bin/simd`);
- `--keyring-backend test`: ключи лежат на диске без пароля (только для локальной сети);
- `--chain-id lesson`: подпись транзакции привязана к этому чейну.

Запросам (`q …`) флаги не нужны: они не читают локальные файлы, а спрашивают запущенную ноду на `localhost:26657`, так же как `curl` к REST API.

Пишите флаги прямо в команде. Если сложить их в переменную (`FLAGS="--home …"`), в zsh (оболочка по умолчанию на macOS) команда не сработает: zsh передаёт строку из переменной одним аргументом.

Мнемоники в скрипте годятся **только** для локальной сети.

> Ноды `simd`, `wasmd` и `evmd` используют одни и те же порты (26657, 1317, 9090). Перед запуском следующей остановите предыдущую (Ctrl+C).

---

## Часть 1. Cosmos SDK: `simd`

`simd` это эталонное приложение из репозитория cosmos-sdk со всеми стандартными модулями.

```bash
./scripts/init-chain.sh bin/simd        # создать чейн, данные ноды в ~/.simd-lesson
bin/simd start --home ~/.simd-lesson    # запустить ноду: в логе каждую секунду новый блок
```

В соседнем терминале, подождав пару блоков:

```bash
export TO=$(bin/simd keys show user2 -a --home ~/.simd-lesson --keyring-backend test)   # адрес user2

# Перевод user1 -> user2. Ответ (code: 0, txhash) значит только «принята в мемпул»
bin/simd tx bank send user1 $TO 100stake --gas auto --gas-adjustment 1.4 -y \
  --home ~/.simd-lesson --keyring-backend test --chain-id lesson
bin/simd q tx <txhash>         # попала ли в блок: height, gas_used, события
bin/simd q bank balances $TO   # баланс user2 вырос на 100

# То же через REST API:
curl -s localhost:1317/cosmos/bank/v1beta1/balances/$TO | jq
```

### Что слушает запущенная нода

Пока работает `start`, нода поднимает несколько серверов:

| Порт | Что это | Кто пользуется |
|---|---|---|
| 26657 | RPC CometBFT: блоки, статус, отправка транзакций | CLI (`q`, `tx`), CosmJS |
| 1317 | REST API приложения (включает `init-chain.sh`) | `curl`, браузер, фронтенды |
| 9090 | gRPC приложения: те же запросы, что REST | бэкенды, другие сервисы |
| 26656 | P2P | другие ноды сети |

```bash
curl -s localhost:26657/status | jq .result.sync_info                 # CometBFT: высота и хэш последнего блока
curl -s "localhost:26657/block?height=5" | jq .result.block.header    # заголовок блока: app_hash, proposer
curl -s localhost:1317/cosmos/bank/v1beta1/balances/$TO | jq          # приложение, модуль bank
curl -s localhost:1317/cosmos/staking/v1beta1/validators | jq '.validators[0].description'   # модуль staking
```

На 26657 отвечает CometBFT: он знает про блоки, но ничего не знает про балансы. На 1317 отвечает приложение: каждый модуль выставляет свои `Query` из proto по пути `/cosmos/<модуль>/...`.

Что происходит с этой транзакцией внутри кода, разобрано в [docs/code-tour.md](docs/code-tour.md): от `MsgSend` в proto до `SendCoins` в модуле bank.

## Часть 2. CosmWasm: `wasmd`

`wasmd` это эталонный чейн с подключённым модулем `x/wasm`. Раньше для этого генерировали чейн через Ignite и плагин wasm, но плагин застрял на старой версии wasmd, поэтому теперь берём wasmd напрямую.

```bash
./scripts/init-chain.sh bin/wasmd       # данные ноды в ~/.wasmd-lesson
bin/wasmd start --home ~/.wasmd-lesson
```

Первый старт после сборки может занять до минуты, прежде чем пойдут блоки.

### Загрузка, инициализация, вызов

```bash
export USER1=$(bin/wasmd keys show user1 -a --home ~/.wasmd-lesson --keyring-backend test)
export USER2=$(bin/wasmd keys show user2 -a --home ~/.wasmd-lesson --keyring-backend test)

# 1. Store: загружаем байткод, получаем code_id
bin/wasmd tx wasm store artifacts/cw20_base.wasm --from user1 --gas auto --gas-adjustment 1.4 -y \
  --home ~/.wasmd-lesson --keyring-backend test --chain-id lesson
bin/wasmd q wasm list-code   # code_id: 1

# 2. Instantiate: создаём экземпляр контракта (токен MIPT). JSON здесь это InstantiateMsg контракта
bin/wasmd tx wasm instantiate 1 \
  "{\"name\":\"MIPT token\",\"symbol\":\"MIPT\",\"decimals\":6,\"initial_balances\":[{\"address\":\"$USER1\",\"amount\":\"1000000000000\"}]}" \
  --label mipt --no-admin --from user1 --gas auto --gas-adjustment 1.4 -y \
  --home ~/.wasmd-lesson --keyring-backend test --chain-id lesson
export CONTRACT=$(bin/wasmd q wasm list-contract-by-code 1 -o json | jq -r '.contracts[-1]')   # адрес контракта

# 3. Execute: переводим 10000 MIPT от user1 к user2
bin/wasmd tx wasm execute $CONTRACT "{\"transfer\":{\"recipient\":\"$USER2\",\"amount\":\"10000\"}}" --from user1 --gas auto --gas-adjustment 1.4 -y \
  --home ~/.wasmd-lesson --keyring-backend test --chain-id lesson

# 4. Query: читаем состояние через функцию query контракта, без транзакции
bin/wasmd q wasm contract-state smart $CONTRACT "{\"balance\":{\"address\":\"$USER2\"}}"
bin/wasmd q wasm contract-state all $CONTRACT   # сырое хранилище: ключи в hex, значения в base64
curl -s localhost:1317/cosmwasm/wasm/v1/code | jq '.code_infos'   # то же через REST: загруженные контракты
```

Если что-то пошло не так, весь сценарий выполняется одной командой. В конце она печатает `export CONTRACT=...` для части 3:

```bash
./scripts/cw20-demo.sh
```

### Компиляция контракта (по желанию)

Готовый `artifacts/cw20_base.wasm` уже лежит в репозитории. Собрать его самому:

```bash
git clone --depth 1 --branch v2.0.0 https://github.com/CosmWasm/cw-plus.git ../cw-plus
cd ../cw-plus

# Важно: cw-plus v2.0.0 зафиксирован на cosmwasm-std 2.0.0. С новым Rust (1.86 в optimizer 0.17)
# такой контракт загружается, но падает при instantiate с паникой аллокатора (dlmalloc).
# Обновляем std до последней 2.x:
docker run --rm -v "$(pwd)":/code --entrypoint cargo cosmwasm/optimizer-arm64:0.17.0 \
  update -p cosmwasm-std -p cosmwasm-schema

# На Intel/Linux используйте образ cosmwasm/optimizer:0.17.0 (на Apple Silicon он идёт через эмуляцию, ~8 минут)
docker run --rm -v "$(pwd)":/code \
  --mount type=volume,source="$(basename "$(pwd)")_cache",target=/target \
  --mount type=volume,source=registry_cache,target=/usr/local/cargo/registry \
  cosmwasm/optimizer-arm64:0.17.0

cd -
```

## Часть 3. Клиент на CosmJS

Нода `wasmd` из части 2 должна быть запущена.

```bash
cd client
CONTRACT=<адрес из части 2> npm run cw20    # балансы до/после и cw20-перевод 5000 MIPT
```

Скрипт `client/cw20.mjs` подключается к ноде, читает балансы и отправляет cw20-перевод: всё то же, что в части 2, только из кода. Для браузерных приложений смотрите [Interchain Kit / Hyperweb](https://hyperweb.io/stack).

> В CosmJS 0.39 пакет `@cosmjs/cosmwasm-stargate` стал обёрткой над `@cosmjs/cosmwasm` и тянет старую версию `stargate`, из-за чего ломается `GasPrice`. Импортируйте из `@cosmjs/cosmwasm`.

## Часть 4. Cosmos EVM: Solidity на Cosmos-чейне

Тот же стек (Cosmos SDK + CometBFT), но с EVM внутри: работают Solidity, MetaMask, ethers, Foundry.

```bash
./scripts/evm-node.sh
```

В соседнем терминале, из папки `cosmos-lesson`:

```bash
(cd evm && npm run deploy)    # компиляция Counter.sol, деплой, increment(), count = 1
```

Скрипт компилирует `contracts/Counter.sol`, деплоит его через Ethereum JSON-RPC (`localhost:8545`, chainId 262144) и вызывает `increment()`.

Один и тот же аккаунт виден с двух сторон:

```bash
bin/evmd keys show dev0 -a --home ~/.evmd --keyring-backend test   # cosmos1cml96...
bin/evmd debug addr cosmos1cml96vmptgw99syqrrz8az79xer2pcgp95srxm   # 0xC6Fe5D33...
bin/evmd q bank balances cosmos1cml96vmptgw99syqrrz8az79xer2pcgp95srxm
```

Чтобы подключить MetaMask: RPC `http://localhost:8545`, chainId `262144`. Приватный ключ dev0 есть в `../evm/local_node.sh`.

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

## Разработка с ИИ

Модели часто знают Cosmos по старым туториалам: предлагают `BeginBlock`/`DeliverTx` вместо `FinalizeBlock`, `x/params`, импорт из `@cosmjs/cosmwasm-stargate`, старую `cosmwasm-std`. Всё это выглядит правдоподобно, но ломается на актуальных версиях. Поэтому дайте агенту актуальную документацию.

**MCP-сервер документации Cosmos:** https://docs.cosmos.network/mcp. С ним агент сам ищет по документации нужной версии.

```bash
# Claude Code
claude mcp add --transport http cosmos-docs https://docs.cosmos.network/mcp

# Codex
codex mcp add cosmos-docs --url https://docs.cosmos.network/mcp
```

Проверить: `claude mcp list` / `codex mcp list`. Другие агенты (Cursor и т.д.): подключите тот же адрес как HTTP MCP-сервер.

Ещё полезно:

- https://docs.cosmos.network/llms.txt: документация в формате для моделей;
- `AGENTS.md` в корне `../cosmos-sdk` и `../evm`: как устроен репозиторий, как собирать и тестировать. Агенты читают его автоматически, заведите такой же в своём проекте.

Готовые инструменты для агентов:

- **[Trail of Bits skills](https://github.com/trailofbits/skills)**: навыки от аудиторской компании Trail of Bits. Для нас главный `cosmos-vulnerability-scanner` (плагин `building-secure-contracts`): ищет в модулях Cosmos SDK и контрактах CosmWasm уязвимости, которые приводят к остановке чейна или потере средств (недетерминизм, паники в `FinalizeBlock`, ошибки в IBC).
  ```bash
  # Claude Code: внутри сессии
  /plugin marketplace add trailofbits/skills
  /plugin                      # выбрать building-secure-contracts
  # Codex
  codex plugin marketplace add trailofbits/skills
  ```
- **[OpenZeppelin Contracts MCP](https://github.com/OpenZeppelin/contracts-wizard/tree/master/packages/mcp)**: генерирует стандартные Solidity-контракты (ERC-20, ERC-721, governor и др.) на проверенных библиотеках OpenZeppelin. Пригодится для Cosmos EVM (часть 4).
  ```bash
  claude mcp add OpenZeppelinContracts -- npx -y @openzeppelin/contracts-mcp
  codex mcp add OpenZeppelinContracts -- npx -y @openzeppelin/contracts-mcp
  ```

Сторонние навыки это инструкции и скрипты, которые агент выполняет у вас на машине. Перед установкой загляните в их `SKILL.md`.

Что проверять за агентом:

- **детерминизм**: никакой итерации по `map` в Go, `float` и `time.Now()` в логике чейна, иначе у валидаторов получится разный результат и чейн остановится;
- **права доступа** в контрактах: кто может вызывать mint, менять конфиг, мигрировать (`info.sender`);
- **тесты**: пусть агент пишет и запускает их (для CosmWasm есть `cw-multi-test`).

## Если что-то сломалось

| Симптом | Решение |
|---|---|
| Транзакция не попала в блок сразу после старта ноды | Подождать пару блоков и повторить |
| `address already in use` / порт 26657 занят | Не остановлена прошлая нода: `pkill -f "simd start"` (или `wasmd`, `evmd`) |
| `instantiate` падает с `dlmalloc ... psize <= size + max_overhead` | Контракт собран со старой `cosmwasm-std`. Возьмите `artifacts/cw20_base.wasm` или выполните `cargo update -p cosmwasm-std` |
| `Gas price must be a GasPrice instance` в CosmJS | Импортируйте из `@cosmjs/cosmwasm`, а не из `@cosmjs/cosmwasm-stargate` |
| `tx ...` печатает справку (`Usage: ...`) вместо отправки | Флаги переданы через переменную в zsh. Напишите их прямо в команде |
| Каждая команда печатает `WARNING: sonic/ast only supports ...` | У вас Go 1.27. Работает, предупреждение безвредное |
| Ignite: нет команды `scaffold chain` | Установлен v30 RC. Поставьте `curl https://get.ignite.com/cli@v29.10.1! \| bash` |

## Версии

| Компонент | 2025 | Сейчас |
|---|---|---|
| Cosmos SDK | v0.50 (через Ignite), `main` для simd | v0.54.4 (v0.55.0 уже вышел) |
| CometBFT | v0.38 | v0.39 / v0.40 |
| ibc-go | v8 | v11 |
| wasmd / wasmvm | v0.54 / v2 | v0.70.5 / v3 |
| cosmwasm optimizer | `workspace-optimizer:0.13.0` | `optimizer:0.17.0` |
| CosmJS | не было | 0.39 |
| Cosmos EVM | не было | v0.7.4 |
| Ignite | latest (v28/v29) | v29.10.1, v30 в RC |

## Ссылки

- Cosmos SDK: https://docs.cosmos.network
- CosmWasm: https://cosmwasm.cosmos.network
- wasmd: https://github.com/CosmWasm/wasmd
- cw-plus: https://github.com/CosmWasm/cw-plus
- Cosmos EVM: https://github.com/cosmos/evm
- CosmJS: https://github.com/cosmos/cosmjs
- Ignite: https://docs.ignite.com
