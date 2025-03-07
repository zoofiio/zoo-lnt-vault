// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/market/ILntMarketFactory.sol";
import "./LntMarket.sol";

contract LntMarketFactory is ILntMarketFactory, Ownable {
  address public feeTo;
  address public feeToSetter;

  mapping(address => mapping(address => address)) public getPair;
  address[] public allPairs;

  constructor() Ownable(msg.sender) {
    feeToSetter = msg.sender;
  }

  function allPairsLength() external view returns (uint) {
    return allPairs.length;
  }

  function createPair(address tokenA, address tokenB) external returns (address pair) {
    require(tokenA != tokenB, 'LntMarketFactory: IDENTICAL_ADDRESSES');
    (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
    require(token0 != address(0), 'LntMarketFactory: ZERO_ADDRESS');
    require(getPair[token0][token1] == address(0), 'LntMarketFactory: PAIR_EXISTS'); // single check is sufficient
    
    bytes memory bytecode = type(LntMarket).creationCode;
    bytes32 salt = keccak256(abi.encodePacked(token0, token1));
    assembly {
      pair := create2(0, add(bytecode, 32), mload(bytecode), salt)
    }
    
    LntMarket(pair).initialize(token0, token1);
    
    getPair[token0][token1] = pair;
    getPair[token1][token0] = pair; // populate mapping in the reverse direction
    allPairs.push(pair);
    
    emit PairCreated(token0, token1, pair, allPairs.length);
  }

  function setFeeTo(address _feeTo) external {
    require(msg.sender == feeToSetter, 'LntMarketFactory: FORBIDDEN');
    feeTo = _feeTo;
  }

  function setFeeToSetter(address _feeToSetter) external {
    require(msg.sender == feeToSetter, 'LntMarketFactory: FORBIDDEN');
    feeToSetter = _feeToSetter;
  }
}
