// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {UD60x18, convert} from "@prb/math/src/UD60x18.sol";
import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {Difficulty} from "../src/Difficulty.sol";
import {State} from "../src/State.sol";

contract StateTest is Test {
    Difficulty.ChainDifficulty public difficulty;
    State.ChainState public state;

    function setUp() public {
        Difficulty.setup(difficulty);
        State.setup(state);

        vm.deal(address(this), 1 ether);
    }

    function test_blockNumber() public {
        assertEq(State.getBlockNumber(state), 0);
        State.tryMine(state, difficulty, 0);
        assertEq(State.getBlockNumber(state), 1);
    }

    function test_windowAvgBlocksPerEvmBlock() public {
        // 1 evmBlock (current), 0 chain blocks
        assertEq(State.computeWindowAvgBlocksPerEvmBlock(state).intoUint256(), convert(0).intoUint256());

        State.tryMine(state, difficulty, 0);
        // 1 evmBlock (current), 1 chain blocks
        assertEq(State.computeWindowAvgBlocksPerEvmBlock(state).intoUint256(), convert(1).intoUint256());

        vm.roll(2); // Moves from block 1 to 2
        // 2 evmBlocks, 1 chain block
        assertEq(State.computeWindowAvgBlocksPerEvmBlock(state).intoUint256(), convert(1).div(convert(2)).intoUint256());

        vm.roll(3); // Moves from block 2 to 3
        // 3 evmBlocks, 1 chain block
        assertEq(State.computeWindowAvgBlocksPerEvmBlock(state).intoUint256(), convert(1).div(convert(3)).intoUint256());

        State.tryMine(state, difficulty, 0);
        // 3 evmBlocks, 2 chain blocks
        assertEq(State.computeWindowAvgBlocksPerEvmBlock(state).intoUint256(), convert(2).div(convert(3)).intoUint256());

        State.tryMine(state, difficulty, 0);
        // 3 evmBlocks, 3 chain blocks
        assertEq(State.computeWindowAvgBlocksPerEvmBlock(state).intoUint256(), convert(1).intoUint256());

        State.tryMine(state, difficulty, 0);
        // 3 evmBlocks, 4 chain blocks
        assertEq(State.computeWindowAvgBlocksPerEvmBlock(state).intoUint256(), convert(4).div(convert(3)).intoUint256());

        vm.roll(4); // Moves from block 3 to 4
        // 4 evmBlocks, 4 chain blocks
        assertEq(State.computeWindowAvgBlocksPerEvmBlock(state).intoUint256(), convert(1).intoUint256());
    }
}
