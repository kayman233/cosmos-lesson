// Часть 3: работа с чейном из кода (так устроены кошельки и фронтенды).
// Читает баланс stake и cw20-баланс, затем отправляет cw20-перевод: то же, что в части 2 через CLI.
// Использование: CONTRACT=wasm1... npm run cw20   (адрес печатает ./scripts/cw20-demo.sh)
import { DirectSecp256k1HdWallet } from "@cosmjs/proto-signing";
// Важно: импортировать из @cosmjs/cosmwasm. Пакет @cosmjs/cosmwasm-stargate в 0.39 тянет старую версию stargate,
// и GasPrice перестаёт работать.
import { SigningCosmWasmClient } from "@cosmjs/cosmwasm";
import { GasPrice } from "@cosmjs/stargate";

// RPC CometBFT (порт 26657): через него клиент читает состояние и отправляет транзакции.
const RPC_URL = process.env.RPC_URL ?? "http://localhost:26657";
const CONTRACT = process.env.CONTRACT;
if (!CONTRACT) throw new Error("Set CONTRACT to the cw20 contract address");

// Мнемоники user1 и user2 из scripts/init-chain.sh. Только для локальной сети.
const USER1 = "friend excite rough reopen cover wheel spoon convince island path clean monkey play snow number walnut pull lock shoot hurry dream divide concert discover";
const USER2 = "fuel obscure melt april direct second usual hair leave hobby beef bacon solid drum used law mercy worry fat super must ritual bring faculty";

// Кошелёк держит ключ у клиента: транзакция подписывается здесь, нода получает уже подписанную.
// prefix "wasm": адреса wasmd начинаются с wasm1… (у simd cosmos1…), байты адреса те же.
const sender = await DirectSecp256k1HdWallet.fromMnemonic(USER1, { prefix: "wasm" });
const [{ address: from }] = await sender.getAccounts();
const [{ address: to }] = await (await DirectSecp256k1HdWallet.fromMnemonic(USER2, { prefix: "wasm" })).getAccounts();

// Подписывающий клиент. gasPrice 0stake, потому что init-chain.sh разрешил нулевую комиссию.
const client = await SigningCosmWasmClient.connectWithSigner(RPC_URL, sender, {
  gasPrice: GasPrice.fromString("0stake"),
});
console.log(`chain ${await client.getChainId()}, height ${await client.getHeight()}`);
console.log(`${from} has ${(await client.getBalance(from, "stake")).amount} stake`);

// Query: вызывает функцию query контракта. Без транзакции и бесплатно.
const cw20Balance = (address) => client.queryContractSmart(CONTRACT, { balance: { address } });
const tokenInfo = await client.queryContractSmart(CONTRACT, { token_info: {} });
console.log(`token ${tokenInfo.symbol}, supply ${tokenInfo.total_supply}`);
console.log(`before: user2 has ${(await cw20Balance(to)).balance} ${tokenInfo.symbol}`);

// Execute: транзакция MsgExecuteContract с JSON-сообщением контракта.
// "auto": газ оценивается симуляцией транзакции на ноде.
const result = await client.execute(from, CONTRACT, { transfer: { recipient: to, amount: "5000" } }, "auto");
console.log(`transfer tx ${result.transactionHash} in block ${result.height}, gas ${result.gasUsed}`);
console.log(`after:  user2 has ${(await cw20Balance(to)).balance} ${tokenInfo.symbol}`);
