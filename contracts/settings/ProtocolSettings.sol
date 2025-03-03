// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "hardhat/console.sol";

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import "../interfaces/IProtocolSettings.sol";
import "../libs/Constants.sol";
import "./ProtocolOwner.sol";

contract ProtocolSettings is IProtocolSettings, ProtocolOwner, ReentrancyGuard {
  using EnumerableSet for EnumerableSet.Bytes32Set;

  address internal _treasury;

  struct ParamConfig {
    uint256 defaultValue;
    uint256 min;
    uint256 max;
  }

  EnumerableSet.Bytes32Set internal _paramsSet;
  mapping(bytes32 => ParamConfig) internal _paramConfigs;

  mapping(address => mapping(bytes32 => bool)) internal _vaultParamsSet;
  mapping(address => mapping(bytes32 => uint256)) internal _vaultParams;

  constructor(address _protocol_, address _treasury_) ProtocolOwner(_protocol_) {
    _treasury = _treasury_;

    // Epoch duration. Default to 30 days, [1 hour, 5 year]
    _upsertParamConfig("D", 30 days, 1 hours, 1825 days);

    // NFT deposit leading time. Default to 3 days, [0.1 day, 1 year]
    _upsertParamConfig("NftDepositLeadingTime", 3 days, 0.1 days, 365 days);

    // NFT redeem waiting period. Default to 7 days, [0.1 day, 1 year]
    _upsertParamConfig("NftRedeemWaitingPeriod", 7 days, 0.1 days, 365 days);

    // Initial APR. Default to 200%, [1%, 10000%]
    _upsertParamConfig("APRi", 2 * 10 ** 10, 10 ** 8, 10 ** 12);

    // Commission rate. Default to 5%, [0%, 50%]
    _upsertParamConfig("f1", 5 * 10 ** 8, 0, 5 * 10 ** 9);

    // YT swap commission rate. Default to 5%, [0%, 50%]
    _upsertParamConfig("f2", 5 * 10 ** 8, 0, 5 * 10 ** 9);
  }

  /* ============== VIEWS =============== */

  function treasury() public view override returns (address) {
    return _treasury;
  }

  function decimals() public pure returns (uint256) {
    return Constants.PROTOCOL_DECIMALS;
  }

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

  function vaultParamValue(address vault, bytes32 param) public view returns (uint256) {
    require(protocol.isVault(vault), "Invalid vault");
    require(param.length > 0, "Empty param name");

    if (_vaultParamsSet[vault][param]) {
      return _vaultParams[vault][param];
    }
    return paramDefaultValue(param);
  }

  /* ============ MUTATIVE FUNCTIONS =========== */

  function setTreasury(address newTreasury) external nonReentrant onlyOwner {
    require(newTreasury != address(0), "Zero address detected");
    require(newTreasury != _treasury, "Same treasury");

    address prevTreasury = _treasury;
    _treasury = newTreasury;
    emit UpdateTreasury(prevTreasury, _treasury);
  }

  function upsertParamConfig(bytes32 param, uint256 defaultValue, uint256 min, uint256 max) external nonReentrant onlyOwner {
    _upsertParamConfig(param, defaultValue, min, max);
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

  function updateVaultParamValue(address vault, bytes32 param, uint256 value) external nonReentrant onlyOwner {
    _updateVaultParamValue(vault, param, value);
  }

  function updateSelfParamValue(bytes32 param, uint256 value) external nonReentrant {
    _updateVaultParamValue(_msgSender(), param, value);
  }

  function _updateVaultParamValue(address vault, bytes32 param, uint256 value) internal {
    require(protocol.isVault(vault), "Invalid vault");
    require(isValidParam(param, value), "Invalid param or value");

    _vaultParamsSet[vault][param] = true;
    _vaultParams[vault][param] = value;
    emit UpdateVaultParamValue(vault, param, value);
  }

  /* =============== EVENTS ============= */

  event UpdateTreasury(address prevTreasury, address newTreasury);

  event UpsertParamConfig(bytes32 indexed name, uint256 defaultValue, uint256 min, uint256 max);

  event UpdateVaultParamValue(address indexed vault, bytes32 indexed param, uint256 value);

}