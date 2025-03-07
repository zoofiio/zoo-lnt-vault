// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

interface INftStakingPoolFactory {

  function createNftStakingPool(address _vault) external returns (address);

}