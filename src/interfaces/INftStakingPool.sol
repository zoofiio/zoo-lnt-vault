// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

interface INftStakingPool {

  event RewardsTokenAdded(address indexed rewardsToken);

  event NftDeposite(address indexed user, uint256 tokenId, uint256 value, uint256 weight);
  
  event NftRedeem(address indexed user, uint256 tokenId, uint256 value, uint256 weight);

  event RewardsAdded(address indexed rewardsToken, uint256 rewards);

  event RewardsPaid(address indexed user, address indexed rewardsToken, uint256 rewards);

  function totalSupply() external view returns (uint256);

  function addRewards(address rewardsToken, uint256 rewardsAmount) external payable;

  function notifyNftDepositForUser(address user, uint256 tokenId, uint256 value, uint256 weight) external;

  function notifyNftRedeemForUser(address user, uint256 tokenId, uint256 value, uint256 weight) external;

}