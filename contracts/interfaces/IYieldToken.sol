// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IYieldToken is IERC20 {

  event EpochEndTimestampUpdated(uint256 newEpochEndTimestamp);

  event RewardsAdded(address indexed rewardToken, uint256 amount, bool isTimeWeighted);

  event RewardPaid(address indexed user, address indexed rewardToken, uint256 amount, bool isTimeWeighted);
  
  event TimeWeightedBalanceAdded(address indexed user, uint256 amount);

  function mint(address to, uint256 amount) external;

  function addRewards(address rewardToken, uint256 amount) external;

  function addTimeWeightedRewards(address rewardToken, uint256 amount) external;
  
}
