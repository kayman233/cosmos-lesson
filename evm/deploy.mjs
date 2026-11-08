// Часть 4: Solidity-контракт на Cosmos-чейне.
// Компилирует contracts/Counter.sol, деплоит его на локальную ноду evmd и вызывает increment().
// Для ethers это обычная Ethereum-сеть: никакого Cosmos-специфичного кода здесь нет.
// Использование: npm run deploy   (нода запущена через ./scripts/evm-node.sh)
import { readFileSync } from "node:fs";
import solc from "solc";
import { ethers } from "ethers";

// Ethereum JSON-RPC, который отдаёт evmd (порт 8545), тот же интерфейс, что у geth или Anvil.
const RPC_URL = process.env.RPC_URL ?? "http://localhost:8545";
// Ключ dev0 из local_node.sh (cosmos/evm). Только для локальной сети!
const DEV0_KEY = "0x88cbead91aee890d27bf06e003ade3d4e952427e88f88d31d61d3ef5e5d54305";

// 1. Компиляция Solidity -> ABI (описание функций) + байткод EVM.
const source = readFileSync(new URL("./contracts/Counter.sol", import.meta.url), "utf8");
const input = {
  language: "Solidity",
  sources: { "Counter.sol": { content: source } },
  settings: { evmVersion: "cancun", outputSelection: { "*": { "*": ["abi", "evm.bytecode.object"] } } },
};
const output = JSON.parse(solc.compile(JSON.stringify(input)));
const errors = (output.errors ?? []).filter((e) => e.severity === "error");
if (errors.length) throw new Error(errors.map((e) => e.formattedMessage).join("\n"));
const { abi, evm } = output.contracts["Counter.sol"].Counter;

// 2. Подключение к ноде.
const provider = new ethers.JsonRpcProvider(RPC_URL);
const wallet = new ethers.Wallet(DEV0_KEY, provider);
const network = await provider.getNetwork();
console.log(`chainId ${network.chainId}, deployer ${wallet.address}`);
console.log(`balance ${ethers.formatEther(await provider.getBalance(wallet.address))}`);

// 3. Деплой: транзакция создания контракта. Внутри чейна это Cosmos-сообщение MsgEthereumTx.
const counter = await new ethers.ContractFactory(abi, evm.bytecode.object, wallet).deploy();
await counter.waitForDeployment();
console.log(`Counter deployed at ${await counter.getAddress()}`);

// 4. Вызов функции и чтение состояния. Блок финален сразу после включения (CometBFT), ждать подтверждений не нужно.
const tx = await counter.increment();
const receipt = await tx.wait();
console.log(`increment() in block ${receipt.blockNumber}, gas used ${receipt.gasUsed}`);
console.log(`count = ${await counter.count()}`);
