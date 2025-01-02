// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "./NftStakingPool.sol";
import "../interfaces/INftStakingPoolFactory.sol";
import "../interfaces/IZooProtocol.sol";
import "../settings/ProtocolOwner.sol";

contract NftStakingPoolFactory is INftStakingPoolFactory, ReentrancyGuard, ProtocolOwner {

  constructor(
    address _protocol
  ) ProtocolOwner(_protocol) { }

  function createNftStakingPool(
    address _vault
  ) external nonReentrant returns (address) {
    return address(new NftStakingPool(_vault));
  }

}