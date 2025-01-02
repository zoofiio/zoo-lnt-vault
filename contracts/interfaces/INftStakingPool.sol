// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

interface INftStakingPool {

  function totalSupply() external view returns (uint256);

  function addRewards(address rewardsToken, uint256 rewardsAmount) external;

  function notifyNftDepositForUser(address user, uint256 nftTokenId) external;

  function notifyNftRedeemForUser(address user, uint256 nftTokenId) external;

}