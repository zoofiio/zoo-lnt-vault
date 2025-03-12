// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

// import "hardhat/console.sol";

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import "../interfaces/IVaultSettings.sol";
import "../libs/Constants.sol";

abstract contract VaultSettings is IVaultSettings, ReentrancyGuard {
  using EnumerableSet for EnumerableSet.Bytes32Set;

  address public treasury;
  uint256 public constant settingDecimals = Constants.PROTOCOL_DECIMALS;

  EnumerableSet.Bytes32Set internal _paramsSet;
  mapping(bytes32 => ParamConfig) internal _paramConfigs;

  mapping(bytes32 => bool) internal _vaultParamsSet;
  mapping(bytes32 => uint256) internal _vaultParams;

  constructor(address _treasury_) {
    treasury = _treasury_;

    // Epoch duration. Default to 30 days, [1 hour, 5 year]
    _upsertParamConfig("D", 30 days, 1 hours, 1825 days);

    // Initial APR. Default to 200%, [1%, 10000%]
    _upsertParamConfig("APRi", 2 * 10 ** 10, 10 ** 8, 10 ** 12);

    // Commission rate. Default to 5%, [0%, 50%]
    _upsertParamConfig("f1", 5 * 10 ** 8, 0, 5 * 10 ** 9);

    // YT swap commission rate. Default to 5%, [0%, 50%]
    _upsertParamConfig("f2", 5 * 10 ** 8, 0, 5 * 10 ** 9);
  }

  /* ============== VIEWS =============== */

  function params() public view returns (bytes32[] memory) {
    return _paramsSet.values();
  }

  function isValidParam(bytes32 param, uint256 value) public view returns (bool) {
    if (param.length == 0 || !_paramsSet.contains(param)) {
      return false;
    }

    ParamConfig memory config = _paramConfigs[param];
    return config.min <= value && value <= config.max;
  }

  function paramConfig(bytes32 param) public view returns(ParamConfig memory) {
    require(param.length > 0, "Empty param name");
    require(_paramsSet.contains(param), "Invalid param name");
    return _paramConfigs[param];
  }

  function paramDefaultValue(bytes32 param) public view returns (uint256) {
    require(param.length > 0, "Empty param name");
    require(_paramsSet.contains(param), "Invalid param name");
    return paramConfig(param).defaultValue;
  }

  function paramValue(bytes32 param) public view returns (uint256) {
    require(param.length > 0, "Empty param name");

    if (_vaultParamsSet[param]) {
      return _vaultParams[param];
    }
    return paramDefaultValue(param);
  }

  /* ============ INTERNAL FUNCTIONS =========== */

  function _setTreasury(address newTreasury) internal {
    require(newTreasury != address(0), "Zero address detected");
    require(newTreasury != treasury, "Same treasury");

    address prevTreasury = treasury;
    treasury = newTreasury;
    emit UpdateTreasury(prevTreasury, treasury);
  }

  function _upsertParamConfig(bytes32 param, uint256 defaultValue, uint256 min, uint256 max) internal {
    require(param.length > 0, "Empty param name");
    require(min <= defaultValue && defaultValue <= max, "Invalid default value");

    if (_paramsSet.contains(param)) {
      ParamConfig storage config = _paramConfigs[param];
      config.defaultValue = defaultValue;
      config.min = min;
      config.max = max;
    }
    else {
      _paramsSet.add(param);
      _paramConfigs[param] = ParamConfig(defaultValue, min, max);
    }
    emit UpsertParamConfig(param, defaultValue, min, max);
  }

  function _updateParamValue(bytes32 param, uint256 value) internal {
    require(isValidParam(param, value), "Invalid param or value");

    _vaultParamsSet[param] = true;
    _vaultParams[param] = value;
    emit UpdateParamValue(param, value);
  }

}