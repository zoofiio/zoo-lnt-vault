// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

// import "hardhat/console.sol";

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import "../libs/TokensTransfer.sol";

contract YtRewardsPoolOpt1 is Context, ReentrancyGuard {
  using Math for uint256;
  using EnumerableSet for EnumerableSet.AddressSet;

  /* ========== STATE VARIABLES ========== */

  address public immutable vault;

  EnumerableSet.AddressSet internal _rewardsTokens;

  mapping(address => uint256) public rewardsPerYt;
  mapping(address => mapping(address => uint256)) public userRewardsPerYtPaid; 
  mapping(address => mapping(address => uint256)) public userRewards;

  uint256 internal _totalSupply;
  mapping(address => uint256) internal _balances;

  /* ========== CONSTRUCTOR ========== */

  constructor(address _vault) {
    vault = _vault;
  }

  /* ========== VIEWS ========== */

  function totalSupply() external view returns (uint256) {
    return _totalSupply;
  }

  function balanceOf(address user) external view returns (uint256) {
    return _balances[user];
  }

  function earned(address user, address rewardsToken) public view returns (uint256) {
    return _balances[user].mulDiv(
      rewardsPerYt[rewardsToken] - userRewardsPerYtPaid[user][rewardsToken],
      1e18
    ) + userRewards[user][rewardsToken];
  }

  /// @dev No guarantees are made on the ordering
  function rewardsTokens() external view returns (address[] memory) {
    return _rewardsTokens.values();
  }

  /* ========== MUTATIVE FUNCTIONS ========== */

  function getRewards() external nonReentrant updateAllRewards(_msgSender()) {
    for (uint256 i = 0; i < _rewardsTokens.length(); i++) {
      address rewardsToken = _rewardsTokens.at(i);
      uint256 rewards = userRewards[_msgSender()][rewardsToken];
      if (rewards > 0) {
        userRewards[_msgSender()][rewardsToken] = 0;
        TokensTransfer.transferTokens(rewardsToken, address(this), _msgSender(), rewards);
        emit RewardsPaid(_msgSender(), rewardsToken, rewards);
      }
    }

  }

  /* ========== RESTRICTED FUNCTIONS ========== */

  function notifyYtSwappedForUser(address user, uint256 deltaYtAmount) external nonReentrant onlyVault updateAllRewards(user) {
    require(user != address(0) && deltaYtAmount > 0, "Invalid input");

    _totalSupply = _totalSupply + deltaYtAmount;
    _balances[user] = _balances[user] + deltaYtAmount;

    emit YtSwapped(user, deltaYtAmount);
  }

  function addRewards(address rewardsToken, uint256 rewardsAmount) external nonReentrant onlyVault updateRewards(address(0), rewardsToken) {
    require(_totalSupply > 0, "Cannot add rewards without YT staked");
    require(rewardsAmount > 0, "Too small rewards amount");

    if (!_rewardsTokens.contains(rewardsToken)) {
      _rewardsTokens.add(rewardsToken);
      emit RewardsTokenAdded(rewardsToken);
    }

    TokensTransfer.transferTokens(rewardsToken, _msgSender(), address(this), rewardsAmount);

    rewardsPerYt[rewardsToken] = rewardsPerYt[rewardsToken] + rewardsAmount.mulDiv(1e18, _totalSupply);

    emit RewardsAdded(rewardsToken, rewardsAmount);
  }

  /* ========== MODIFIERS ========== */

  modifier onlyVault() {
    require(_msgSender() == vault, "Caller is not Vault");
    _;
  }

  modifier updateAllRewards(address user) {
    for (uint256 i = 0; i < _rewardsTokens.length(); i++) {
      address rewardsToken = _rewardsTokens.at(i);
      _updateRewards(user, rewardsToken);
    }

    _;
  }

  modifier updateRewards(address user, address rewardsToken) {
    _updateRewards(user, rewardsToken);

    _;
  }

  function _updateRewards(address user, address rewardsToken) internal {
    if (user != address(0)) {
      userRewards[user][rewardsToken] = earned(user, rewardsToken);
      userRewardsPerYtPaid[user][rewardsToken] = rewardsPerYt[rewardsToken];
    }
  }

  /* ========== EVENTS ========== */

  event RewardsTokenAdded(address indexed rewardsToken);

  event YtSwapped(address indexed user, uint256 deltaYtAmount);

  event RewardsAdded(address indexed rewardsToken, uint256 rewards);

  event RewardsPaid(address indexed user, address indexed rewardsToken, uint256 rewards);

}
