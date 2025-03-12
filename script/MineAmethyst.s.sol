// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {Amethyst} from "../src/Amethyst.sol";

contract MineAmethyst is Script {
    function run() public {
        uint256 minerPrivateKey = vm.envUint("PRIVATE_KEY");
        address payable amethystAddress = payable(vm.envAddress("CONTRACT_ADDRESS"));

        Amethyst amethyst = Amethyst(amethystAddress);
        address miner = vm.addr(minerPrivateKey);
        console.log("Mining with address:", miner);


        vm.startBroadcast(minerPrivateKey);

        // Check if we need to stake
        uint256 currentStake = amethyst.getStake(miner);
        uint256 stakeRequired = amethyst.getMinStakeAmount();
        if (currentStake < stakeRequired) {
            uint256 stakeNeeded = stakeRequired - currentStake;
            console.log("Adding stake:", stakeNeeded);
            amethyst.stake{value: stakeNeeded}();
        }

        console.log("Starting mining...");
        uint256 numMines = amethyst.mineManual(4);

        if (numMines > 0) {
            console.log("Successfully mined!");
            console.log("Num Mines:", numMines);
            console.log("Current difficulty:", amethyst.getDifficulty());
        } else {
            console.log("Mining unsuccessful");
        }

        vm.stopBroadcast();
    }
}
