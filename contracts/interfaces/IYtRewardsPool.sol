// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

interface IYtRewardsPool {

  function totalSupply() external view returns (uint256);

  function addRewards(address rewardsToken, uint256 rewardsAmount) external;

  function notifyYtSwappedForUser(address user, uint256 deltaYTAmount) external;

}