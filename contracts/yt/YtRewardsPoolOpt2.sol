// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

// import "hardhat/console.sol";

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import "../libs/TokensTransfer.sol";

contract YtRewardsPoolOpt2 is Context, ReentrancyGuard {
  using Math for uint256;
  using EnumerableSet for EnumerableSet.AddressSet;

  /* ========== STATE VARIABLES ========== */

  address public immutable vault;
  uint256 public epochEndTimestamp;

  EnumerableSet.AddressSet internal _rewardsTokens;

  mapping(address => uint256) public ytSum;
  mapping(address => uint256) public ytLastCollectTime;

  mapping(address => uint256) public rewardsPerTimeWeightedYt;  // (rewards token => rewards per Time-Weighted YT)
  mapping(address => mapping(address => uint256)) public userRewardsPerTimeWeightedYtPaid; 
  mapping(address => mapping(address => uint256)) public userRewards;

  uint256 internal _totalSupply;
  mapping(address => uint256) internal _balances;

  /* ========== CONSTRUCTOR ========== */

  constructor(address _vault, uint256 _epochEndTimestamp) {
    vault = _vault;
    epochEndTimestamp = _epochEndTimestamp;
  }

  /* ========== VIEWS ========== */

  function totalSupply() external view returns (uint256) {
    return _totalSupply;
  }

  function balanceOf(address user) external view returns (uint256) {
    return _balances[user];
  }

  function collectableYt(address user) public view returns (uint256, uint256) {
    uint256 ytCollectTimestamp = ytCollectTimestampApplicable();
    uint256 deltaTime = ytCollectTimestamp - ytLastCollectTime[user];
    uint256 deltaTimeWeightedYtAmount = ytSum[user] * deltaTime;

    // console.log('collectableYt, user yt: %s, epoch end time: %s, current time: %s', ytSum[user], epochEndTimestamp, block.timestamp);
    return (ytCollectTimestamp, deltaTimeWeightedYtAmount);
  }

  function earned(address user, address rewardsToken) public view returns (uint256) {
    return _balances[user].mulDiv(
      rewardsPerTimeWeightedYt[rewardsToken] - userRewardsPerTimeWeightedYtPaid[user][rewardsToken],
      1e36
    ) + userRewards[user][rewardsToken];
  }

  /// @dev No guarantees are made on the ordering
  function rewardsTokens() external view returns (address[] memory) {
    return _rewardsTokens.values();
  }

  function ytCollectTimestampApplicable() public view returns (uint256) {
    return Math.min(block.timestamp, epochEndTimestamp);
  }

  /* ========== MUTATIVE FUNCTIONS ========== */

  function collectYt() external nonReentrant {
    (uint256 ytCollectTimestamp, uint256 deltaTimeWeightedYtAmount) = collectableYt(_msgSender());
    if (deltaTimeWeightedYtAmount > 0) {
      _notifyYtCollectedForUser(_msgSender(), deltaTimeWeightedYtAmount);
    }

    ytLastCollectTime[_msgSender()] = ytCollectTimestamp;
  }

  function getRewards() external nonReentrant updateAllRewards(_msgSender()) {
    for (uint256 i = 0; i < _rewardsTokens.length(); i++) {
      address rewardsToken = _rewardsTokens.at(i);
      uint256 rewards = userRewards[_msgSender()][rewardsToken];
      if (rewards > 0) {
        userRewards[_msgSender()][rewardsToken] = 0;
        TokensTransfer.transferTokens(rewardsToken, address(this), _msgSender(), rewards);
        // console.log('getRewards, user: %s, token: %s, rewards: %s', _msgSender(), rewardsToken, rewards);
        emit RewardsPaid(_msgSender(), rewardsToken, rewards);
      }
    }
  }

  /* ========== RESTRICTED FUNCTIONS ========== */

  function notifyYtSwappedForUser(address user, uint256 deltaYtAmount) external nonReentrant onlyVault {
    require(user != address(0) && deltaYtAmount > 0, "Invalid input");

    emit YtSwapped(user, deltaYtAmount);

    (uint256 ytCollectTimestamp, uint256 deltaTimeWeightedYtAmount) = collectableYt(user);
    if (deltaTimeWeightedYtAmount > 0) {
      _notifyYtCollectedForUser(user, deltaTimeWeightedYtAmount);
    }

    ytSum[user] = ytSum[user] + deltaYtAmount;
    ytLastCollectTime[user] = ytCollectTimestamp;
  }

  function _notifyYtCollectedForUser(address user, uint256 deltaTimeWeightedYtAmount) internal updateAllRewards(user) {
    require(user != address(0) && deltaTimeWeightedYtAmount > 0, "Invalid input");

    _totalSupply = _totalSupply + deltaTimeWeightedYtAmount;
    _balances[user] = _balances[user] + deltaTimeWeightedYtAmount;

    emit TimeWeightedYtAdded(user, deltaTimeWeightedYtAmount);
  }

  function addRewards(address rewardsToken, uint256 rewardsAmount) external nonReentrant onlyVault {
    require(_totalSupply > 0, "Cannot add rewards without YT staked");
    require(rewardsAmount > 0, "Too small rewards amount");

    if (!_rewardsTokens.contains(rewardsToken)) {
      _rewardsTokens.add(rewardsToken);
      emit RewardsTokenAdded(rewardsToken);
    }

    TokensTransfer.transferTokens(rewardsToken, _msgSender(), address(this), rewardsAmount);

    rewardsPerTimeWeightedYt[rewardsToken] = rewardsPerTimeWeightedYt[rewardsToken] + rewardsAmount.mulDiv(1e36, _totalSupply);

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

  function _updateRewards(address user, address rewardsToken) internal {
    require(user != address(0), "Invalid address");
    userRewards[user][rewardsToken] = earned(user, rewardsToken);
    userRewardsPerTimeWeightedYtPaid[user][rewardsToken] = rewardsPerTimeWeightedYt[rewardsToken];
  }

  /* ========== EVENTS ========== */

  event RewardsTokenAdded(address indexed rewardsToken);

  event YtSwapped(address indexed user, uint256 deltaYtAmount);

  event TimeWeightedYtAdded(address indexed user, uint256 deltaTimeWeightedYtAmount);

  event RewardsAdded(address indexed rewardsToken, uint256 rewards);

  event RewardsPaid(address indexed user, address indexed rewardsToken, uint256 rewards);

}
