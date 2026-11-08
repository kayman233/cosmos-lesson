// Compiles Counter.sol, deploys it to a local Cosmos EVM node (evmd) and calls it.
// Usage: npm install && node deploy.mjs
import { readFileSync } from "node:fs";
import solc from "solc";
import { ethers } from "ethers";

const RPC_URL = process.env.RPC_URL ?? "http://localhost:8545";
// dev0 from cosmos/evm local_node.sh. Test-only key, never use it for real funds.
const DEV0_KEY = "0x88cbead91aee890d27bf06e003ade3d4e952427e88f88d31d61d3ef5e5d54305";

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

const provider = new ethers.JsonRpcProvider(RPC_URL);
const wallet = new ethers.Wallet(DEV0_KEY, provider);
const network = await provider.getNetwork();
console.log(`chainId ${network.chainId}, deployer ${wallet.address}`);
console.log(`balance ${ethers.formatEther(await provider.getBalance(wallet.address))}`);

const counter = await new ethers.ContractFactory(abi, evm.bytecode.object, wallet).deploy();
await counter.waitForDeployment();
console.log(`Counter deployed at ${await counter.getAddress()}`);

const tx = await counter.increment();
const receipt = await tx.wait();
console.log(`increment() in block ${receipt.blockNumber}, gas used ${receipt.gasUsed}`);
console.log(`count = ${await counter.count()}`);
