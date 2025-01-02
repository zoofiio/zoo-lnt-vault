// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

interface IYtRewardsPoolFactory {

  function createYtRewardsPoolOpt1(address vault) external returns (address);

  function createYtRewardsPoolOpt2(address vault, uint256 epochEndTimestamp) external returns (address);

}