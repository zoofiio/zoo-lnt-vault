// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import "../libs/TokensTransfer.sol";
import "../settings/ProtocolOwner.sol";

contract YieldToken is ERC20, ProtocolOwner, ReentrancyGuard {
  using Math for uint256;
  using EnumerableSet for EnumerableSet.AddressSet;

  /* ========== STATE VARIABLES ========== */

  uint256 public MAX_REWARDS_TOKENS = 10;
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
    string memory name,
    string memory symbol,
    address _protocol,
    address _vault
  ) ERC20(name, symbol) ProtocolOwner(_protocol) {
    require(_vault != address(0), "Zero vault address");
    vault = _vault;
    epochEndTimestamp = type(uint256).max;
  }

  /* ========== VIEWS ========== */

  // Determine if an address is excluded from rewards
  function excludedFromRewards(address account) public view returns (bool) {
    return account == address(0) || account == vault || account == address(this);
  }

  // Query user's standard rewards
  function earned(address user, address rewardToken) public view returns (uint256) {
    // Excluded addresses don't earn rewards
    if (excludedFromRewards(user)) return 0;
    
    return balanceOf(user).mulDiv(
      rewardsPerToken[rewardToken] - userRewardsPerTokenPaid[user][rewardToken],
      1e36
    ) + userRewards[user][rewardToken];
  }

  // Get collectible time-weighted balance for a user
  function collectableTimeWeightedBalance(address user) public view returns (uint256, uint256) {
    // Excluded addresses don't accumulate time-weighted balance
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
  function timeWeightedEarned(address user, address rewardToken) public view returns (uint256) {
    // Excluded addresses don't earn time-weighted rewards
    if (excludedFromRewards(user)) return 0;
    
    return _timeWeightedBalances[user].mulDiv(
      timeWeightedRewardsPerToken[rewardToken] - userTimeWeightedRewardsPerTokenPaid[user][rewardToken],
      1e36
    ) + userTimeWeightedRewards[user][rewardToken];
  }

  // Calculate total supply eligible for rewards (excluding vault, address(0) and this contract)
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

  // User manually collects time-weighted balance
  function collectTimeWeightedBalance() external nonReentrant {
    require(!excludedFromRewards(_msgSender()), "Address excluded from rewards");
    _collectTimeWeightedBalance(_msgSender());
  }

  // User manually settles and claims rewards
  function claimRewards() external nonReentrant {
    require(!excludedFromRewards(_msgSender()), "Address excluded from rewards");
    
    _updateRewards(_msgSender());
    _collectTimeWeightedBalance(_msgSender());
    _updateTimeWeightedRewards(_msgSender());
    
    // Use the internal function to claim rewards
    _claimRewardsForUser(_msgSender());
  }

  /* ========== RESTRICTED FUNCTIONS ========== */

  function setEpochEndTimestamp(uint256 _epochEndTimestamp) external onlyVault {
    require(_epochEndTimestamp >= block.timestamp, "Invalid epoch end timestamp");
    epochEndTimestamp = _epochEndTimestamp;
    emit EpochEndTimestampUpdated(_epochEndTimestamp);
  }

  // Add standard rewards
  function addRewards(address rewardToken, uint256 amount) external onlyVault nonReentrant {
    require(amount > 0, "Cannot add zero rewards");
    require(_rewardsTokens.length() + _timeWeightedRewardsTokens.length() <= MAX_REWARDS_TOKENS, "Too many reward tokens");
    
    uint256 supply = circulatingSupply();  // Use circulating supply instead of total supply
    require(supply > 0, "No circulating supply");
    
    if (!_rewardsTokens.contains(rewardToken)) {
      _rewardsTokens.add(rewardToken);
    }
    
    // Transfer reward tokens from caller to contract
    TokensTransfer.transferTokens(rewardToken, _msgSender(), address(this), amount);
    
    // Update the reward rate for each token
    rewardsPerToken[rewardToken] = rewardsPerToken[rewardToken] + amount.mulDiv(1e36, supply);
    
    emit RewardsAdded(rewardToken, amount, false);
  }

  // Add time-weighted rewards
  function addTimeWeightedRewards(address rewardToken, uint256 amount) external onlyVault nonReentrant {
    require(amount > 0, "Cannot add zero rewards");
    require(_rewardsTokens.length() + _timeWeightedRewardsTokens.length() <= MAX_REWARDS_TOKENS, "Too many reward tokens");
    
    uint256 supply = _totalTimeWeightedBalance;
    require(supply > 0, "No time-weighted balance supply");
    
    if (!_timeWeightedRewardsTokens.contains(rewardToken)) {
      _timeWeightedRewardsTokens.add(rewardToken);
    }
    
    // Transfer reward tokens from caller to contract
    TokensTransfer.transferTokens(rewardToken, _msgSender(), address(this), amount);
    
    // Because time-weighting uses higher precision
    timeWeightedRewardsPerToken[rewardToken] = timeWeightedRewardsPerToken[rewardToken] + amount.mulDiv(1e36, supply);
    
    emit RewardsAdded(rewardToken, amount, true);
  }
  
  // Set the maximum number of reward tokens allowed
  function setMaxRewardsTokens(uint256 _maxRewardsTokens) external onlyOwner {
    require(_maxRewardsTokens >= _rewardsTokens.length() + _timeWeightedRewardsTokens.length(), "Cannot set max lower than current token count");
    require(_maxRewardsTokens <= 30, "Max rewards tokens cannot exceed 30");
    MAX_REWARDS_TOKENS = _maxRewardsTokens;
    
    emit MaxRewardsTokensUpdated(_maxRewardsTokens);
  }

  /* ========== INTERNAL FUNCTIONS ========== */

  // Automatically settle rewards for both users during transfers
  function _update(address from, address to, uint256 value) internal override {
    bool fromExcluded = excludedFromRewards(from);
    bool toExcluded = excludedFromRewards(to);
    
    // Handle rewards for non-excluded addresses
    if (from != address(0) && !fromExcluded) {
      // Update and collect rewards for the sender
      _updateRewards(from);
      _collectTimeWeightedBalance(from);
      _updateTimeWeightedRewards(from);
      
      // Auto-claim rewards for sender
      _claimRewardsForUser(from);
    }
    
    if (to != address(0) && !toExcluded) {
      // Update and collect rewards for the receiver
      _updateRewards(to);
      _collectTimeWeightedBalance(to);
      _updateTimeWeightedRewards(to);
      
      // Auto-claim rewards for receiver
      _claimRewardsForUser(to);
    }
    
    // Execute standard transfer operation
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
        TokensTransfer.transferTokens(rewardToken, address(this), user, reward);
        emit RewardPaid(user, rewardToken, reward, false);
      }
    }
    
    // Claim time-weighted rewards
    for (uint i = 0; i < _timeWeightedRewardsTokens.length(); i++) {
      address rewardToken = _timeWeightedRewardsTokens.at(i);
      uint256 reward = userTimeWeightedRewards[user][rewardToken];
      if (reward > 0) {
        userTimeWeightedRewards[user][rewardToken] = 0;
        TokensTransfer.transferTokens(rewardToken, address(this), user, reward);
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
    // Excluded addresses don't accumulate time-weighted balance
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

  /* ========== EVENTS ========== */

  event EpochEndTimestampUpdated(uint256 newEpochEndTimestamp);
  event RewardsAdded(address indexed rewardToken, uint256 amount, bool isTimeWeighted);
  event RewardPaid(address indexed user, address indexed rewardToken, uint256 amount, bool isTimeWeighted);
  event TimeWeightedBalanceAdded(address indexed user, uint256 amount);
  event MaxRewardsTokensUpdated(uint256 newMaxRewardsTokens);
}
