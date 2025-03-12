// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

// import "hardhat/console.sol";

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import "../interfaces/INftStakingPool.sol";
import "../libs/TokensHelper.sol";

contract NftStakingPool is INftStakingPool, Context, ReentrancyGuard {
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
        TokensHelper.transferTokens(rewardsToken, address(this), _msgSender(), rewards);
        emit RewardsPaid(_msgSender(), rewardsToken, rewards);
      }
    }
  }

  /* ========== RESTRICTED FUNCTIONS ========== */

  function notifyNftDepositForUser(address user, uint256 tokenId, uint256 value, uint256 weight) external override nonReentrant onlyVault updateAllRewards(user) {
    require(user != address(0), "Invalid input");

    _totalSupply = _totalSupply + value * weight;
    _balances[user] = _balances[user] + value * weight;

    emit NftDeposite(user, tokenId, value, weight);
  }

  function notifyNftRedeemForUser(address user, uint256 tokenId, uint256 value, uint256 weight) external override nonReentrant onlyVault updateAllRewards(user) {
    require(user != address(0), "Invalid input");
    require(_balances[user] > 0, "No NFT staked");

    _totalSupply = _totalSupply - value * weight;
    _balances[user] = _balances[user] - value * weight;

    emit NftRedeem(user, tokenId, value, weight);
  }

  function addRewards(address rewardsToken, uint256 amount) external payable override nonReentrant onlyVault {
    require(_totalSupply > 0, "Cannot add rewards without YT staked");
    require(amount > 0, "Too small rewards amount");

    if (!_rewardTokens.contains(rewardsToken)) {
      _rewardTokens.add(rewardsToken);
      emit RewardsTokenAdded(rewardsToken);
    }

    if (rewardsToken == Constants.NATIVE_TOKEN) {
      require(msg.value == amount, "Invalid msg.value");
    }
    else {
      require(msg.value == 0, "Invalid msg.value");
      TokensHelper.transferTokens(rewardsToken, _msgSender(), address(this), amount);
    }

    rewardsPerNft[rewardsToken] = rewardsPerNft[rewardsToken] + amount.mulDiv(1e18, _totalSupply);

    emit RewardsAdded(rewardsToken, amount);
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

  function _updateRewards(address user, address rewardsToken) internal {
    require(user != address(0), "Invalid input");
    userRewards[user][rewardsToken] = earned(user, rewardsToken);
    userRewardsPerNftPaid[user][rewardsToken] = rewardsPerNft[rewardsToken];
  }

}
