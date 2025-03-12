// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "./VestingToken.sol";
import "./YieldToken.sol";

contract LntTokenFactory is ReentrancyGuard {

  function createVT(
    address _vault, string memory _name, string memory _symbol
  ) external nonReentrant returns (address) {
    return address(new VestingToken(_vault, _name, _symbol));
  }

  function createYT(
    address _vault, string memory _name, string memory _symbol
  ) external nonReentrant returns (address) {
    return address(new YieldToken(_vault, _name, _symbol));
  }

}