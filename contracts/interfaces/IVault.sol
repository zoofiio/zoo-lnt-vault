// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import "../libs/Constants.sol";

interface IVault {

  function settings() external view returns (address);

  function currentEpochId() external view returns (uint256);

  function epochInfoById(uint256 epochId) external view returns (Constants.Epoch memory);

  function nftToken() external view returns (address);

  function vToken() external view returns (address);

  function paramValue(bytes32 param) external view returns (uint256);

  function ytDecimals() external view returns (uint8);

  function ytNewEpoch() external view returns (uint256);

  function ytSwapPaymentToken() external view returns (address);

  function ytSwapPrice() external view returns (uint256);

  function yTokenTotalSupply(uint256 epochId) external view returns (uint256);

  function yTokenUserBalance(uint256 epochId, address user) external view returns (uint256);

  function epochNextSwapX(uint256 epochId) external view returns (uint256);

  function epochNextSwapK0(uint256 epochId) external view returns (uint256);

}