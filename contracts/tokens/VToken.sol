// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "../interfaces/IProtocolSettings.sol";
import "../interfaces/IVToken.sol";
import "../settings/ProtocolOwner.sol";

contract VToken is IVToken, ProtocolOwner, ERC20, ReentrancyGuard {

  IProtocolSettings public immutable settings;
  address public immutable vault;

  string internal _name_;
  string internal _symbol_;
  uint8 internal _decimals_;

  constructor(address _protocol, address _settings, string memory _name, string memory _symbol, uint8 _decimals)
    ProtocolOwner(_protocol) ERC20(_name, _symbol) {
    settings = IProtocolSettings(_settings);
    vault = _msgSender();
    _name_ = _name;
    _symbol_ = _symbol;
    _decimals_ = _decimals;
  }

  /* ================= IERC20 Functions ================ */

  function name() public view virtual override returns (string memory) {
    return _name_;
  }

  function symbol() public view virtual override returns (string memory) {
    return _symbol_;
  }

  function decimals() public view override returns (uint8) {
    return _decimals_;
  }

  /* ========== RESTRICTED FUNCTIONS ========== */

  function setName(string memory _name) external nonReentrant onlyOwner {
    _name_ = _name;
  }

  function setSymbol(string memory _symbol) external nonReentrant onlyOwner {
    _symbol_ = _symbol;
  }

  function mint(address to, uint256 amount) public nonReentrant onlyVault {
    _mint(to, amount);
  }

  function burn(address account, uint256 amount) public nonReentrant onlyVault {
    _burn(account, amount);
  }

  /* ============== MODIFIERS =============== */

  modifier onlyVault() {
    require(vault == _msgSender(), "Caller is not Vault");
    _;
  }
}
