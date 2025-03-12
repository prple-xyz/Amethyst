// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/Math.sol";
import {UD60x18, convert, ud, ZERO} from "@prb/math/src/UD60x18.sol";
import {SD59x18, convert} from "@prb/math/src/SD59x18.sol";

import {State} from "./State.sol";

library Difficulty {
    struct ChainDifficulty {
        // difficulty X means statistically X/(2**256) mines succeeds
        uint256 difficulty;
        uint256 lastDifficultyUpdateEvmBlock;
        // Must be smaller than INT256 MAX (2**255)
        uint256 adjustmentFactor;
        // Must be a valid SD59x18
        UD60x18 targetBlocksPerEvmBlock;
    }

    function setup(ChainDifficulty storage self) internal {
        self.difficulty = type(uint256).max;
        self.lastDifficultyUpdateEvmBlock = block.number - 1;
        self.adjustmentFactor = State.windowSize;
        self.targetBlocksPerEvmBlock = convert(uint256(1)).div(convert(uint256(2)));
    }

    function getDifficulty(ChainDifficulty storage self) internal view returns (uint256 returnDifficulty) {
        returnDifficulty = self.difficulty;
    }

    function getDifficultyProbability(ChainDifficulty storage self)
        internal
        view
        returns (UD60x18 returnDifficultyProbability)
    {
        returnDifficultyProbability = ud(self.difficulty).div(ud(type(uint256).max));
    }

    function getAdjustmentFactor(ChainDifficulty storage self) internal view returns (uint256 returnAdjustmentFactor) {
        returnAdjustmentFactor = self.adjustmentFactor;
    }

    function getTargetBlocksPerEvmBlock(ChainDifficulty storage self)
        internal
        view
        returns (UD60x18 returnTargetBlocksPerEvmBlock)
    {
        returnTargetBlocksPerEvmBlock = self.targetBlocksPerEvmBlock;
    }

    function setParams(
        ChainDifficulty storage self,
        uint256 _newDifficulty,
        uint256 _newAdjustmentFactor,
        UD60x18 _newTargetBlocksPerEvmBlock
    ) internal returns (bool difficultyChanged, bool adjustmentFactorChanged, bool targetBlocksPerEvmBlockChanged) {
        require(_newAdjustmentFactor > 0, "Adjustment factor must be greater than zero");
        require(_newTargetBlocksPerEvmBlock > ZERO, "Target blocks per evm block must be greater than zero");

        difficultyChanged = self.difficulty != _newDifficulty;
        adjustmentFactorChanged = self.adjustmentFactor != _newDifficulty;
        targetBlocksPerEvmBlockChanged = self.targetBlocksPerEvmBlock != _newTargetBlocksPerEvmBlock;

        self.difficulty = _newDifficulty;
        self.lastDifficultyUpdateEvmBlock = block.number;
        self.adjustmentFactor = _newAdjustmentFactor;
        self.targetBlocksPerEvmBlock = _newTargetBlocksPerEvmBlock;
    }

    function computeDifficulty(ChainDifficulty storage self, State.ChainState storage chainState)
        internal
        view
        returns (uint256 returnDifficulty)
    {
        SD59x18 avgBlocksPerEvmBlock = State.computeWindowAvgBlocksPerEvmBlock(chainState).intoSD59x18();

        if (avgBlocksPerEvmBlock.isZero()) {
            require(State.getBlockNumber(chainState) == 0, "Chain halted");
            return self.difficulty;
        }

        // current rate: λ (avgBlocksPerEvmBlock)
        // target rate:  λ' (self.targetBlocksPerEvmBlock)
        // adjustment factor: z (self.adjustmentFactor)
        //
        // desired change in rate: t = (1/z) * (λ'-λ)
        // desired rate: λ + t =  λ * u
        // => multiplier: u = 1 + t/λ

        SD59x18 desiredChangeInBlocksPerEvmBlock = self.targetBlocksPerEvmBlock.intoSD59x18().sub(avgBlocksPerEvmBlock)
            .div(convert(int256(self.adjustmentFactor)));

        UD60x18 multiplier =
            desiredChangeInBlocksPerEvmBlock.div(avgBlocksPerEvmBlock).add(convert(int256(1))).intoUD60x18();

        // current difficulty: a (self.difficulty)
        // current mine probability per hash: p = a / (2**256)
        //
        // mining follows a Poisson process with rate parameter λ
        //   => avgBlocksPerEvmBlock is modeled by λ = H * p  where H is hashrate
        // desired λ' = λ * u
        //            = H * p * u
        // to achieve λ', we need:
        //            p' = p * u = (a / (2**256)) * u = (a * u) / (2**256)
        //
        // desired difficulty: a' = a * u
        //
        // This gives us higher difficulty when u > 1 when we're mining too slowly
        // and lower difficulty when u < 1 when we're mining too quickly
        //
        // check for overflow: a * u > 2**256
        //   => a > (2**256) / u

        if (multiplier > convert(uint256(1)) && ud(self.difficulty) >= ud(type(uint256).max).div(multiplier)) {
            return type(uint256).max;
        }

        uint256 oldDifficulty = self.difficulty;

        // Calculate new difficulty using the multiplier
        returnDifficulty = Math.max(1e9, ud(oldDifficulty).mul(multiplier).intoUint256());

        // Clamp by factor of 4 in both directions
        uint256 minDifficulty = oldDifficulty / 4;
        uint256 maxDifficulty;
        if (oldDifficulty >= type(uint256).max / 4) {
            maxDifficulty = type(uint256).max;
        } else {
            maxDifficulty = oldDifficulty * 4;
        }

        returnDifficulty = Math.min(Math.max(returnDifficulty, minDifficulty), maxDifficulty);
    }

    function isWithinDifficulty(ChainDifficulty storage self, uint256 value)
        internal
        view
        returns (bool returnIsWithinDifficulty)
    {
        returnIsWithinDifficulty = value <= self.difficulty;
    }

    function updateAfterMine(ChainDifficulty storage self, State.ChainState storage chainState) internal {
        self.difficulty = computeDifficulty(self, chainState);
        self.lastDifficultyUpdateEvmBlock = block.number;
    }

    function adjustStale(ChainDifficulty storage self, State.ChainState storage chainState) internal {
        require(self.difficulty != 0, "Chain halted");

        if (self.lastDifficultyUpdateEvmBlock < block.number) {
            self.difficulty = computeDifficulty(self, chainState);
            self.lastDifficultyUpdateEvmBlock = block.number;
        }
    }
}
