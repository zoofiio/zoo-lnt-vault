// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

contract MockERC721 is ERC721, ERC721Burnable, Ownable, ReentrancyGuard {
  using EnumerableSet for EnumerableSet.AddressSet;

  EnumerableSet.AddressSet internal _testers;

  constructor(
    string memory name,
    string memory symbol
  ) Ownable(_msgSender()) ERC721(name, symbol) {
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

  function safeMint(address to, uint256 tokenId) public nonReentrant onlyTester {
    _safeMint(to, tokenId);
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