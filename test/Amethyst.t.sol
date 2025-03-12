// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {UD60x18, ud, convert} from "@prb/math/src/UD60x18.sol";
import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {Amethyst} from "../src/Amethyst.sol";
import {State} from "../src/State.sol";

contract AmethystTest is Test {
    Amethyst public amethyst;
    uint256 public constant MINIMUM_STAKE = 1 ether;
    uint256 public constant TARGET_BLOCK_TIME = 30;

    receive() external payable {}

    function setUp() public {
        amethyst = new Amethyst();
        vm.deal(address(this), 0);
    }

    function test_UnauthorizedAdmin() public {
        vm.expectRevert("Not authorized");
        amethyst.setDifficultyParams(0, 0, ud(0));
    }

    function test_AdminPrivileges() public {
        vm.prank(amethyst.PHIL());
        amethyst.setDifficultyParams(1, 2, ud(3));

        vm.prank(amethyst.KEVIN());
        amethyst.setDifficultyParams(6, 5, ud(4));

        vm.prank(amethyst.ANDRE());
        amethyst.setDifficultyParams(7, 8, ud(9));

        assertEq(amethyst.getMinStakeAmount(), MINIMUM_STAKE);

        assertEq(amethyst.getDifficulty(), 7);
        assertEq(amethyst.getAdjustmentFactor(), 8);
        assertEq(amethyst.getTargetBlocksPerEvmBlock().intoUint256(), 9);
    }

    function test_NoBalanceToStake() public {
        uint256 initialBalance = address(this).balance;
        assertEq(initialBalance, 0);
        vm.expectRevert();
        amethyst.stake{value: MINIMUM_STAKE}();
    }

    function test_StakeTooLow() public {
        vm.deal(address(this), 1 ether);
        vm.expectRevert("Stake amount too low");
        amethyst.stake{value: 0.5 ether}();
    }

    function test_ChainHalted() public {
        vm.prank(amethyst.KEVIN());
        amethyst.setDifficultyParams(0, 1024, convert(1));

        vm.deal(address(this), 1 ether);
        amethyst.stake{value: MINIMUM_STAKE}();

        vm.expectRevert("Chain halted");
        amethyst.mineManual(1);
    }

    function test_Unstake() public {
        vm.deal(address(this), 2 ether);
        amethyst.stake{value: MINIMUM_STAKE}();
        amethyst.unstake(MINIMUM_STAKE);
        assertEq(address(this).balance, 2 ether);
    }

    function test_MineSimple() public {
        vm.deal(address(this), 2 ether);
        uint256 initialBalance = address(this).balance;
        assertEq(initialBalance, 2 ether);
        amethyst.stake{value: MINIMUM_STAKE}();
        uint256 balanceAfterStake = address(this).balance;
        assertEq(balanceAfterStake, 1 ether);
        for (int256 i = 0; i < 10; i++) {
            amethyst.mineManual(1);
            vm.roll(block.number + 1);
        }
        assertEq(amethyst.balanceOf(address(this)), 10 ether);
        amethyst.unstake(MINIMUM_STAKE);
        assertEq(address(this).balance, 2 ether);
    }

    function test_MineFail() public {
        vm.deal(address(this), MINIMUM_STAKE);

        vm.prank(amethyst.KEVIN());
        amethyst.setDifficultyParams(20, 16, ud(0.5e18));

        amethyst.stake{value: MINIMUM_STAKE}();
        uint256 numMines = amethyst.mineManual(1);
        assertEq(numMines, 0);
    }

    function test_DifficultyAdjustment() public {
        // Set up array of miners
        address[] memory miners = new address[](3);
        for (uint256 i = 0; i < miners.length; i++) {
            miners[i] = address(uint160(i + 1));
            vm.deal(miners[i], 2 ether);
            vm.prank(miners[i]);
            amethyst.stake{value: MINIMUM_STAKE}();
        }

        uint256 difficulty = amethyst.getDifficulty();
        for (uint256 i = 0; i <= State.windowSize; i++) {
            for (uint256 miner = 0; miner < miners.length; miner++) {
                vm.prank(miners[miner]);
                amethyst.mineManual(10);
            }
            vm.roll(block.number + 10);
        }
        uint256 difficulty2 = amethyst.getDifficulty();
        assertLt(difficulty2, difficulty);

        difficulty = amethyst.getDifficulty();
        for (uint256 i = 0; i <= 2 * State.windowSize; i++) {
            if (i % 2 == 0) {
                // Only have one miner mine per block to target 0.5 winners
                vm.prank(miners[0]);
                amethyst.mineManual(10);
            }
            vm.roll(block.number + 10);
        }
        uint256 difficulty3 = amethyst.getDifficulty();
        assertGt(difficulty3, difficulty2);
    }

    function test_StaleHighDifficulty() public {
        vm.deal(address(this), 2 ether);
        amethyst.stake{value: MINIMUM_STAKE}();
        amethyst.mineManual(1);

        vm.prank(amethyst.KEVIN());
        amethyst.setDifficultyParams(1_000_000_000, 512, ud(0.5e18));
        uint256 initialDifficulty = amethyst.getDifficulty();
        assertEq(initialDifficulty, 1_000_000_000);

        for (uint256 i = 0; i <= State.windowSize; i++) {
            amethyst.mineManual(1);
            vm.roll(block.number + 10);
        }
        uint256 newDifficulty = amethyst.getDifficulty();
        console.log("new difficulty:", newDifficulty);
        assert(newDifficulty > initialDifficulty);
    }
}
