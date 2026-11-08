# Экскурсия по коду: как устроен чейн на Cosmos SDK

После `./scripts/setup.sh` рядом с репозиторием лежат исходники всех трёх нод:

```
../cosmos-sdk   v0.54.4   Cosmos SDK и эталонное приложение simd
../wasmd        v0.70.5   чейн с модулем x/wasm (CosmWasm)
../evm          v0.7.4    чейн с модулем x/vm (EVM)
```

Их удобно открыть в редакторе (`code ../cosmos-sdk`) и пройтись по файлам ниже. Ссылки ведут на GitHub на те же версии, номера строк совпадают.

Главная идея, которую стоит держать в голове: **CometBFT ничего не знает о токенах и балансах.** Он договаривается о порядке байтов (транзакций) и через ABCI отдаёт их приложению. Всё остальное (что это за транзакция, кто её подписал, у кого сколько денег) решает приложение на Cosmos SDK.

---

## 1. Карта репозитория cosmos-sdk

```
cosmos-sdk/
├── baseapp/        ядро: реализация ABCI, прогон транзакций, мемпул
├── x/              стандартные модули: bank, staking, gov, auth, distribution, …
├── simapp/         пример приложения, которое собирает модули в чейн (бинарник simd)
├── proto/          protobuf-описания сообщений, запросов и состояния модулей
├── types/          общие типы: Coin, AccAddress, Context, Msg, Tx
├── store/, collections/   хранилище ключ-значение (IAVL-дерево) и удобные обёртки над ним
├── server/, client/       запуск ноды, CLI, gRPC и REST
└── AGENTS.md       подсказки для ИИ-агентов по устройству репозитория
```

Своё приложение на SDK устроено так же, как `simapp`: `app.go` подключает нужные модули, а `cmd/` делает из этого бинарник. Именно это генерирует `ignite scaffold chain`.

## 2. Приложение: `simapp/app.go`

Это «главный файл» чейна. Здесь видно, из чего он собран.

