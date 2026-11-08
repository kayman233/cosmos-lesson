// Talks to a local wasmd node from code: reads bank and cw20 balances, then sends a cw20 transfer.
// Usage: CONTRACT=wasm1... node cw20.mjs
import { DirectSecp256k1HdWallet } from "@cosmjs/proto-signing";
import { SigningCosmWasmClient } from "@cosmjs/cosmwasm";
import { GasPrice } from "@cosmjs/stargate";

const RPC_URL = process.env.RPC_URL ?? "http://localhost:26657";
const CONTRACT = process.env.CONTRACT;
if (!CONTRACT) throw new Error("Set CONTRACT to the cw20 contract address");

// user1 and user2 from scripts/init-chain.sh. Test-only mnemonics.
const USER1 = "friend excite rough reopen cover wheel spoon convince island path clean monkey play snow number walnut pull lock shoot hurry dream divide concert discover";
const USER2 = "fuel obscure melt april direct second usual hair leave hobby beef bacon solid drum used law mercy worry fat super must ritual bring faculty";

const sender = await DirectSecp256k1HdWallet.fromMnemonic(USER1, { prefix: "wasm" });
const [{ address: from }] = await sender.getAccounts();
const [{ address: to }] = await (await DirectSecp256k1HdWallet.fromMnemonic(USER2, { prefix: "wasm" })).getAccounts();

const client = await SigningCosmWasmClient.connectWithSigner(RPC_URL, sender, {
  gasPrice: GasPrice.fromString("0stake"),
});
console.log(`chain ${await client.getChainId()}, height ${await client.getHeight()}`);
console.log(`${from} has ${(await client.getBalance(from, "stake")).amount} stake`);

const cw20Balance = (address) => client.queryContractSmart(CONTRACT, { balance: { address } });
const tokenInfo = await client.queryContractSmart(CONTRACT, { token_info: {} });
console.log(`token ${tokenInfo.symbol}, supply ${tokenInfo.total_supply}`);
console.log(`before: user2 has ${(await cw20Balance(to)).balance} ${tokenInfo.symbol}`);

const result = await client.execute(from, CONTRACT, { transfer: { recipient: to, amount: "5000" } }, "auto");
console.log(`transfer tx ${result.transactionHash} in block ${result.height}, gas ${result.gasUsed}`);
console.log(`after:  user2 has ${(await cw20Balance(to)).balance} ${tokenInfo.symbol}`);
