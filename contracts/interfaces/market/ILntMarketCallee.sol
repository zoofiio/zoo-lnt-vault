// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

interface ILntMarketCallee {
  function lntMarketCall(address sender, uint amount0, uint amount1, bytes calldata data) external;
}
