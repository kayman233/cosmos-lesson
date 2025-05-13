# Cosmos blockchain (Go 1.23)

## Clone
```
git clone https://github.com/cosmos/cosmos-sdk.git
cd cosmos-sdk
```

## Build
```
make build
cd build
```

## Set ENVs
```
export BINARY=./simd
export CHAIN_ID=chain

MNEMONIC_1="guard cream sadness conduct invite crumble clock pudding hole grit liar hotel maid produce squeeze return argue turtle know drive eight casino maze host"
MNEMONIC_2="friend excite rough reopen cover wheel spoon convince island path clean monkey play snow number walnut pull lock shoot hurry dream divide concert discover"
MNEMONIC_3="fuel obscure melt april direct second usual hair leave hobby beef bacon solid drum used law mercy worry fat super must ritual bring faculty"
MNEMONIC_4="silly rebel tattoo style furnace gorilla giggle engine grass ticket friend act spell film achieve usage fatal crew notice seminar cute eagle grit consider"

GENESIS_COINS=10000000000000stake
```

## Init folder, configs
```
$BINARY init test --chain-id $CHAIN_ID
```

## Add users
```
echo $MNEMONIC_1 | $BINARY keys add validator --recover --keyring-backend=test
echo $MNEMONIC_2 | $BINARY keys add user1 --recover --keyring-backend=test
echo $MNEMONIC_3 | $BINARY keys add user2 --recover --keyring-backend=test
echo $MNEMONIC_4 | $BINARY keys add user3 --recover --keyring-backend=test

$BINARY genesis add-genesis-account $($BINARY keys show validator --keyring-backend test -a) $GENESIS_COINS
$BINARY genesis add-genesis-account $($BINARY keys show user1 --keyring-backend test -a) $GENESIS_COINS
$BINARY genesis add-genesis-account $($BINARY keys show user2 --keyring-backend test -a) $GENESIS_COINS
$BINARY genesis add-genesis-account $($BINARY keys show user3 --keyring-backend test -a) $GENESIS_COINS
```

## Generate first tx and start the blockchain
```
$BINARY genesis gentx validator 100000000stake --chain-id $CHAIN_ID --keyring-backend test
$BINARY genesis collect-gentxs
$BINARY start
```

# Send tokens via CLI
```
export BINARY=./simd
export CHAIN_ID=chain

export FROM="cosmos1mzgucqnfr2l8cj5apvdpllhzt4zeuh2cshz5xu"
export TO="cosmos185fflsvwrz0cx46w6qada7mdy92m6kx4gqx0ny"
export SIGNER="user1"

$BINARY tx bank send $FROM $TO 100stake \
    --from $SIGNER \
    --chain-id $CHAIN_ID \
    --gas=auto \
    --gas-adjustment 1.4 \
    --keyring-backend test

```

## View balances
```
$BINARY q tx [hash]

$BINARY q bank balances $FROM
$BINARY q bank balances $TO
```

# Adding ignite
```
curl https://get.ignite.com/cli! | bash
```

## Creating a chain
```
ignite scaffold chain wasmapp --no-module
```

## Adding Wasm
```
ignite app install -g github.com/ignite/apps/wasm
ignite wasm add
ignite chain serve
ignite wasm config
ignite chain serve
```

## Compile contracts
```
git clone https://github.com/CosmWasm/cw-plus.git                                                                   
cd cw-plus

docker run --rm -v "$(pwd)":/code \  --mount type=volume,source="$(basename "$(pwd)")_cache",target=/target \
  --mount type=volume,source=registry_cache,target=/usr/local/cargo/registry \
  cosmwasm/workspace-optimizer:0.13.0

```

## Upload contract
```
wasmappd tx wasm store artifacts/cw20_base.wasm --from alice --chain-id wasmapp --gas 3000000

wasmappd query tx
```

## Instantiate contract and get address
```
wasmappd tx wasm instantiate 2 '{"name":"umipt", "symbol":"MIPT", "decimals":6, "initial_balances":[{"address":"cosmos19fzrytkckch9c8au49cllkpr64k5upj2zy0yyw", "amount":"1000000000000"}]}' --label "umipt" --from alice --chain-id wasmapp --no-admin -y

wasmappd query wasm list-contract-by-code 2
```

## Transfer
```
wasmappd tx wasm execute $addr '{"transfer":{"recipient":"$bob","amount":"10000"}}' --from alice --chain-id wasmapp -y

wasmappd q wasm contract-state smart $addr '{ "balance": { "address": "$bob" } }'
```
