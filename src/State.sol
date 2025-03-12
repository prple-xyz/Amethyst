// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {CircularBuffer} from "@openzeppelin/contracts/utils/structs/CircularBuffer.sol";
import {UD60x18, convert} from "@prb/math/src/UD60x18.sol";

import {Difficulty} from "./Difficulty.sol";

library State {
    uint256 constant windowSize = 1024;

    struct ChainState {
        uint256 blockNumber;
        CircularBuffer.Bytes32CircularBuffer recentBlockEvmBlockNumbers;
    }

    function setup(ChainState storage self) internal {
        self.blockNumber = 0;
        CircularBuffer.setup(self.recentBlockEvmBlockNumbers, windowSize);
    }

    function getBlockNumber(ChainState storage self) internal view returns (uint256 returnBlockNumber) {
        returnBlockNumber = self.blockNumber;
    }

    function computeWindowAvgBlocksPerEvmBlock(ChainState storage self)
        internal
        view
        returns (UD60x18 returnWindowAvgBlocksPerEvmBlock)
    {
        uint256 numRecentBlockEvmBlockNumbers = CircularBuffer.count(self.recentBlockEvmBlockNumbers);

        if (numRecentBlockEvmBlockNumbers == 0) {
            // In the first evm block, the rate is equal to the chain block number
            returnWindowAvgBlocksPerEvmBlock = convert(self.blockNumber);
        } else {
            uint256 currentEvmBlockNumber = block.number;
            uint256 earliestRecentBlockEvmBlockNumber =
                uint256(CircularBuffer.last(self.recentBlockEvmBlockNumbers, numRecentBlockEvmBlockNumbers - 1));

            require(
                currentEvmBlockNumber >= earliestRecentBlockEvmBlockNumber,
                "Mined block cannot be ahead of current evm block"
            );

            returnWindowAvgBlocksPerEvmBlock = convert(numRecentBlockEvmBlockNumbers).div(
                // We include the current block in the window so the rate is pessimistic
                convert(currentEvmBlockNumber + 1 - earliestRecentBlockEvmBlockNumber)
            );
        }
    }

    function tryMine(ChainState storage self, Difficulty.ChainDifficulty storage difficulty, uint256 answer)
        internal
        returns (bool returnIsSuccess, uint256 returnMinedBlockNumber)
    {
        if (Difficulty.isWithinDifficulty(difficulty, answer)) {
            returnIsSuccess = true;
            returnMinedBlockNumber = self.blockNumber;

            self.blockNumber += 1;
            CircularBuffer.push(self.recentBlockEvmBlockNumbers, bytes32(block.number));

            Difficulty.updateAfterMine(difficulty, self);
        }
    }
}
