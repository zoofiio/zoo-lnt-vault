// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "../interfaces/IVestingToken.sol";

contract VestingToken is IVestingToken, ERC20, ReentrancyGuard {

  address public immutable vault;
  uint8 internal _decimals_;

  constructor(
    address _vault, string memory _name, string memory _symbol, uint8 _decimals
  ) ERC20(_name, _symbol) {
    require(_vault != address(0), "Zero address detected");

    vault = _vault;
    _decimals_ = _decimals;
  }

  /* ================= IERC20 Functions ================ */

  function decimals() public view override returns (uint8) {
    return _decimals_;
  }

  /* ========== RESTRICTED FUNCTIONS ========== */

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
