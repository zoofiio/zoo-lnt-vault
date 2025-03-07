// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

// import "hardhat/console.sol";

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import "../libs/TokensTransfer.sol";

contract NftStakingPool is Context, ReentrancyGuard {
  using Math for uint256;
  using EnumerableSet for EnumerableSet.AddressSet;

  /* ========== STATE VARIABLES ========== */

  address public immutable vault;

  EnumerableSet.AddressSet internal _rewardTokens;

  mapping(address => uint256) public rewardsPerNft;
  mapping(address => mapping(address => uint256)) public userRewardsPerNftPaid; 
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
      rewardsPerNft[rewardsToken] - userRewardsPerNftPaid[user][rewardsToken],
      1e18
    ) + userRewards[user][rewardsToken];
  }

  /// @dev No guarantees are made on the ordering
  function rewardTokens() external view returns (address[] memory) {
    return _rewardTokens.values();
  }

  /* ========== MUTATIVE FUNCTIONS ========== */

  function getRewards() external nonReentrant updateAllRewards(_msgSender()) {
    for (uint256 i = 0; i < _rewardTokens.length(); i++) {
      address rewardsToken = _rewardTokens.at(i);
      uint256 rewards = userRewards[_msgSender()][rewardsToken];
      if (rewards > 0) {
        userRewards[_msgSender()][rewardsToken] = 0;
        TokensTransfer.transferTokens(rewardsToken, address(this), _msgSender(), rewards);
        emit RewardsPaid(_msgSender(), rewardsToken, rewards);
      }
    }
  }

  /* ========== RESTRICTED FUNCTIONS ========== */

  function notifyNftDepositForUser(address user, uint256 nftTokenId) external nonReentrant onlyVault updateAllRewards(user) {
    require(user != address(0), "Invalid input");

    _totalSupply = _totalSupply + 1;
    _balances[user] = _balances[user] + 1;

    emit NftDeposite(user, nftTokenId);
  }

  function notifyNftRedeemForUser(address user, uint256 nftTokenId) external nonReentrant onlyVault updateAllRewards(user) {
    require(user != address(0), "Invalid input");
    require(_balances[user] > 0, "No NFT staked");

    _totalSupply = _totalSupply - 1;
    _balances[user] = _balances[user] - 1;

    emit NftRedeem(user, nftTokenId);
  }

  function addRewards(address rewardsToken, uint256 rewardsAmount) external nonReentrant onlyVault updateRewards(address(0), rewardsToken) {
    require(_totalSupply > 0, "Cannot add rewards without YT staked");
    require(rewardsAmount > 0, "Too small rewards amount");

    if (!_rewardTokens.contains(rewardsToken)) {
      _rewardTokens.add(rewardsToken);
      emit RewardsTokenAdded(rewardsToken);
    }

    TokensTransfer.transferTokens(rewardsToken, _msgSender(), address(this), rewardsAmount);

    rewardsPerNft[rewardsToken] = rewardsPerNft[rewardsToken] + rewardsAmount.mulDiv(1e18, _totalSupply);

    emit RewardsAdded(rewardsToken, rewardsAmount);
  }

  /* ========== MODIFIERS ========== */

  modifier onlyVault() {
    require(_msgSender() == vault, "Caller is not Vault");
    _;
  }

  modifier updateAllRewards(address user) {
    for (uint256 i = 0; i < _rewardTokens.length(); i++) {
      address rewardsToken = _rewardTokens.at(i);
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
      userRewardsPerNftPaid[user][rewardsToken] = rewardsPerNft[rewardsToken];
    }
  }

  /* ========== EVENTS ========== */

  event RewardsTokenAdded(address indexed rewardsToken);

  event NftDeposite(address indexed user, uint256 nftTokenId);
  event NftRedeem(address indexed user, uint256 nftTokenId);

  event RewardsAdded(address indexed rewardsToken, uint256 rewards);

  event RewardsPaid(address indexed user, address indexed rewardsToken, uint256 rewards);

}
