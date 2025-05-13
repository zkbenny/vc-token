// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract TokenReleaseDelay is
    Initializable,
    UUPSUpgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20 for IERC20;
    IERC20 public immutable zklToken;

    struct Release {
        uint256 startTime;
        uint256 amount;
        uint256 delayCompensationAmount;
        bool claimed;
    }

    mapping(address => Release[]) public userPlans;

    error NoRelease();
    error DuplicateInitiation(address user);
    error InvalidIndex(address user, uint256 index);
    error ReleaseClaimed(address user, uint256 index);
    error ReleaseNotStarted(address user, uint256 index);
    error TokenNotEnough(uint256 balance, uint256 require);

    event UserPlanInitiation(address indexed user, uint256 planLength);
    event UserReleaseUpdation(address indexed user, uint256 index, uint256 startTime, uint256 amount, uint256 delayCompensationAmount);
    event UserReleaseAddition(address indexed user, uint256 startTime, uint256 amount, uint256 delayCompensationAmount);
    event TokenClaim(address indexed user, uint256 amount);
    event ExcessTokenWithdraw(address indexed user, uint256 amount);

    constructor(IERC20 _zklToken) {
        _disableInitializers();
        zklToken = _zklToken;
    }

    function initialize() public initializer {
        __Ownable_init_unchained(msg.sender);
        __UUPSUpgradeable_init_unchained();
        __ReentrancyGuard_init_unchained();
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function initPlan(address user, Release[] memory releases) external onlyOwner {
        if (releases.length == 0) {
            revert NoRelease();
        }
        if (userPlans[user].length > 0) {
            revert DuplicateInitiation(user);
        }
        userPlans[user] = releases;
        emit UserPlanInitiation(user, releases.length);
    }

    function updateRelease(address user, uint256 index, uint256 startTime, uint256 amount, uint256 delayCompensationAmount) external onlyOwner {
        Release[] storage releases = userPlans[user];
        uint256 planLength = releases.length;
        if (index >= planLength) {
            revert InvalidIndex(user, index);
        }
        Release storage release = releases[index];
        if (release.claimed) {
            revert ReleaseClaimed(user, index);
        }
        release.startTime = startTime;
        release.amount = amount;
        release.delayCompensationAmount = delayCompensationAmount;
        emit UserReleaseUpdation(user, index, startTime, amount, delayCompensationAmount);
    }

    function addRelease(address user, uint256 startTime, uint256 amount, uint256 delayCompensationAmount) external onlyOwner {
        Release[] storage releases = userPlans[user];
        Release memory release;
        release.startTime = startTime;
        release.amount = amount;
        release.delayCompensationAmount = delayCompensationAmount;
        releases.push(release);
        emit UserReleaseAddition(user, startTime, amount, delayCompensationAmount);
    }

    function getClaimableAmount(address user) external view returns (uint256) {
        Release[] memory releases = userPlans[user];
        uint256 planLength = releases.length;
        uint256 claimAmount;
        for(uint i = 0; i < planLength; i++) {
            Release memory release = releases[i];
            if (release.claimed) {
                continue;
            }
            if (block.timestamp < release.startTime) {
                continue;
            }
            claimAmount += release.amount + release.delayCompensationAmount;
        }
        return claimAmount;
    }

    function claimIndex(uint256 index) external nonReentrant {
        address user = msg.sender;
        Release[] storage releases = userPlans[user];
        uint256 planLength = releases.length;
        if (index >= planLength) {
            revert InvalidIndex(user, index);
        }
        Release storage release = releases[index];
        if (release.claimed) {
            revert ReleaseClaimed(user, index);
        }
        if (block.timestamp < release.startTime) {
            revert ReleaseNotStarted(user, index);
        }
        release.claimed = true;
        uint256 claimAmount = release.amount + release.delayCompensationAmount;
        _claimToken(user, claimAmount);
    }

    function claimAll() external nonReentrant {
        address user = msg.sender;
        Release[] storage releases = userPlans[user];
        uint256 planLength = releases.length;
        uint256 claimAmount;
        for(uint i = 0; i < planLength; i++) {
            Release storage release = releases[i];
            if (release.claimed) {
                continue;
            }
            if (block.timestamp < release.startTime) {
                continue;
            }
            release.claimed = true;
            claimAmount += release.amount + release.delayCompensationAmount;
        }
        _claimToken(user, claimAmount);
    }

    function _claimToken(address to, uint256 claimAmount) internal {
        uint256 balance = zklToken.balanceOf(address(this));
        if (balance < claimAmount) {
            revert TokenNotEnough(balance, claimAmount);
        }
        zklToken.safeTransfer(to, claimAmount);
        emit TokenClaim(to, claimAmount);
    }

    function withdrawExcessToken(address to, uint256 amount) external onlyOwner {
        zklToken.safeTransfer(to, amount);
        emit ExcessTokenWithdraw(to, amount);
    }
}
