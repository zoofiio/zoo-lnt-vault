// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import "./interfaces/IVault.sol";
import "./interfaces/IZooProtocol.sol";
import "./settings/ProtocolSettings.sol";

contract ZooProtocol is IZooProtocol, Ownable, ReentrancyGuard {
  using EnumerableSet for EnumerableSet.AddressSet;

  EnumerableSet.AddressSet internal _assetTokens;
  EnumerableSet.AddressSet internal _vaults;
  mapping(address => EnumerableSet.AddressSet) _assetTokenToVaults;

  constructor() Ownable(_msgSender()) {}

  /* ========== Views ========= */

  function protocolOwner() public view returns (address) {
    return owner();
  }

  /* ========== Vault Operations ========== */

  function addVault(address vault) external nonReentrant onlyOwner {
    require(!_vaults.contains(vault), "Vault already added");
    _vaults.add(vault);

    address assetToken = IVault(vault).nftToken();
    if (!_assetTokens.contains(assetToken)) {
      _assetTokens.add(assetToken);
    }

    EnumerableSet.AddressSet storage tokenVaults = _assetTokenToVaults[assetToken];
    if (!tokenVaults.contains(vault)) {
      tokenVaults.add(vault);
    }

    emit VaultAdded(assetToken, vault);
  }

  function assetTokens() external view returns (address[] memory) {
    return _assetTokens.values();
  }

  function isVault(address vaultAddress) external view override returns (bool) {
    require(vaultAddress != address(0), "Zero address detected");
    return _vaults.contains(vaultAddress);
  }

  function isVaultAsset(address assetToken) external view override returns (bool) {
    require(assetToken != address(0), "Zero address detected");
    return _assetTokens.contains(assetToken);
  }

  function getVaultAddresses(address assetToken) external view returns (address[] memory) {
    require(assetToken != address(0) && _assetTokens.contains(assetToken), "Invalid asset token");
    return _assetTokenToVaults[assetToken].values();
  }

  /* =============== EVENTS ============= */

  event VaultAdded(address indexed assetToken, address vault);
}