// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

interface IProtocolSettings {

  function treasury() external view returns (address);

  function decimals() external view returns (uint256);

  function isValidParam(bytes32 param, uint256 value) external view returns (bool);

  function paramDefaultValue(bytes32 param) external view returns (uint256);

  function vaultParamValue(address vault, bytes32 param) external view returns (uint256);

  function updateSelfParamValue(bytes32 param, uint256 value) external;
}