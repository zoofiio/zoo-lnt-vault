// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

interface ILntContractFactory {

    event UpdateTreasury(address prevTreasury, address newTreasury);

    event ContractDeployed(address indexed deployer, address indexed contractAddress);

    function treasury() external view returns (address);

    function deployContract(bytes memory creationCode, bytes memory constructorArgs) external returns (address addr);

}
