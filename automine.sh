#!/bin/bash

set +e

PRIVATE_KEY=${PRIVATE_KEY:-0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80}
CONTRACT_ADDRESS=${CONTRACT_ADDRESS:-0x5FbDB2315678afecb367f032d93F642f64180aa3}
GAS_LIMIT=${GAS_LIMIT:-1000000}
SLEEP_TIME=${SLEEP_TIME:-4}
RPC_URL=${RPC_URL:-"https://localhost:8545"}

echo "Starting miner... Press CTRL+C to stop"

while true; do
    PRIVATE_KEY=$PRIVATE_KEY \
    CONTRACT_ADDRESS=$CONTRACT_ADDRESS \
    GAS_LIMIT=$GAS_LIMIT \
    forge script script/MineAmethyst.s.sol:MineAmethyst \
        --rpc-url $RPC_URL \
        --broadcast \
        --gas-limit $GAS_LIMIT

    sleep $SLEEP_TIME
done
