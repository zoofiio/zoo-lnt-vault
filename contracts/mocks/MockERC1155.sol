// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Burnable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

contract MockERC1155 is ERC1155, ERC1155Burnable, Ownable, ReentrancyGuard {
  using EnumerableSet for EnumerableSet.AddressSet;

  EnumerableSet.AddressSet internal _testers;

  constructor() Ownable(_msgSender()) ERC1155("") {
    _setTester(owner(), true);
  }

  /* ================= VIEWS ================ */

  function getTestersCount() public view returns (uint256) {
    return _testers.length();
  }

  function getTester(uint256 index) public view returns (address) {
    require(index < _testers.length(), "Invalid index");
    return _testers.at(index);
  }

  function isTester(address account) public view returns (bool) {
    return _testers.contains(account);
  }

  /* ================= MUTATIVE FUNCTIONS ================ */

  function batchSetTesters(address[] calldata accounts, bool tester) external nonReentrant onlyOwner {
    for (uint256 i = 0; i < accounts.length; i++) {
      _setTester(accounts[i], tester);
    }
  }

  function setTester(address account, bool tester) external nonReentrant onlyOwner {
    _setTester(account, tester);
  }

  function mint(address account, uint256 id, uint256 amount, bytes memory data) public onlyTester {
    _mint(account, id, amount, data);
  }

  function mintBatch(address to, uint256[] memory ids, uint256[] memory amounts, bytes memory data) public onlyTester {
    _mintBatch(to, ids, amounts, data);
  }

  /* ========== INTERNAL FUNCTIONS ========== */

  function _setTester(address account, bool tester) internal {
    require(account != address(0), "Zero address detected");

    if (tester) {
      require(!_testers.contains(account), "Address is already tester");
      _testers.add(account);
    }
    else {
      require(_testers.contains(account), "Address was not tester");
      _testers.remove(account);
    }

    emit UpdateTester(account, tester);
  }

  /* ============== MODIFIERS =============== */

  modifier onlyTester() {
    require(isTester(_msgSender()), "Caller is not tester");
    _;
  }

  /* ========== EVENTS ========== */

  event UpdateTester(address indexed account, bool tester);

}