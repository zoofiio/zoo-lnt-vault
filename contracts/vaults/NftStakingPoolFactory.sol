// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "./NftStakingPool.sol";
import "../interfaces/INftStakingPoolFactory.sol";

contract NftStakingPoolFactory is INftStakingPoolFactory, ReentrancyGuard {

  function createNftStakingPool(
    address _vault
  ) external nonReentrant returns (address) {
    return address(new NftStakingPool(_vault));
  }

}