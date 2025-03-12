// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import {UD60x18} from "@prb/math/src/UD60x18.sol";
import {convert} from "@prb/math/src/ud60x18/Conversions.sol";

import {State} from "./State.sol";
import {Difficulty} from "./Difficulty.sol";

contract Amethyst is ERC20 {
    //////////////
    //  Mining  //
    //////////////

    function mineManual(uint256 attempts) public returns (uint256 returnNumMines) {
        uint256 baseNonce = prepareToMine();

        uint256 attempt = 0;

        while (attempts > 0) {
            attempts -= 1;

            if (mineSingle(baseNonce, attempt)) {
                returnNumMines += 1;
            }
            attempt += 1;
        }
    }

    function prepareToMine() internal returns (uint256 returnBaseNonce) {
        require(miners[msg.sender].stake >= minStakeAmount, "Must be staked to mine");

        Difficulty.adjustStale(difficulty, state);

        returnBaseNonce = uint160(msg.sender) ^ block.prevrandao ^ State.getBlockNumber(state);
    }

    function mineSingle(uint256 baseNonce, uint256 attempt) internal returns (bool returnMineSuccess) {
        uint256 nonce;
        unchecked {
            nonce = baseNonce + attempt;
        }

        uint256 answer = uint256(keccak256(abi.encodePacked(nonce, blockhash(block.number - 1), block.prevrandao)));

        // Apply level
        answer >>= miners[msg.sender].level;

        // Apply stake multiplier
        // 1 ETH   -> log10(1e18) - 18   = 0
        // 10 ETH  -> log10(10e18) - 18  = 1
        // 100 ETH -> log10(100e18) - 18 = 2
        answer >>= Math.log10(miners[msg.sender].stake) - 18;

        uint256 mineBlockNumber;
        (returnMineSuccess, mineBlockNumber) = State.tryMine(state, difficulty, answer);

        if (returnMineSuccess) {
            _transfer(address(this), msg.sender, miningReward());
            emit Mine(msg.sender, mineBlockNumber, nonce);
            miners[msg.sender].mines += 1;
        }
    }

    function miningReward() public view returns (uint256 returnMiningReward) {
        returnMiningReward = 1 ether >> numHalvenings();
    }

    function numHalvenings() public view returns (uint256 returnHalvenings) {
        uint256 unminedAmy = balanceOf(address(this));

        // -log_2(100%)  => 0
        // -log_2(50%)   => 1
        // -log_2(25%)   => 2
        // -log_2(12.5%) => 3
        // ...
        // -log_2{\frac{UNMINED}{SUPPLY}}
        //   => Apply -log_2{\frac{1}{x}} = log_2{x}
        // log_2{\frac{SUPPLY}{UNMINED}}
        //   => Apply log_b (x/y) = log_b(x) - log_b(y)
        // log_2{SUPPLY} - log_2{UNMINED}

        UD60x18 halveningsExact = convert(TOTAL_SUPPLY).log2().sub(convert(unminedAmy).log2());

        returnHalvenings = convert(halveningsExact);
    }

    ////////////
    // Events //
    ////////////

    event Stake(address indexed miner, uint256 amount);
    event Unstake(address indexed miner, uint256 amount);

    event Upgrade(address indexed miner, uint256 level);

    event Mine(address indexed miner, uint256 indexed blockNumber, uint256 answer);

    event UpdateDifficulty(uint256 newDifficulty);
    event UpdateAdjustmentFactor(uint256 newAdjustmentFactor);
    event UpdateTargetBlocksPerEvmBlock(UD60x18 newTargetBlocksPerEvmBlock);

    ///////////
    // ADMIN //
    ///////////

    address public constant PHIL = 0xF660efF9868c8Ea6Fd6932Dd1932AC97aDBE3064;
    address public constant KEVIN = 0x623e60caf4500b2338523048a530693Fd98d9A42;
    address public constant ANDRE = 0x90e77a53f19289f403abCa48DC518E594be17068;

    modifier onlyAdmin() {
        require(msg.sender == PHIL || msg.sender == KEVIN || msg.sender == ANDRE, "Not authorized");
        _;
    }

    ////////////////
    // Properties //
    ////////////////

    // NOTE: this needs to be smaller than INT256 MAX (2**255)
    uint256 public constant TOTAL_SUPPLY = 26_384_978 ether; // Number is AMETHYST on dialpad

    // ERC20 override
    function totalSupply() public pure override returns (uint256) {
        return TOTAL_SUPPLY;
    }

    uint256 private constant minStakeAmount = 1 ether;

    function getMinStakeAmount() public pure returns (uint256) {
        return minStakeAmount;
    }

    ///////////
    // Chain //
    ///////////

    State.ChainState internal state;

    function getBlockNumber() public view returns (uint256 returnBlockNumber) {
        returnBlockNumber = State.getBlockNumber(state);
    }

    Difficulty.ChainDifficulty internal difficulty;

    function getDifficulty() public view returns (uint256 returnDifficulty) {
        returnDifficulty = Difficulty.getDifficulty(difficulty);
    }

    function getDifficultyProbability() public view returns (UD60x18 returnDifficultyProbability) {
        returnDifficultyProbability = Difficulty.getDifficultyProbability(difficulty);
    }

    function getAdjustmentFactor() public view returns (uint256 returnAdjustmentFactor) {
        returnAdjustmentFactor = Difficulty.getAdjustmentFactor(difficulty);
    }

    function getTargetBlocksPerEvmBlock() public view returns (UD60x18 returnTargetBlocksPerEvmBlock) {
        returnTargetBlocksPerEvmBlock = Difficulty.getTargetBlocksPerEvmBlock(difficulty);
    }

    function setDifficultyParams(
        uint256 _newDifficulty,
        uint256 _newAdjustmentFactor,
        UD60x18 _newTargetBlocksPerEvmBlock
    ) external onlyAdmin {
        (bool difficultyChanged, bool adjustmentFactorChanged, bool targetBlocksPerEvmBlockChanged) =
            Difficulty.setParams(difficulty, _newDifficulty, _newAdjustmentFactor, _newTargetBlocksPerEvmBlock);

        if (difficultyChanged) {
            emit UpdateDifficulty(_newDifficulty);
        }
        if (adjustmentFactorChanged) {
            emit UpdateAdjustmentFactor(_newAdjustmentFactor);
        }
        if (targetBlocksPerEvmBlockChanged) {
            emit UpdateTargetBlocksPerEvmBlock(_newTargetBlocksPerEvmBlock);
        }
    }

    ////////////
    // Miners //
    ////////////

    struct Miner {
        uint256 stake;
        uint256 level;
        uint256 mines;
    }

    mapping(address => Miner) public miners;

    function getStake(address miner) public view returns (uint256) {
        return miners[miner].stake;
    }

    function getLevel(address miner) public view returns (uint256) {
        return miners[miner].level;
    }

    function getMines(address miner) public view returns (uint256) {
        return miners[miner].mines;
    }

    ////////////////////
    // Initialization //
    ////////////////////

    constructor() ERC20("Purple Gem", "AMY") {
        State.setup(state);
        Difficulty.setup(difficulty);

        _mint(address(this), TOTAL_SUPPLY);
    }

    /////////////
    // Staking //
    /////////////

    receive() external payable {}

    function stake() public payable {
        require(msg.value >= minStakeAmount, "Stake amount too low");
        miners[msg.sender].stake += msg.value;
        emit Stake(msg.sender, msg.value);
    }

    function unstake(uint256 amount) public {
        require(miners[msg.sender].stake >= amount, "Insufficient stake");
        miners[msg.sender].stake -= amount;
        emit Unstake(msg.sender, amount);
        (bool success,) = msg.sender.call{value: amount}("");
        require(success, "Transfer failed");
    }

    ///////////////
    // Upgrading //
    ///////////////

    function ugpradeRequiredMonAmy(address miner) public view returns (uint256, uint256) {
        uint256 level = miners[miner].level;

        if (level == 0) {
            return (1 ether, 100 ether);
        } else if (level == 1) {
            return (10 ether, 1_000 ether);
        } else if (level == 2) {
            return (100 ether, 15_000 ether);
        } else if (level == 3) {
            return (1_000 ether, 250_000 ether);
        } else {
            revert("Already at max level");
        }
    }

    function upgrade() public payable {
        require(miners[msg.sender].stake >= minStakeAmount, "Must be staked to upgrade");

        (uint256 required_mon, uint256 required_amy) = ugpradeRequiredMonAmy(msg.sender);

        require(msg.value == required_mon, "Invalid MON upgrade amount");

        _transfer(msg.sender, address(this), required_amy);
        require(miners[msg.sender].stake >= minStakeAmount, "Must be staked after upgrade");
        miners[msg.sender].level += 1;
    }
}
