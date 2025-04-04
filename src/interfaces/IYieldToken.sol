// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IYieldToken is IERC20 {

    event EpochEndTimestampUpdated(uint256 newEpochEndTimestamp);

    event RewardsAdded(address indexed rewardToken, uint256 amount, bool isTimeWeighted);

    event RewardsPaid(address indexed user, address indexed rewardToken, uint256 amount, bool isTimeWeighted);
    
    event TimeWeightedBalanceAdded(address indexed user, uint256 amount);

    function mint(address to, uint256 amount) external;

    function setEpochEndTimestamp(uint256 _epochEndTimestamp) external;

    function addRewards(address rewardToken, uint256 amount) external payable;

    function addTimeWeightedRewards(address rewardToken, uint256 amount) external payable;
    
}
