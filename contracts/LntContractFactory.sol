// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract LntContractFactory is ReentrancyGuard {

  // Generic method to deploy any contract with provided creation code and constructor arguments
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
  
  // Events
  event ContractDeployed(address indexed deployer, address indexed contractAddress);
}