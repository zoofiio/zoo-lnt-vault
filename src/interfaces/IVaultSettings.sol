// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

interface IVaultSettings {

    struct ParamConfig {
        uint256 defaultValue;
        uint256 min;
        uint256 max;
    }

    event UpsertParamConfig(bytes32 indexed name, uint256 defaultValue, uint256 min, uint256 max);

    event UpdateParamValue(bytes32 indexed param, uint256 value);

    function settingDecimals() external view returns (uint256);

    function isValidParam(bytes32 param, uint256 value) external view returns (bool);

    function paramDefaultValue(bytes32 param) external view returns (uint256);

    function paramValue(bytes32 param) external view returns (uint256);

}
