// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import "../interfaces/IYieldToken.sol";
import "../libs/TokensHelper.sol";

contract YieldToken is IYieldToken, ERC20, ReentrancyGuard {
  using Math for uint256;
  using EnumerableSet for EnumerableSet.AddressSet;

  /* ========== STATE VARIABLES ========== */

  uint256 public constant MAX_REWARDS_TOKENS = 20;
  uint256 public epochEndTimestamp;
  address public immutable vault;
  
  // State variables for standard rewards
  EnumerableSet.AddressSet private _rewardsTokens;
  mapping(address => uint256) public rewardsPerToken;
  mapping(address => mapping(address => uint256)) public userRewardsPerTokenPaid;
  mapping(address => mapping(address => uint256)) public userRewards;

  // State variables for time-weighted rewards
  EnumerableSet.AddressSet private _timeWeightedRewardsTokens;
  mapping(address => uint256) public timeWeightedRewardsPerToken;
  mapping(address => mapping(address => uint256)) public userTimeWeightedRewardsPerTokenPaid;
  mapping(address => mapping(address => uint256)) public userTimeWeightedRewards;

  // Time-weighted balance tracking
  uint256 internal _totalTimeWeightedBalance;
  mapping(address => uint256) internal _timeWeightedBalances;
  mapping(address => uint256) public lastCollectTime;
  
  /* ========== CONSTRUCTOR ========== */

  constructor(
    address _vault,
    string memory name,
    string memory symbol
  ) ERC20(name, symbol) {
    require(_vault != address(0), "Zero vault address");
    vault = _vault;
    epochEndTimestamp = type(uint256).max;
  }

  /* ========== VIEWS ========== */

  // Determine if an address is excluded from rewards
  function excludedFromRewards(address account) public view noneZeroAddress(account) returns (bool) {
    return account == vault || account == address(this);
  }

  // Query user's standard rewards
  function earned(address user, address rewardToken) public view noneZeroAddress(user) returns (uint256) {
    if (excludedFromRewards(user)) return 0;
    
    return balanceOf(user).mulDiv(
      rewardsPerToken[rewardToken] - userRewardsPerTokenPaid[user][rewardToken],
      1e36
    ) + userRewards[user][rewardToken];
  }

  // Get collectible time-weighted balance for a user
  function collectableTimeWeightedBalance(address user) public view noneZeroAddress(user) returns (uint256, uint256) {
    if (excludedFromRewards(user)) return (block.timestamp, 0);
    
    uint256 collectTimestamp = collectTimestampApplicable();
    uint256 deltaTime = collectTimestamp - lastCollectTime[user];
    uint256 deltaTimeWeightedAmount = balanceOf(user) * deltaTime;

    return (collectTimestamp, deltaTimeWeightedAmount);
  }

  // Get the applicable timestamp for collection (capped by epoch end)
  function collectTimestampApplicable() public view returns (uint256) {
    return Math.min(block.timestamp, epochEndTimestamp);
  }

  // Query user's time-weighted rewards
  function timeWeightedEarned(address user, address rewardToken) public view noneZeroAddress(user) returns (uint256) {
    if (excludedFromRewards(user)) return 0;
    
    return _timeWeightedBalances[user].mulDiv(
      timeWeightedRewardsPerToken[rewardToken] - userTimeWeightedRewardsPerTokenPaid[user][rewardToken],
      1e36
    ) + userTimeWeightedRewards[user][rewardToken];
  }

  // Calculate total supply eligible for rewards (excluding vault and this contract)
  function circulatingSupply() public view returns (uint256) {
    return totalSupply() - balanceOf(vault) - balanceOf(address(this));
  }

  // Get all reward tokens
  function getRewardsTokens() external view returns (address[] memory) {
    return _rewardsTokens.values();
  }

  // Get all time-weighted reward tokens
  function getTimeWeightedRewardsTokens() external view returns (address[] memory) {
    return _timeWeightedRewardsTokens.values();
  }

  // Get user's time-weighted balance
  function timeWeightedBalanceOf(address user) external view returns (uint256) {
    return _timeWeightedBalances[user];
  }

  // Get total time-weighted balance
  function totalTimeWeightedBalance() external view returns (uint256) {
    return _totalTimeWeightedBalance;
  }

  /* ========== MUTATIVE FUNCTIONS ========== */

  function collectTimeWeightedBalance() external nonReentrant {
    require(!excludedFromRewards(_msgSender()), "Address excluded from rewards");
    _collectTimeWeightedBalance(_msgSender());
  }

  function claimRewards() external nonReentrant {
    require(!excludedFromRewards(_msgSender()), "Address excluded from rewards");
    
    _updateRewards(_msgSender());
    _collectTimeWeightedBalance(_msgSender());
    _updateTimeWeightedRewards(_msgSender());
    
    _claimRewardsForUser(_msgSender());
  }

  /* ========== RESTRICTED FUNCTIONS ========== */

  function mint(address to, uint256 amount) external nonReentrant onlyVault {
    _mint(to, amount);
  }

  function setEpochEndTimestamp(uint256 _epochEndTimestamp) external nonReentrant onlyVault {
    require(_epochEndTimestamp > block.timestamp, "Invalid epoch end timestamp");
    epochEndTimestamp = _epochEndTimestamp;
    emit EpochEndTimestampUpdated(_epochEndTimestamp);
  }

  // Add standard rewards
  function addRewards(address rewardToken, uint256 amount) external payable override nonReentrant onlyVault {
    require(amount > 0, "Cannot add zero rewards");
    
    uint256 supply = circulatingSupply();
    require(supply > 0, "No circulating supply");
    
    if (!_rewardsTokens.contains(rewardToken)) {
      _rewardsTokens.add(rewardToken);
      require(_rewardsTokens.length() + _timeWeightedRewardsTokens.length() <= MAX_REWARDS_TOKENS, "Too many reward tokens");
    }
    
    if (rewardToken == Constants.NATIVE_TOKEN) {
      require(msg.value == amount, "Invalid msg.value");
    }
    else {
      require(msg.value == 0, "Invalid msg.value");
      TokensHelper.transferTokens(rewardToken, _msgSender(), address(this), amount);
    }
    
    rewardsPerToken[rewardToken] = rewardsPerToken[rewardToken] + amount.mulDiv(1e36, supply);
    
    emit RewardsAdded(rewardToken, amount, false);
  }

  // Add time-weighted rewards
  function addTimeWeightedRewards(address rewardToken, uint256 amount) external payable override nonReentrant onlyVault {
    require(amount > 0, "Cannot add zero rewards");
    
    uint256 supply = _totalTimeWeightedBalance;
    require(supply > 0, "No time-weighted balance supply");
    
    if (!_timeWeightedRewardsTokens.contains(rewardToken)) {
      _timeWeightedRewardsTokens.add(rewardToken);
      require(_rewardsTokens.length() + _timeWeightedRewardsTokens.length() <= MAX_REWARDS_TOKENS, "Too many reward tokens");
    }
    
    if (rewardToken == Constants.NATIVE_TOKEN) {
      require(msg.value == amount, "Invalid msg.value");
    }
    else {
      require(msg.value == 0, "Invalid msg.value");
      TokensHelper.transferTokens(rewardToken, _msgSender(), address(this), amount);
    }
    
    timeWeightedRewardsPerToken[rewardToken] = timeWeightedRewardsPerToken[rewardToken] + amount.mulDiv(1e36, supply);
    
    emit RewardsAdded(rewardToken, amount, true);
  }
  
  /* ========== INTERNAL FUNCTIONS ========== */

  // Automatically settle rewards for both users during transfers
  function _update(address from, address to, uint256 value) internal override {
    bool fromExcluded = excludedFromRewards(from);
    bool toExcluded = excludedFromRewards(to);
    
    if (from != address(0) && !fromExcluded) {
      _updateRewards(from);
      _collectTimeWeightedBalance(from);
      _updateTimeWeightedRewards(from);
      
      // Auto-claim rewards for sender
      _claimRewardsForUser(from);
    }
    
    if (to != address(0) && !toExcluded) {
      _updateRewards(to);
      _collectTimeWeightedBalance(to);
      _updateTimeWeightedRewards(to);
      
      // Auto-claim rewards for receiver
      _claimRewardsForUser(to);
    }
    
    super._update(from, to, value);
  }
  
  // Internal function to claim rewards for a user
  function _claimRewardsForUser(address user) internal {
    // Claim standard rewards
    for (uint i = 0; i < _rewardsTokens.length(); i++) {
      address rewardToken = _rewardsTokens.at(i);
      uint256 reward = userRewards[user][rewardToken];
      if (reward > 0) {
        userRewards[user][rewardToken] = 0;
        TokensHelper.transferTokens(rewardToken, address(this), user, reward);
        emit RewardPaid(user, rewardToken, reward, false);
      }
    }
    
    // Claim time-weighted rewards
    for (uint i = 0; i < _timeWeightedRewardsTokens.length(); i++) {
      address rewardToken = _timeWeightedRewardsTokens.at(i);
      uint256 reward = userTimeWeightedRewards[user][rewardToken];
      if (reward > 0) {
        userTimeWeightedRewards[user][rewardToken] = 0;
        TokensHelper.transferTokens(rewardToken, address(this), user, reward);
        emit RewardPaid(user, rewardToken, reward, true);
      }
    }
  }

  // Update user's standard rewards
  function _updateRewards(address user) internal {
    // Excluded addresses don't get rewards
    if (excludedFromRewards(user)) return;
    
    for (uint i = 0; i < _rewardsTokens.length(); i++) {
      address rewardToken = _rewardsTokens.at(i);
      userRewards[user][rewardToken] = earned(user, rewardToken);
      userRewardsPerTokenPaid[user][rewardToken] = rewardsPerToken[rewardToken];
    }
  }

  // Update user's time-weighted rewards
  function _updateTimeWeightedRewards(address user) internal {
    // Excluded addresses don't get time-weighted rewards
    if (excludedFromRewards(user)) return;
    
    for (uint i = 0; i < _timeWeightedRewardsTokens.length(); i++) {
      address rewardToken = _timeWeightedRewardsTokens.at(i);
      userTimeWeightedRewards[user][rewardToken] = timeWeightedEarned(user, rewardToken);
      userTimeWeightedRewardsPerTokenPaid[user][rewardToken] = timeWeightedRewardsPerToken[rewardToken];
    }
  }

  // Collect time-weighted balance for a user
  function _collectTimeWeightedBalance(address user) internal {
    if (excludedFromRewards(user)) return;
    
    (uint256 collectTimestamp, uint256 deltaTimeWeightedAmount) = collectableTimeWeightedBalance(user);
    
    if (deltaTimeWeightedAmount > 0) {
      _totalTimeWeightedBalance += deltaTimeWeightedAmount;
      _timeWeightedBalances[user] += deltaTimeWeightedAmount;
      
      emit TimeWeightedBalanceAdded(user, deltaTimeWeightedAmount);
    }

    lastCollectTime[user] = collectTimestamp;
  }

  /* ============== MODIFIERS =============== */

  modifier onlyVault() {
    require(_msgSender() == vault, "Caller is not the vault");
    _;
  }

  modifier noneZeroAddress(address addr) {
    require(addr != address(0), "Zero address detected");
    _;
  }

}
