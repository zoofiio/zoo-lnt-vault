// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "../ytswap/YTSwap.sol";

contract LntYTSwapFactory is ReentrancyGuard {

  function createYTSwap(
    address _vault
  ) external nonReentrant returns (address) {
    return address(new YTSwap(_vault));
  }

}