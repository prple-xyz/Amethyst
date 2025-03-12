// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {convert} from "@prb/math/src/UD60x18.sol";
import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {Amethyst} from "../src/Amethyst.sol";
import {UD60x18, convert} from "@prb/math/src/UD60x18.sol";

import "@openzeppelin/contracts/utils/Strings.sol";

contract AmethystGasTest is Test {
    Amethyst public amethyst;

    function setUp() public {
        amethyst = new Amethyst();

        vm.deal(address(this), 100 ether);

        assertEq(amethyst.getStake(address(this)), 0);
        amethyst.stake{value: 1 ether}();
        assertEq(amethyst.getStake(address(this)), 1 ether);

        vm.prank(amethyst.ANDRE());
        amethyst.setDifficultyParams(type(uint256).max, 1e18, convert(5e17));

        uint256 numMines = amethyst.mineManual(1024);
        assertEq(numMines, 1024);
        vm.roll(block.number + 2 * 1024);

        vm.prank(amethyst.ANDRE());
        amethyst.setDifficultyParams(type(uint256).max, 1024, convert(5e17));
    }

    function setImpossibleDifficulty() internal {
        vm.prank(amethyst.PHIL());
        amethyst.setDifficultyParams(1, 1024, convert(1));
        vm.roll(block.number + 1);
    }

    function mineSecond() internal {
        amethyst.mineManual(1);
    }

    function test_gasCost_mine_first_A0x01_M0x00() public {
        setImpossibleDifficulty();
        vm.resetGasMetering();

        uint256 numMines = amethyst.mineManual(1);
        assertEq(numMines, 0);
    }

    function test_gasCost_mine_second_A0x01_M0x00() public {
        setImpossibleDifficulty();
        mineSecond();
        vm.resetGasMetering();

        uint256 numMines = amethyst.mineManual(1);
        assertEq(numMines, 0);
    }

    function test_gasCost_mine_first_A0x01_M0x01() public {
        uint256 numMines = amethyst.mineManual(1);
        assertEq(numMines, 1);
    }

    function test_gasCost_mine_second_A0x01_M0x01() public {
        mineSecond();
        vm.resetGasMetering();

        uint256 numMines = amethyst.mineManual(1);
        assertEq(numMines, 1);
    }

    function test_gasCost_mine_first_A0x10_M0x00() public {
        setImpossibleDifficulty();
        vm.resetGasMetering();

        uint256 numMines = amethyst.mineManual(16);
        assertEq(numMines, 0);
    }

    function test_gasCost_mine_second_A0x10_M0x00() public {
        setImpossibleDifficulty();
        mineSecond();
        vm.resetGasMetering();

        uint256 numMines = amethyst.mineManual(16);
        assertEq(numMines, 0);
    }

    function test_gasCost_mine_first_A0x10_M0x10() public {
        uint256 numMines = amethyst.mineManual(16);
        assertEq(numMines, 16);
    }

    function test_gasCost_mine_second_A0x10_M0x10() public {
        mineSecond();
        vm.resetGasMetering();

        uint256 numMines = amethyst.mineManual(16);
        assertEq(numMines, 16);
    }
}
