// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract TokenRelease is OwnableUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable{
    using SafeERC20 for IERC20;

    error NoReleasePlan(address user);
    error ReleaseFinished();
    error NoPendingRelease();
    error TokenNotEnough(uint256 balance, uint256 require);
    event Withdraw(address user, uint256 amount);

    struct Plan {
        Release[] releases;
        uint256 lastWithdrawReleaseIndex;
        uint256 lastWithdrawTime;
    }

    struct Release {
        uint256 startTime;
        uint256 endTime;
        uint256 releasePerSecond;
    }

    IERC20 public releaseToken;
    mapping(address user => Plan) public userPlans;

    constructor() {
        _disableInitializers();
    }

    function initialize(IERC20 _releaseToken) external initializer {
        __Ownable_init_unchained(msg.sender);
        __UUPSUpgradeable_init_unchained();
        __ReentrancyGuard_init_unchained();

        releaseToken = _releaseToken;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {
        // can only call by owner
    }

    function initPlan(address user, Release[] memory releases) external onlyOwner {
        Plan memory plan;
        plan.releases = releases;
        userPlans[user] = plan;
    }

    function updatePlan(address user, uint256 index, Release memory release) external onlyOwner {
        Plan storage plan = userPlans[user];
        uint256 planLength = plan.releases.length;
        if (index < planLength) {
            plan.releases[index] = release;
        } else if (index == planLength) {
            plan.releases.push(release);
        }
    }

    function getPendingAmount(address user) external view returns (uint256) {
        return getPendingAmountToIndex(user, type(uint256).max);
    }

    function getPendingAmountToIndex(address user, uint256 targetIndex) public view returns (uint256) {
        Plan memory plan = userPlans[user];
        uint256 planLength = plan.releases.length;
        if (planLength == 0) {
            return 0;
        }
        uint256 maxIndex = planLength - 1;
        if (plan.lastWithdrawReleaseIndex > maxIndex) {
            return 0;
        }
        if (targetIndex > maxIndex) {
            targetIndex = maxIndex;
        }
        uint256 pendingAmount;
        uint256 currentTime = block.timestamp;
        uint256 lastWithdrawReleaseIndex = plan.lastWithdrawReleaseIndex;
        uint256 lastWithdrawTime = plan.lastWithdrawTime;
        while(lastWithdrawReleaseIndex <= targetIndex) {
            Release memory currentRelease = plan.releases[lastWithdrawReleaseIndex];
            if (currentTime < currentRelease.startTime || currentTime < lastWithdrawTime) {
                break;
            } else {
                uint256 startTime = Math.max(lastWithdrawTime, currentRelease.startTime);
                uint256 endTime = Math.min(currentTime, currentRelease.endTime);
                pendingAmount += (endTime - startTime) * currentRelease.releasePerSecond;
                lastWithdrawTime = endTime;
                if (endTime == currentRelease.endTime) {
                    lastWithdrawReleaseIndex += 1;
                } else {
                    break;
                }
            }
        }
        return pendingAmount;
    }

    function withdraw() external nonReentrant {
        withdrawToIndex(type(uint256).max);
    }

    function withdrawToIndex(uint256 targetIndex) public nonReentrant {
        Plan storage plan = userPlans[msg.sender];
        uint256 planLength = plan.releases.length;
        if (planLength == 0) {
            revert NoReleasePlan(msg.sender);
        }
        uint256 maxIndex = planLength - 1;
        if (plan.lastWithdrawReleaseIndex > maxIndex) {
            revert ReleaseFinished();
        }
        if (targetIndex > maxIndex) {
            targetIndex = maxIndex;
        }
        uint256 pendingAmount;
        uint256 currentTime = block.timestamp;
        while(plan.lastWithdrawReleaseIndex <= targetIndex) {
            Release memory currentRelease = plan.releases[plan.lastWithdrawReleaseIndex];
            if (currentTime < currentRelease.startTime || currentTime < plan.lastWithdrawTime) {
                break;
            } else {
                uint256 startTime = Math.max(plan.lastWithdrawTime, currentRelease.startTime);
                uint256 endTime = Math.min(currentTime, currentRelease.endTime);
                pendingAmount += (endTime - startTime) * currentRelease.releasePerSecond;
                plan.lastWithdrawTime = endTime;
                if (endTime == currentRelease.endTime) {
                    plan.lastWithdrawReleaseIndex += 1;
                } else {
                    break;
                }
            }
        }
        if (pendingAmount == 0) {
            revert NoPendingRelease();
        }
        uint256 balance = releaseToken.balanceOf(address(this));
        if (balance < pendingAmount) {
            revert TokenNotEnough(balance, pendingAmount);
        }
        releaseToken.safeTransfer(msg.sender, pendingAmount);
        emit Withdraw(msg.sender, pendingAmount);
    }
}
