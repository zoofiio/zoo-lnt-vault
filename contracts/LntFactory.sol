// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract LntFactory is ReentrancyGuard {

  // Generic method to deploy any contract with provided creation code and constructor arguments
  function deployContract(
    bytes memory creationCode,
    bytes memory constructorArgs
  ) external nonReentrant returns (address deployed) {
    bytes memory bytecode = abi.encodePacked(creationCode, constructorArgs);
    
    assembly {
      deployed := create(0, add(bytecode, 32), mload(bytecode))
    }
    
    require(deployed != address(0), "Contract deployment failed");
    
    emit ContractDeployed(msg.sender, deployed, creationCode);
    return deployed;
  }
  
  // Events
  event ContractDeployed(address indexed deployer, address indexed contractAddress, bytes creationCode);
}