// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {UD60x18, convert, ud} from "@prb/math/src/UD60x18.sol";
import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {Difficulty} from "../src/Difficulty.sol";
import {State} from "../src/State.sol";

contract DifficultyStorageTest is Test {
    Difficulty.ChainDifficulty public difficulty;
    State.ChainState public state;

    function setUp() public {
        Difficulty.setup(difficulty);
        State.setup(state);

        vm.deal(address(this), 1 ether);
    }

    /////////////
    // Storage //
    /////////////

    function test_defaultParams() public view {
        assertEq(Difficulty.getDifficulty(difficulty), type(uint256).max);
        assertEq(Difficulty.getAdjustmentFactor(difficulty), 1024);
        assertEq(Difficulty.getTargetBlocksPerEvmBlock(difficulty).intoUint256(), 1 ether / 2);
    }

    function test_setParams_valid() public {
        Difficulty.setParams(difficulty, 2, 3, convert(4));

        assertEq(Difficulty.getDifficulty(difficulty), 2);
        assertEq(Difficulty.getAdjustmentFactor(difficulty), 3);
        assertEq(Difficulty.getTargetBlocksPerEvmBlock(difficulty).intoUint256(), 4 ether);
    }

    ////////////
    // Memory //
    ////////////

    function test_update() public {
        uint256 adjustmentFactor = 1024;
        uint256 chainBlocksPerEvmBlock = 2;

        uint256 fixedPrecisionLoss1 = 2 * (adjustmentFactor - 1);
        uint256 fixedPrecisionLoss2 = fixedPrecisionLoss1 * 2;

        (bool mineSuccess1,) = State.tryMine(state, difficulty, 0);
        assert(mineSuccess1);
        // Check that other params didn't change
        assertEq(Difficulty.getAdjustmentFactor(difficulty), adjustmentFactor);
        assertEq(Difficulty.getTargetBlocksPerEvmBlock(difficulty).intoUint256(), 1 ether / 2);

        // 1 chain block, target is 1 chain block every 2 evm blocks

        uint256 newDifficulty1 = ud(type(uint256).max).div(convert(uint256(adjustmentFactor * chainBlocksPerEvmBlock)))
            .mul(convert(uint256(adjustmentFactor * chainBlocksPerEvmBlock - 1))).add(ud(fixedPrecisionLoss1)).intoUint256();
        assertEq(Difficulty.getDifficulty(difficulty), newDifficulty1);

        (bool mineSuccess2,) = State.tryMine(state, difficulty, 0);
        assert(mineSuccess2);
        // Check that other params didn't change
        assertEq(Difficulty.getAdjustmentFactor(difficulty), adjustmentFactor);
        assertEq(Difficulty.getTargetBlocksPerEvmBlock(difficulty).intoUint256(), 1 ether / 2);

        // 2 chain blocks, target is 1 chain block every 2 evm blocks

        uint256 newDifficulty2 = ud(newDifficulty1).div(convert(uint256(2 * adjustmentFactor * chainBlocksPerEvmBlock)))
            .mul(convert(uint256(2 * adjustmentFactor * chainBlocksPerEvmBlock - 3))).add(ud(fixedPrecisionLoss2))
            .intoUint256();
        assertEq(Difficulty.getDifficulty(difficulty), newDifficulty2);
    }
}