| Что посмотреть | Где |
|---|---|
| Создание приложения | [`NewSimApp`](https://github.com/cosmos/cosmos-sdk/blob/v0.54.4/simapp/app.go#L174) |
| Keeper модуля bank | [`bankkeeper.NewBaseKeeper`](https://github.com/cosmos/cosmos-sdk/blob/v0.54.4/simapp/app.go#L301) |
| Keeper модуля staking получает BankKeeper | [`stakingkeeper.NewKeeper`](https://github.com/cosmos/cosmos-sdk/blob/v0.54.4/simapp/app.go#L325) |
| Список всех модулей | [`module.NewManager`](https://github.com/cosmos/cosmos-sdk/blob/v0.54.4/simapp/app.go#L471) |
| Порядок BeginBlock / EndBlock модулей | [`SetOrderBeginBlockers`](https://github.com/cosmos/cosmos-sdk/blob/v0.54.4/simapp/app.go#L517) |
| Регистрация Msg- и Query-сервисов | [`RegisterServices`](https://github.com/cosmos/cosmos-sdk/blob/v0.54.4/simapp/app.go#L585) |
| AnteHandler | [`setAnteHandler`](https://github.com/cosmos/cosmos-sdk/blob/v0.54.4/simapp/app.go#L650) |
| Свои PrepareProposal / ProcessProposal (закомментированный пример) | [строка 215](https://github.com/cosmos/cosmos-sdk/blob/v0.54.4/simapp/app.go#L215) |

На что обратить внимание: модули не ходят в чужое состояние напрямую. Staking получает **ссылку на BankKeeper** и списывает токены только через его методы. Какие методы ему нужны, описано интерфейсом в [`x/staking/types/expected_keepers.go`](https://github.com/cosmos/cosmos-sdk/blob/v0.54.4/x/staking/types/expected_keepers.go#L29). Так модули изолированы друг от друга.

Сам бинарник: [`simapp/simd/main.go`](https://github.com/cosmos/cosmos-sdk/blob/v0.54.4/simapp/simd/main.go#L14) и [`simapp/simd/cmd/root.go`](https://github.com/cosmos/cosmos-sdk/blob/v0.54.4/simapp/simd/cmd/root.go): команды `init`, `start`, `keys`, `tx`, `q`, которыми мы пользовались.

## 3. Модуль изнутри: `x/bank`

Любой модуль устроен одинаково. Разберём bank, потому что его транзакцию мы отправляли в части 1.

```
x/bank/
├── module.go            регистрация модуля в приложении
├── keeper/
│   ├── keeper.go        Keeper: единственный вход в состояние модуля
│   ├── view.go          что хранится (балансы, supply) и чтение
│   ├── send.go          логика переводов
│   ├── msg_server.go    обработчики транзакций (Msg)
│   └── grpc_query.go    обработчики запросов (Query)
├── types/               ключи хранилища, ошибки, события, сгенерированный из proto код
└── client/, autocli.go  CLI-команды `tx bank …`, `q bank …`
```

И описание API в `proto/cosmos/bank/v1beta1/`: `tx.proto` (сообщения), `query.proto` (запросы), `bank.proto` и `genesis.proto` (состояние).

Путь `simd tx bank send` по файлам:

1. [`tx.proto: MsgSend`](https://github.com/cosmos/cosmos-sdk/blob/v0.54.4/proto/cosmos/bank/v1beta1/tx.proto#L39): что такое транзакция перевода: `from_address`, `to_address`, `amount`. Строка `option (cosmos.msg.v1.signer) = "from_address"` говорит, чья подпись нужна.
2. [`module.go: RegisterServices`](https://github.com/cosmos/cosmos-sdk/blob/v0.54.4/x/bank/module.go#L119): модуль регистрирует свой `MsgServer`, так роутер узнаёт, кому отдавать `MsgSend`.
3. [`msg_server.go: Send`](https://github.com/cosmos/cosmos-sdk/blob/v0.54.4/x/bank/keeper/msg_server.go#L28): проверки (адреса, сумма > 0, перевод разрешён, получатель не заблокирован) и вызов `SendCoins`.
4. [`send.go: SendCoins`](https://github.com/cosmos/cosmos-sdk/blob/v0.54.4/x/bank/keeper/send.go#L229) → [`subUnlockedCoins`](https://github.com/cosmos/cosmos-sdk/blob/v0.54.4/x/bank/keeper/send.go#L304) → [`addCoins`](https://github.com/cosmos/cosmos-sdk/blob/v0.54.4/x/bank/keeper/send.go#L351): списали у одного, добавили другому, выпустили событие `transfer`.
5. [`view.go: Balances`](https://github.com/cosmos/cosmos-sdk/blob/v0.54.4/x/bank/keeper/view.go#L83): балансы лежат в хранилище как map `(адрес, denom) → сумма` под префиксом [`0x02`](https://github.com/cosmos/cosmos-sdk/blob/v0.54.4/x/bank/types/keys.go#L31).

Если открыть `curl localhost:1317/cosmos/bank/v1beta1/balances/<адрес>`: это `grpc_query.go`, выставленный наружу через REST.

## 4. Ядро: как транзакция проходит через ABCI (`baseapp/`)

Здесь SDK реализует методы ABCI, которые вызывает CometBFT. Это код к слайду про ABCI 2.0.

| Метод ABCI | Где | Что делает |
|---|---|---|
| `InitChain` | [`abci.go#L44`](https://github.com/cosmos/cosmos-sdk/blob/v0.54.4/baseapp/abci.go#L44) | Читает `genesis.json`, создаёт начальное состояние |
| `CheckTx` | [`abci.go#L358`](https://github.com/cosmos/cosmos-sdk/blob/v0.54.4/baseapp/abci.go#L358) | Проверка транзакции перед мемпулом |
| `PrepareProposal` | [`abci.go#L427`](https://github.com/cosmos/cosmos-sdk/blob/v0.54.4/baseapp/abci.go#L427) | Лидер собирает блок из мемпула |
| `ProcessProposal` | [`abci.go#L526`](https://github.com/cosmos/cosmos-sdk/blob/v0.54.4/baseapp/abci.go#L526) | Валидатор проверяет предложенный блок. В конце [запускает optimistic execution](https://github.com/cosmos/cosmos-sdk/blob/v0.54.4/baseapp/abci.go#L619): начинает исполнять блок, не дожидаясь конца голосования |
| `FinalizeBlock` | [`abci.go#L967`](https://github.com/cosmos/cosmos-sdk/blob/v0.54.4/baseapp/abci.go#L967) | Исполняет весь блок (подробнее ниже) |
| `Commit` | [`abci.go#L1056`](https://github.com/cosmos/cosmos-sdk/blob/v0.54.4/baseapp/abci.go#L1056) | Сохраняет состояние на диск |

Внутри [`internalFinalizeBlock`](https://github.com/cosmos/cosmos-sdk/blob/v0.54.4/baseapp/abci.go#L783) видна схема со слайда: один вызов ABCI, а внутри всё по-старому:

```
FinalizeBlock
├── preBlock        abci.go#L856   (например, применение апгрейда)
├── beginBlock      abci.go#L865   BeginBlocker всех модулей: mint, distribution, …
├── executeTxs      abci.go#L895   все транзакции блока
└── endBlock        abci.go#L922   EndBlocker модулей: staking обновляет валидаторов, gov считает голоса
```

Транзакции исполняются через `txRunner` ([`baseapp/txnrunner/`](https://github.com/cosmos/cosmos-sdk/tree/v0.54.4/baseapp/txnrunner)): `default.go`: по очереди, `blockstm.go`: параллельно (BlockSTM). Это возможно именно потому, что `FinalizeBlock` получает весь блок сразу.

### Одна транзакция: `runTx`

[`baseapp.go: RunTx`](https://github.com/cosmos/cosmos-sdk/blob/v0.54.4/baseapp/baseapp.go#L778): общий путь и для `CheckTx`, и для исполнения в блоке. Отличается только режим (`mode`):

1. Декодирование транзакции.
2. [AnteHandler](https://github.com/cosmos/cosmos-sdk/blob/v0.54.4/baseapp/baseapp.go#L876): проверки до исполнения.
3. В режиме `CheckTx` транзакция [кладётся в мемпул](https://github.com/cosmos/cosmos-sdk/blob/v0.54.4/baseapp/baseapp.go#L918), а сообщения **не исполняются**: [`runMsgs` выходит сразу](https://github.com/cosmos/cosmos-sdk/blob/v0.54.4/baseapp/baseapp.go#L1005). Поэтому `CheckTx` дешёвый.
4. В режиме `FinalizeBlock` каждое сообщение отдаётся [обработчику модуля через роутер](https://github.com/cosmos/cosmos-sdk/blob/v0.54.4/baseapp/baseapp.go#L1011): например, в `msg_server.go: Send` из раздела 3.

Каждая транзакция исполняется на копии состояния: если она упала, изменения отбрасываются, но комиссия (списанная в AnteHandler) остаётся списанной.

### AnteHandler: `x/auth/ante/ante.go`

[`NewAnteHandler`](https://github.com/cosmos/cosmos-sdk/blob/v0.54.4/x/auth/ante/ante.go#L46): цепочка декораторов, каждый делает одну проверку:

```
SetUpContext            лимит газа
ValidateBasic           транзакция корректно сформирована
TxTimeoutHeight         не просрочена
ValidateMemo            длина memo
ConsumeGasForTxSize     газ за размер транзакции
DeductFee               списать комиссию (здесь же feegrant: комиссию может платить другой аккаунт)
SetPubKey               запомнить публичный ключ аккаунта
ValidateSigCount        не слишком много подписей
SigGasConsume           газ за проверку подписей
SigVerification         проверить подписи
IncrementSequence       увеличить nonce (sequence): защита от повтора транзакции
```

Свой декоратор это обычный способ добавить в чейн правило «для всех транзакций», например запрет определённых сообщений или своя модель комиссий.

### Пример: account abstraction через AnteHandler

Хорошо видно, зачем это нужно, на account abstraction из магистерской работы автора семинара: [kayman233/mychain](https://github.com/kayman233/mychain) (модуль `x/abstractaccount` основан на [larry0x/abstract-account](https://github.com/larry0x/abstract-account), поверх него сделаны smart account'ы с social recovery и клиент).

Идея: правило «кто имеет право подписывать за аккаунт» в Cosmos живёт в одном месте, в декораторе `SigVerification`. Его можно заменить своим:

```
SetPubKey → ValidateSigCount → SigGasConsume
  → BeforeTxDecorator        ← вместо SigVerification
       обычный аккаунт?  → стандартная проверка подписи
       smart account?    → вызвать контракт аккаунта: sudo before_tx(msgs, sign_bytes, cred_bytes)
                            контракт сам решает, пускать ли транзакцию
  → IncrementSequence → … исполнение сообщений …
PostHandler: AfterTxDecorator → sudo after_tx (например, проверить лимиты трат)
```

- [`x/abstractaccount/ante.go`](https://github.com/kayman233/mychain/blob/main/x/abstractaccount/ante.go): `BeforeTxDecorator` и `AfterTxDecorator`, весь файл меньше 300 строк на Go.
- [`app/ante.go`](https://github.com/kayman233/mychain/blob/main/app/ante.go): декоратор просто вставлен в цепочку на место `SigVerification`.
- [`cosmwasm/contracts/base/src/execute.rs`](https://github.com/kayman233/mychain/blob/main/cosmwasm/contracts/base/src/execute.rs): простейший контракт-аккаунт: `before_tx` проверяет secp256k1-подпись своим ключом.
- [`cosmwasm/contracts/social-recovery`](https://github.com/kayman233/mychain/tree/main/cosmwasm/contracts/social-recovery): аккаунт, ключ которого можно восстановить голосами доверенных пользователей (guardians).

Аккаунт здесь является контрактом, поэтому «подпись» становится просто `cred_bytes`: что в них лежит и как проверять, решает код контракта. Это может быть обычная подпись, мультиподпись, passkey, zk-доказательство, подтверждение от guardians.

Сравнение с Ethereum: там правила проверки транзакций зашиты в протокол, и поменять их одно приложение не может. Поэтому account abstraction в Ethereum (ERC-4337) построен поверх протокола: отдельный мемпул для `UserOperation`, бандлеры, контракт `EntryPoint`, paymaster'ы, то есть целая параллельная инфраструктура. В app-specific чейне правила проверки транзакций принадлежат приложению, и то же самое делается одним декоратором.

## 5. CosmWasm: `../wasmd`

wasmd это такое же SDK-приложение, только с ещё одним модулем.

- [`app/app.go#L533`](https://github.com/CosmWasm/wasmd/blob/v0.70.5/app/app.go#L533): создание `WasmKeeper`. Ему передают Bank, Staking, Distribution и роутер сообщений: контракт может отправлять токены и вызывать модули.
- [`x/wasm/keeper/keeper.go`](https://github.com/CosmWasm/wasmd/blob/v0.70.5/x/wasm/keeper/keeper.go): три операции, которые мы делали в части 2:
  - [`create`](https://github.com/CosmWasm/wasmd/blob/v0.70.5/x/wasm/keeper/keeper.go#L158): `tx wasm store`: сохранить байткод, выдать `code_id`;
  - [`instantiate`](https://github.com/CosmWasm/wasmd/blob/v0.70.5/x/wasm/keeper/keeper.go#L263): создать контракт с адресом и своим хранилищем;
  - [`execute`](https://github.com/CosmWasm/wasmd/blob/v0.70.5/x/wasm/keeper/keeper.go#L420): вызвать контракт; сообщения, которые контракт вернул, исполняются после него (акторная модель).

Сам контракт: [`cw20-base/src/contract.rs`](https://github.com/CosmWasm/cw-plus/blob/v2.0.0/contracts/cw20-base/src/contract.rs): точки входа `instantiate`, `execute`, `query`. Состояние хранится через `cw-storage-plus`: например, `BALANCES: Map<&Addr, Uint128>` с префиксом `balance`. Поэтому в `contract-state all` ключ выглядит как `0007 62616c616e6365 …`: длина префикса, слово `balance` в hex, адрес.

## 6. Cosmos EVM: `../evm`

Тоже SDK-приложение, но с EVM-модулем.

- `evmd/app.go`: сборка чейна, как `simapp/app.go`, плюс модули `x/vm`, `x/feemarket`, `x/erc20`.
- [`x/vm/keeper/msg_server.go: EthereumTx`](https://github.com/cosmos/evm/blob/v0.7.4/x/vm/keeper/msg_server.go#L31): **Ethereum-транзакция здесь просто ещё одно Cosmos-сообщение `MsgEthereumTx`**. Она проходит через тот же `FinalizeBlock`, что и `MsgSend`, а внутри модуля исполняется в EVM.
- `rpc/`: Ethereum JSON-RPC сервер (порт 8545): переводит запросы MetaMask и ethers в запросы к чейну.
- `ante/`: отдельный AnteHandler для Ethereum-транзакций (подписи secp256k1 в формате Ethereum, nonce, EIP-1559).
- `precompiles/`: контракты по фиксированным адресам, через которые Solidity может вызвать модули SDK: bank, staking, distribution, gov, IBC.

## Что почитать дальше

- [Архитектура SDK-приложения](https://docs.cosmos.network/sdk/latest/learn/intro/sdk-app-architecture)
- `../cosmos-sdk/AGENTS.md`, `../evm/AGENTS.md`: короткие описания устройства репозиториев (написаны для ИИ-агентов, но людям тоже полезно)
- `x/<модуль>/README.md`: у каждого модуля своя спецификация
