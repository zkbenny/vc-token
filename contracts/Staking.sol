// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract Staking is
    Initializable,
    UUPSUpgradeable,
    OwnableUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20 for IERC20;
    IERC20 public immutable zklToken;
    uint256 public constant ONE_YEAR = 86400 * 365;
    uint256 public constant ONE_YEAR_IN_MONTHS = 12;
    uint256 public constant PERCENT_BASE = 100;

    enum StakingPeriod {
        ONE_MONTHS,
        THREE_MONTHS,
        SIX_MONTHS,
        TWELVE_MONTHS
    }

    struct DemandStake {
        uint256 amount;
        uint256 pendingReward;
        uint256 cnav;
    }

    struct StakeConfig {
        uint256 rate;
        uint256 cap;
    }

    struct FixedStake {
        StakingPeriod stakePeriod;
        uint256 amount;
        uint256 reward;
        uint256 stakeTime;
        bool claimed;
    }

    StakeConfig public demandConfig;
    uint256 public demandCNAV;
    uint256 public lastDemandCNAVUpdateTime;
    mapping(address => DemandStake) public userDemandStakes;
    uint256 public totalDemandStake;

    mapping(StakingPeriod => StakeConfig) public fixedConfigs;
    mapping(address => FixedStake[]) public userFixedStakes;
    mapping(StakingPeriod => uint256) public totalFixedStakes;
    uint256 public totalStake;

    error NewCapBelowCurrentStake();
    error StakeZeroAmount();
    error StakeExceedsCap();
    error UnStakeExceedsPrincipal();
    error InvalidStakeIndex();
    error FixedStakeClaimed(address user, uint256 index);
    error FixedStakeUnClaimable(address user, uint256 index, uint256 claimableTime);
    error ExcessWithdrawDuringStake();

    event DemandConfigUpdation(uint256 newRate, uint256 newCap);
    event FixedConfigUpdation(StakingPeriod indexed stakePeriod, uint256 newRate, uint256 newCap);
    event DemandStaked(address indexed user, uint256 amount);
    event DemandUnStaked(address indexed user, uint256 amount, uint256 reward);
    event FixedStaked(address indexed user, uint256 amount, StakingPeriod stakingPeriod);
    event FixedUnStaked(address indexed user, uint256 stakeIndex, uint256 amount, uint256 reward);
    event ExcessTokenWithdraw(address indexed to, uint256 amount);

    constructor(IERC20 _zklToken) {
        _disableInitializers();
        zklToken = _zklToken;
    }

    function initialize(StakeConfig memory _demandConfig, StakeConfig memory _oneMConfig, StakeConfig memory _threeMConfig, StakeConfig memory _sixMConfig, StakeConfig memory _twelveMConfig) public initializer {
        __Ownable_init_unchained(msg.sender);
        __UUPSUpgradeable_init_unchained();
        __ReentrancyGuard_init_unchained();
        __Pausable_init_unchained();

        demandConfig = _demandConfig;
        demandCNAV = 0;
        lastDemandCNAVUpdateTime = block.timestamp;
        fixedConfigs[StakingPeriod.ONE_MONTHS] = _oneMConfig;
        fixedConfigs[StakingPeriod.THREE_MONTHS] = _threeMConfig;
        fixedConfigs[StakingPeriod.SIX_MONTHS] = _sixMConfig;
        fixedConfigs[StakingPeriod.TWELVE_MONTHS] = _twelveMConfig;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function updateDemandConfig(StakeConfig memory newConfig) external onlyOwner {
        if (newConfig.cap < totalDemandStake) {
            revert NewCapBelowCurrentStake();
        }
        _updateDemandCNAV();
        demandConfig = newConfig;
        emit DemandConfigUpdation(newConfig.rate, newConfig.cap);
    }

    function updateDemandCNAV() external nonReentrant {
        _updateDemandCNAV();
    }

    function updateFixedConfig(StakingPeriod period, StakeConfig memory newConfig) external onlyOwner {
        if (newConfig.cap < totalFixedStakes[period]) {
            revert NewCapBelowCurrentStake();
        }
        fixedConfigs[period] = newConfig;
        emit FixedConfigUpdation(period, newConfig.rate, newConfig.cap);
    }

    function demandStake(uint256 amount) external nonReentrant whenNotPaused {
        if (amount == 0) {
            revert StakeZeroAmount();
        }
        if (totalDemandStake + amount > demandConfig.cap) {
            revert StakeExceedsCap();
        }
        _updateDemandCNAV();
        address user = msg.sender;
        DemandStake storage ds = userDemandStakes[user];
        ds.pendingReward += ds.amount * (demandCNAV - ds.cnav);
        ds.amount += amount;
        ds.cnav = demandCNAV;
        totalDemandStake += amount;
        totalStake += amount;
        zklToken.safeTransferFrom(user, address(this), amount);
        emit DemandStaked(user, amount);
    }

    function demandUnStake(uint256 amount) external nonReentrant {
        // allow amount to 0 to withdraw pending reward
        address user = msg.sender;
        DemandStake storage ds = userDemandStakes[user];
        if (ds.amount < amount) {
            revert UnStakeExceedsPrincipal();
        }
        _updateDemandCNAV();
        uint256 reward = ds.pendingReward + ds.amount * (demandCNAV - ds.cnav);
        ds.pendingReward = 0;
        ds.amount -= amount;
        ds.cnav = demandCNAV;
        totalDemandStake -= amount;
        totalStake -= amount;
        zklToken.safeTransfer(user, amount + reward);
        emit DemandUnStaked(user, amount, reward);
    }

    function fixedStake(uint256 amount, StakingPeriod stakePeriod) external nonReentrant whenNotPaused {
        if (amount == 0) {
            revert StakeZeroAmount();
        }
        StakeConfig memory config = fixedConfigs[stakePeriod];
        if (totalFixedStakes[stakePeriod] + amount > config.cap) {
            revert StakeExceedsCap();
        }
        uint256 months = _getStakePeriodInMonths(stakePeriod);
        uint256 reward = amount * months * config.rate / (PERCENT_BASE * ONE_YEAR_IN_MONTHS);
        address user = msg.sender;

        userFixedStakes[user].push(FixedStake(stakePeriod, amount, reward, block.timestamp, false));
        totalFixedStakes[stakePeriod] += amount;
        totalStake += amount;
        zklToken.safeTransferFrom(user, address(this), amount);
        emit FixedStaked(user, amount, stakePeriod);
    }

    function fixedUnStake(uint256 stakeIndex) external nonReentrant {
        address user = msg.sender;
        if (stakeIndex >= userFixedStakes[user].length) {
            revert InvalidStakeIndex();
        }

        FixedStake storage userStake = userFixedStakes[user][stakeIndex];
        if (userStake.claimed) {
            revert FixedStakeClaimed(user, stakeIndex);
        }
        uint256 months = _getStakePeriodInMonths(userStake.stakePeriod);
        uint256 claimableTime = userStake.stakeTime + months * 30 days;
        if (block.timestamp < claimableTime) {
            revert FixedStakeUnClaimable(user, stakeIndex, claimableTime);
        }
        userStake.claimed = true;
        totalFixedStakes[userStake.stakePeriod] -= userStake.amount;
        totalStake -= userStake.amount;

        zklToken.safeTransfer(user, userStake.amount + userStake.reward);
        emit FixedUnStaked(user, stakeIndex, userStake.amount, userStake.reward);
    }

    function withdrawExcessToken(address to, uint256 amount) external onlyOwner {
        if (totalStake > 0) {
            revert ExcessWithdrawDuringStake();
        }
        zklToken.safeTransfer(to, amount);
        emit ExcessTokenWithdraw(to, amount);
    }

    function getPendingDemandReward(address user) external view returns (uint256) {
        DemandStake memory ds = userDemandStakes[user];
        uint256 additionalCNAV = (block.timestamp - lastDemandCNAVUpdateTime) * demandConfig.rate / (PERCENT_BASE * ONE_YEAR);
        uint256 currentCNAV = demandCNAV + additionalCNAV;
        return ds.pendingReward + ds.amount * (currentCNAV - ds.cnav);
    }

    function _updateDemandCNAV() internal {
        demandCNAV += (block.timestamp - lastDemandCNAVUpdateTime) * demandConfig.rate / (PERCENT_BASE * ONE_YEAR);
        lastDemandCNAVUpdateTime = block.timestamp;
    }

    function _getStakePeriodInMonths(StakingPeriod stakePeriod) internal pure returns (uint256) {
        if (stakePeriod == StakingPeriod.ONE_MONTHS) {
            return 1;
        } else if (stakePeriod == StakingPeriod.THREE_MONTHS) {
            return 3;
        } else if (stakePeriod == StakingPeriod.SIX_MONTHS) {
            return 6;
        }  else {
            return 12;
        }
    }
}
