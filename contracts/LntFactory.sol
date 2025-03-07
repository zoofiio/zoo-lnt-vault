// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";


import "./tokens/VestingToken.sol";

import "./interfaces/ILntVault.sol";

contract LntFactory is ReentrancyGuard {


  function createVT(
    address _vault, string memory _name, string memory _symbol, uint8 _decimals
  ) external nonReentrant returns (address) {
    address vt = address(new VestingToken(_vault, _name, _symbol, _decimals));
    ILntVault(_vault).initialize(vt);

    return vt;
  }

}