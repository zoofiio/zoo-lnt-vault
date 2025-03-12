// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

interface ILntMarketFactory {
  event PairCreated(address indexed token0, address indexed token1, address pair, uint);
  event FeeToSet(address indexed feeTo);

  function feeTo() external view returns (address);

  function getPair(address tokenA, address tokenB) external view returns (address pair);
  function allPairs(uint) external view returns (address pair);
  function allPairsLength() external view returns (uint);

  function createPair(address tokenA, address tokenB) external returns (address pair);
}
