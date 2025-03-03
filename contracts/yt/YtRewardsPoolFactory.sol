// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "./YtRewardsPoolOpt1.sol";
import "./YtRewardsPoolOpt2.sol";
import "../interfaces/IYtRewardsPoolFactory.sol";
import "../interfaces/IZooProtocol.sol";
import "../settings/ProtocolOwner.sol";

contract YtRewardsPoolFactory is IYtRewardsPoolFactory, ReentrancyGuard, ProtocolOwner {

  constructor(
    address _protocol
  ) ProtocolOwner(_protocol) { }

  function createYtRewardsPoolOpt1(
    address _vault
  ) external nonReentrant onlyVault returns (address) {
    return address(new YtRewardsPoolOpt1(_vault));
  }

  function createYtRewardsPoolOpt2(
    address _vault, uint256 _epochEndTimestamp
  ) external nonReentrant onlyVault returns (address) {
    return address(new YtRewardsPoolOpt2(_vault, _epochEndTimestamp));
  }

  modifier onlyVault() virtual {
    require (IZooProtocol(protocol).isVault(_msgSender()), "Caller is not a Vault contract");
    _;
  }

}