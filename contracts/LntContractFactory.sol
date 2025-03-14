// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "./interfaces/ILntContractFactory.sol";

contract LntContractFactory is ILntContractFactory, Ownable, ReentrancyGuard {

  address public treasury;

  constructor(address _treasury) Ownable(_msgSender()) {
    require(_treasury != address(0), "Zero address detected");
    treasury = _treasury;
  }

  /* ========== MUTATIVE FUNCTIONS ========== */

  function deployContract(
    bytes memory creationCode,
    bytes memory constructorArgs
  ) external nonReentrant returns (address addr) {
    bytes memory bytecode = abi.encodePacked(creationCode, constructorArgs);
    
    assembly {
      addr := create(0, add(bytecode, 32), mload(bytecode))
    }
    
    require(addr != address(0), "Contract deployment failed");
    
    emit ContractDeployed(msg.sender, addr);
    return addr;
  }

  /* ========== RESTRICTED FUNCTIONS ========== */

  function setTreasury(address newTreasury) external nonReentrant onlyOwner {
    require(newTreasury != address(0), "Zero address detected");
    require(newTreasury != treasury, "Same treasury");

    address prevTreasury = treasury;
    treasury = newTreasury;
    emit UpdateTreasury(prevTreasury, treasury);
  }
  
}