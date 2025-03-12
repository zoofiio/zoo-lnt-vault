// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

interface INftStakingPool {

  function totalSupply() external view returns (uint256);

  function addRewards(address rewardsToken, uint256 rewardsAmount) external;

  function notifyNftDepositForUser(address user, uint256 tokenId, uint256 value) external;

  function notifyNftRedeemForUser(address user, uint256 tokenId, uint256 value) external;

}