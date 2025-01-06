// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

// import "hardhat/console.sol";

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/structs/DoubleEndedQueue.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import "../libs/Constants.sol";
import "../libs/TokensTransfer.sol";
import "../libs/VaultCalculator.sol";
import "../interfaces/INftStakingPool.sol";
import "../interfaces/INftStakingPoolFactory.sol";
import "../interfaces/IVToken.sol";
import "../interfaces/IVault.sol";
import "../interfaces/IYtRewardsPool.sol";
import "../interfaces/IYtRewardsPoolFactory.sol";
import "../interfaces/IZooProtocol.sol";
import "../settings/ProtocolOwner.sol";
import "../tokens/VToken.sol";

contract Vault is IVault, ReentrancyGuard, ProtocolOwner {
  using Math for uint256;
  using DoubleEndedQueue for DoubleEndedQueue.Bytes32Deque;
  using EnumerableSet for EnumerableSet.UintSet;
  using VaultCalculator for IVault;

  address public immutable settings;
  address public immutable nftStakingPool;
  address public immutable ytRewardsPoolFactory;

  address public immutable nftToken;
  address public immutable nftVestingToken;
  address public immutable vToken;

  bool public initialized;

  uint256 public nftVtAmount;  // VT
  uint256 public nftVestingEndTime;  // VE
  uint256 public nftVestingDuration;  // VD
  address public ytSwapPaymentToken;  // Effective from next epoch
  uint256 public ytSwapPrice; // Effective from next epoch

  uint8 public constant ytDecimals = 18;

  mapping(address => uint256) public accruedNftStakingRewards;

  uint256 internal _currentEpochId;  // default to 0
  DoubleEndedQueue.Bytes32Deque internal _allEpochIds;   // all Epoch Ids, start from 1
  mapping(uint256 => Constants.Epoch) internal _epochs;  // epoch id => epoch info

  /**
   * @dev
   * - deposit: nftTokenId in _nftDeposits
   * - claim deposit: nftTokenId in _nftDeposits && _claimedNftDeposits
   * - redeem: nftTokenId in _nftDeposits && _claimedNftDeposits && _nftRedeems
   * - claim redeem: nftTokenId removed from _nftDeposits && _claimedNftDeposits && _nftRedeems (so that user could deposit again)
   */
  EnumerableSet.UintSet internal _nftDeposits;  // nft token ids
  mapping(uint256 => Constants.NftDeposit) internal _nftDepositInfo;  // nft token id => nft deposit info
  EnumerableSet.UintSet internal _claimedNftDeposits;
  EnumerableSet.UintSet internal _nftRedeems;
  mapping(uint256 => Constants.NftRedeem) internal _nftRedeemInfo;

  mapping(uint256 => uint256) internal _yTokenTotalSupply;  // including yTokens hold by Vault
  mapping(uint256 => mapping(address => uint256)) internal _yTokenUserBalances;

  mapping(uint256 => uint256) internal _epochNextSwapX;
  mapping(uint256 => uint256) internal _epochNextSwapK0;

  constructor(
    address _protocol,
    address _settings,
    address _nftStakingPoolFactory,
    address _ytRewardsPoolFactory,
    address _nftToken,
    address _nftVestingToken,
    string memory _vTokenName, string memory _vTokenSymbol
  ) ProtocolOwner(_protocol) {
    require(_settings != address(0) && _nftStakingPoolFactory != address(0) && _ytRewardsPoolFactory != address(0) && _nftToken != address(0) && _nftVestingToken != address(0), "Zero address detected");

    settings = _settings;
    nftStakingPool = INftStakingPoolFactory(_nftStakingPoolFactory).createNftStakingPool(address(this));
    ytRewardsPoolFactory = _ytRewardsPoolFactory;

    nftToken = _nftToken;
    nftVestingToken = _nftVestingToken;
    vToken = address(new VToken(_protocol, _settings, _vTokenName, _vTokenSymbol, IERC20Metadata(nftVestingToken).decimals()));
  }

  /* ================= VIEWS ================ */

  function currentEpochId() public view returns (uint256) {
    require(_currentEpochId > 0, "No epochs yet");
    return _currentEpochId;
  }

  function epochIdCount() public view returns (uint256) {
    return _allEpochIds.length();
  }

  function epochIdAt(uint256 index) public view returns (uint256) {
    return uint256(_allEpochIds.at(index));
  }

  function epochInfoById(uint256 epochId) public view onlyValidEpochId(epochId) returns (Constants.Epoch memory) {
    return _epochs[epochId];
  }

  function nftDepositIds() public view returns (uint256[] memory) {
    return _nftDeposits.values();
  }

  function nftDepositInfo(uint256 nftTokenId) public view onlyDepositedNft(nftTokenId) returns (Constants.NftDeposit memory) {
    return _nftDepositInfo[nftTokenId];
  }

  function nftRedeemInfo(uint256 nftTokenId) public view onlyRedeemedNft(nftTokenId) returns (Constants.NftRedeem memory) {
    return _nftRedeemInfo[nftTokenId];
  } 

  function paramValue(bytes32 param) public view override returns (uint256) {
    return IProtocolSettings(settings).vaultParamValue(address(this), param);
  }

  function yTokenTotalSupply(uint256 epochId) public view onlyValidEpochId(epochId) returns (uint256) {
    return _yTokenTotalSupply[epochId];
  }

  function yTokenUserBalance(uint256 epochId, address user) public view onlyValidEpochId(epochId) returns (uint256) {
    return _yTokenUserBalances[epochId][user];
  }

  function epochNextSwapX(uint256 epochId) public view returns (uint256) {
    return _epochNextSwapX[epochId];
  }

  function epochNextSwapK0(uint256 epochId) public view returns (uint256) {
    return _epochNextSwapK0[epochId];
  }

  function ytNewEpoch() public view returns (uint256) {
    return (_claimedNftDeposits.length() - _nftRedeems.length()) * (10 ** ytDecimals);
  }

  function calcSwap(uint256 ytSwapPaymentAmount) public view onlyInitialized onlyValidEpochId(_currentEpochId) returns (uint256, uint256) {
    return IVault(this).doCalcSwap(ytSwapPaymentAmount);
  }

  function Y() public view onlyInitialized onlyValidEpochId(_currentEpochId) returns (uint256) {
    return IVault(this).calcY();
  }

  /* ========== MUTATIVE FUNCTIONS ========== */

  function batchDepositNft(uint256[] calldata nftTokenIds) external nonReentrant onUserAction {
    for (uint256 i = 0; i < nftTokenIds.length; i++) {
      _depositNft(nftTokenIds[i]);
    }
  }

  function depositNft(uint256 nftTokenId) external nonReentrant onUserAction {
    _depositNft(nftTokenId);
  }

  function batchClaimDepositNft(uint256[] calldata nftTokenIds) external nonReentrant onUserAction {
    for (uint256 i = 0; i < nftTokenIds.length; i++) {
      _claimDepositNft(nftTokenIds[i]);
    }
  }

  function claimDepositNft(uint256 nftTokenId) external nonReentrant onUserAction {
    _claimDepositNft(nftTokenId);
  }

  function batchRedeemNft(uint256[] calldata nftTokenIds) external nonReentrant onUserAction {
    for (uint256 i = 0; i < nftTokenIds.length; i++) {
      _redeemNft(nftTokenIds[i]);
    }
  }

  function redeemNft(uint256 nftTokenId) external nonReentrant onUserAction {
    _redeemNft(nftTokenId);
  }

  function batchClaimRedeemNft(uint256[] calldata nftTokenIds) external nonReentrant onUserAction {
    for (uint256 i = 0; i < nftTokenIds.length; i++) {
      _claimRedeemNft(nftTokenIds[i]);
    }
  }

  function claimRedeemNft(uint256 nftTokenId) external nonReentrant onUserAction {
    _claimRedeemNft(nftTokenId);
  }

  function swap(uint256 amount) external nonReentrant onlyInitialized noneZeroAmount(amount) onUserAction {
    require(_currentEpochId > 0);
    Constants.Epoch memory epoch = _epochs[_currentEpochId];
    require(block.timestamp <= epoch.startTime + epoch.duration, "Epoch ended");

    require(amount <= IERC20(epoch.ytSwapPaymentToken).balanceOf(_msgSender()));
    require(amount <= IERC20(epoch.ytSwapPaymentToken).allowance(_msgSender(), address(this)));
    require(_yTokenUserBalances[_currentEpochId][address(this)] > 0);

    TokensTransfer.transferTokens(address(epoch.ytSwapPaymentToken), _msgSender(), address(this), amount);

    uint256 fees = amount * paramValue("f2") / (10 ** IProtocolSettings(settings).decimals());
    if (fees > 0) {
      TokensTransfer.transferTokens(address(epoch.ytSwapPaymentToken), address(this), IProtocolSettings(settings).treasury(), fees);
    }
    uint256 netAmount = amount - fees;

    require(_epochNextSwapK0[_currentEpochId] > 0);
    (uint256 X, uint256 m) = calcSwap(netAmount);
    _epochNextSwapX[_currentEpochId] = X;

    uint256 yTokenAmount = m;
    require(_yTokenUserBalances[_currentEpochId][address(this)] >= yTokenAmount, "Not enough yTokens");
    _yTokenUserBalances[_currentEpochId][address(this)] = _yTokenUserBalances[_currentEpochId][address(this)] - yTokenAmount;
    _yTokenUserBalances[_currentEpochId][_msgSender()] = _yTokenUserBalances[_currentEpochId][_msgSender()] + yTokenAmount;
    
    emit Swap(_currentEpochId, _msgSender(), amount, fees, yTokenAmount);

    if (INftStakingPool(nftStakingPool).totalSupply() == 0) {
      accruedNftStakingRewards[epoch.ytSwapPaymentToken] = accruedNftStakingRewards[epoch.ytSwapPaymentToken] + netAmount;
    }
    else {
      uint256 totalRewards = Math.min(
        accruedNftStakingRewards[epoch.ytSwapPaymentToken] + netAmount,
        IERC20(epoch.ytSwapPaymentToken).balanceOf(address(this))
      );
      IERC20(epoch.ytSwapPaymentToken).approve(nftStakingPool, totalRewards);
      INftStakingPool(nftStakingPool).addRewards(epoch.ytSwapPaymentToken, totalRewards);
      accruedNftStakingRewards[epoch.ytSwapPaymentToken] = 0;  
    }

    IYtRewardsPool(epoch.ytRewardsPoolOpt1).notifyYtSwappedForUser(_msgSender(), yTokenAmount);
    IYtRewardsPool(epoch.ytRewardsPoolOpt2).notifyYtSwappedForUser(_msgSender(), yTokenAmount);
  }

  function claimNftVestingToken(uint256 amount) external nonReentrant onlyInitialized noneZeroAmount(amount) {
    require(IERC20(vToken).balanceOf(_msgSender()) >= amount, "Insufficient vToken balance");
    require(IERC20(nftVestingToken).balanceOf(address(this)) >= amount, "Insufficient token balance");

    IVToken(vToken).burn(_msgSender(), amount);
    TokensTransfer.transferTokens(nftVestingToken, address(this), _msgSender(), amount);

    emit NftVestingTokenClaimed(_msgSender(), amount);
  }

  /* ========== RESTRICTED FUNCTIONS ========== */

  function initialize(
    uint256 _epochDuration, uint256 _nftVtAmount, uint256 _nftVestingEndTime, uint256 _nftVestingDuration, address _ytSwapPaymentToken, uint256 _ytSwapPrice
  ) external nonReentrant onlyOwner {
    require(!initialized, "Already initialized");
    _initialize(_epochDuration, _nftVtAmount, _nftVestingEndTime, _nftVestingDuration, _ytSwapPaymentToken, _ytSwapPrice);
    initialized = true;
    emit Initialized(_epochDuration, _nftVtAmount, _nftVestingEndTime, _nftVestingDuration, _ytSwapPaymentToken, _ytSwapPrice);
  }

  function reInitialize(
    uint256 _epochDuration, uint256 _nftVtAmount, uint256 _nftVestingEndTime, uint256 _nftVestingDuration, address _ytSwapPaymentToken, uint256 _ytSwapPrice
  ) external nonReentrant onlyOwner onlyInitialized {
    _initialize(_epochDuration, _nftVtAmount, _nftVestingEndTime, _nftVestingDuration, _ytSwapPaymentToken, _ytSwapPrice);
    emit ReInitialized(_epochDuration, _nftVtAmount, _nftVestingEndTime, _nftVestingDuration, _ytSwapPaymentToken, _ytSwapPrice);
  }

  function _initialize(
    uint256 _epochDuration, uint256 _nftVtAmount, uint256 _nftVestingEndTime, uint256 _nftVestingDuration, address _ytSwapPaymentToken, uint256 _ytSwapPrice
  ) internal {
    require(_epochDuration > 0 && _nftVtAmount > 0 && _nftVestingDuration > 0 && _ytSwapPaymentToken != address(0) && _ytSwapPrice > 0, "Invalid parameters");
    // require(IERC20Metadata(_ytSwapPaymentToken).decimals() <= 18);

    nftVtAmount = _nftVtAmount;
    nftVestingEndTime = _nftVestingEndTime;
    nftVestingDuration = _nftVestingDuration;
    ytSwapPaymentToken = _ytSwapPaymentToken;
    ytSwapPrice = _ytSwapPrice;
    IProtocolSettings(settings).updateSelfParamValue("D", _epochDuration);
  }

  function startEpoch1() external nonReentrant onlyInitialized onlyOwner {
    require(_currentEpochId == 0, "Epoch 1 already started");

    _startNewEpoch();
  }

  function updateNftDepositClaimableTime(uint256 nftTokenId, uint256 claimableTime) external nonReentrant onlyOwner onlyInitialized onlyDepositedNft(nftTokenId) {
    require(claimableTime > block.timestamp, "Invalid claimable time");

    uint256 prevClaimableTime = _nftDepositInfo[nftTokenId].claimableTime;
    _nftDepositInfo[nftTokenId].claimableTime = claimableTime;
    emit UpdateNftDepositClaimableTime(nftTokenId, prevClaimableTime, claimableTime);
  }

  /**
   * @dev Deposit NFT vesting token to the pool for VT holders to claim. Admin could also directly transfer token to the pool.
   */
  function depositNftVestingToken(uint256 amount) external nonReentrant onlyOwner onlyInitialized noneZeroAmount(amount) {
    require(IERC20(nftVestingToken).balanceOf(_msgSender()) >= amount, "Insufficient token balance");
    TokensTransfer.transferTokens(nftVestingToken, _msgSender(), address(this), amount);
    emit NftVestingTokenDeposite(_msgSender(), amount);
  }

  function withdrawNftVestingToken(uint256 amount) external nonReentrant onlyOwner onlyInitialized noneZeroAmount(amount) {
    require(IERC20(nftVestingToken).balanceOf(address(this)) >= amount, "Insufficient token balance");
    TokensTransfer.transferTokens(nftVestingToken, address(this), _msgSender(), amount);
    emit NftVestingTokenWithdrawn(_msgSender(), amount);
  }

  function addYtRewards(address rewardsToken, uint256 amount, Constants.YtRewardsPoolOption opt) external nonReentrant onlyOwner onlyInitialized noneZeroAddress(rewardsToken) noneZeroAmount(amount) {
    IYtRewardsPool ytRewardsPool;
    if (opt == Constants.YtRewardsPoolOption.Opt1) {
      ytRewardsPool = IYtRewardsPool(_epochs[_currentEpochId].ytRewardsPoolOpt1);
    }
    else {
      ytRewardsPool = IYtRewardsPool(_epochs[_currentEpochId].ytRewardsPoolOpt2);
    }
    
    TokensTransfer.transferTokens(rewardsToken, _msgSender(), address(this), amount);
    IERC20(rewardsToken).approve(address(ytRewardsPool), amount);
    ytRewardsPool.addRewards(rewardsToken, amount);
  }

  /* ========== INTERNAL FUNCTIONS ========== */

  function _startNewEpoch() internal {
    _currentEpochId++;
    _allEpochIds.pushBack(bytes32(_currentEpochId));

    _epochs[_currentEpochId].epochId = _currentEpochId;
    _epochs[_currentEpochId].startTime = block.timestamp;
    _epochs[_currentEpochId].duration = paramValue("D");
    _epochs[_currentEpochId].ytSwapPaymentToken = ytSwapPaymentToken;
    _epochs[_currentEpochId].ytSwapPrice = ytSwapPrice;
    _epochs[_currentEpochId].ytRewardsPoolOpt1 = IYtRewardsPoolFactory(ytRewardsPoolFactory).createYtRewardsPoolOpt1(address(this));
    _epochs[_currentEpochId].ytRewardsPoolOpt2 = IYtRewardsPoolFactory(ytRewardsPoolFactory).createYtRewardsPoolOpt2(address(this), _epochs[_currentEpochId].startTime + _epochs[_currentEpochId].duration);

    emit EpochStarted(_currentEpochId, block.timestamp, paramValue("D"));

    uint256 yTokenAmount = ytNewEpoch();
    _yTokenTotalSupply[_currentEpochId] = yTokenAmount;
    _yTokenUserBalances[_currentEpochId][address(this)] = yTokenAmount;

    // initialize swap params
    uint256 N = _yTokenUserBalances[_currentEpochId][address(this)];
    (uint256 X, uint256 k0) = IVault(this).calcInitSwapParams(N, _epochs[_currentEpochId].ytSwapPaymentToken, _epochs[_currentEpochId].ytSwapPrice);
    _epochNextSwapX[_currentEpochId] = X;
    _epochNextSwapK0[_currentEpochId] = k0;
  }

  function _depositNft(uint256 nftTokenId) internal {
    require(IERC721(nftToken).ownerOf(nftTokenId) == _msgSender(), "Not owner of NFT");
    require(!_nftDeposits.contains(nftTokenId), "Already deposited");  // should not happen

    IERC721(nftToken).transferFrom(_msgSender(), address(this), nftTokenId);
    require(IERC721(nftToken).ownerOf(nftTokenId) == address(this), "NFT transfer failed");

    _nftDeposits.add(nftTokenId);
    _nftDepositInfo[nftTokenId] = Constants.NftDeposit({
      owner: _msgSender(),
      nftTokenId: nftTokenId,
      depositTime: block.timestamp,
      depositAtEpoch: _currentEpochId,
      claimableTime: block.timestamp + paramValue("NftDepositLeadingTime") + 1,
      claimed: false,
      f1OnClaim: 0
    });
    emit NftDeposit(_currentEpochId, _msgSender(), nftTokenId);
  }

  function _claimDepositNft(uint256 nftTokenId) internal onlyInitialized onlyDepositedNft(nftTokenId) {
    require(_nftDepositInfo[nftTokenId].owner == _msgSender(), "Not owner of NFT");
    require(!_nftDepositInfo[nftTokenId].claimed, "Already claimed");
    require(block.timestamp >= _nftDepositInfo[nftTokenId].claimableTime, "Not claimable yet");

    uint256 leadingTimeEnd = _nftDepositInfo[nftTokenId].claimableTime;

    uint256 remainingTime = 0;
    if (leadingTimeEnd < nftVestingEndTime) {
      remainingTime = nftVestingEndTime - leadingTimeEnd;
    }

    uint256 vtAmount = nftVtAmount.mulDiv(Math.min(nftVestingDuration, remainingTime), nftVestingDuration);
    uint256 fees = vtAmount.mulDiv(paramValue("f1"), 10 ** IProtocolSettings(settings).decimals());
    uint256 vtNetAmount = vtAmount - fees;
    if (vtNetAmount > 0) {
      IVToken(vToken).mint(_msgSender(), vtNetAmount);
    }
    if (fees > 0) {
      IVToken(vToken).mint(IProtocolSettings(settings).treasury(), fees);
    }
    emit VTokenMinted(_msgSender(), nftTokenId, vtNetAmount, fees);

    _nftDepositInfo[nftTokenId].f1OnClaim = paramValue("f1");
    _nftDepositInfo[nftTokenId].claimed = true;
    emit NftDepositClaimed(_currentEpochId, _msgSender(), nftTokenId);

    _claimedNftDeposits.add(nftTokenId);

    INftStakingPool(nftStakingPool).notifyNftDepositForUser(_msgSender(), nftTokenId);
  }

  function _redeemNft(uint256 nftTokenId) internal onlyInitialized onlyValidEpochId(_currentEpochId) onlyDepositedNft(nftTokenId) {
    require(_nftDepositInfo[nftTokenId].owner == _msgSender(), "Not owner of NFT");
    require(_nftDepositInfo[nftTokenId].claimed, "Not claimed deposit yet");
    require(!_nftRedeems.contains(nftTokenId), "Already redeemed");

    _nftRedeems.add(nftTokenId);
    _nftRedeemInfo[nftTokenId] = Constants.NftRedeem({
      owner: _msgSender(),
      nftTokenId: nftTokenId,
      redeemTime: block.timestamp,
      redeemAtEpoch: _currentEpochId,
      claimableTime: Math.max(
        block.timestamp + paramValue( "NftRedeemWaitingPeriod") + 1,
        _epochs[_currentEpochId].startTime + _epochs[_currentEpochId].duration + 1
      ),
      claimed: false
    });
    emit NftRedeem(_currentEpochId, _msgSender(), nftTokenId);

    uint256 remainingTime = 0;
    if (_nftRedeemInfo[nftTokenId].redeemTime < nftVestingEndTime) {
      remainingTime = nftVestingEndTime - _nftRedeemInfo[nftTokenId].redeemTime;
    }
    uint256 vtAmount = nftVtAmount.mulDiv(Math.min(nftVestingDuration, remainingTime), nftVestingDuration);
    uint256 fees = vtAmount.mulDiv(_nftDepositInfo[nftTokenId].f1OnClaim, 10 ** IProtocolSettings(settings).decimals());
    uint256 vtBurnAmount = vtAmount - fees;
    if (vtBurnAmount > 0) {
      IVToken(vToken).burn(_msgSender(), vtBurnAmount);
    }
    emit VTokenBurned(_msgSender(), nftTokenId, vtBurnAmount);

    INftStakingPool(nftStakingPool).notifyNftRedeemForUser(_msgSender(), nftTokenId);
  }

  function _claimRedeemNft(uint256 nftTokenId) internal onlyInitialized onlyRedeemedNft(nftTokenId) {
    require(_nftRedeemInfo[nftTokenId].owner == _msgSender(), "Not owner of NFT");
    require(!_nftRedeemInfo[nftTokenId].claimed, "Already claimed");
    require(block.timestamp >= _nftRedeemInfo[nftTokenId].claimableTime, "Not claimable yet");

    IERC721(nftToken).transferFrom(address(this), _msgSender(), nftTokenId);

    _nftRedeemInfo[nftTokenId].claimed = true;

    _nftDeposits.remove(nftTokenId);
    delete _nftDepositInfo[nftTokenId];

    _claimedNftDeposits.remove(nftTokenId);
    _nftRedeems.remove(nftTokenId);
    delete _nftRedeemInfo[nftTokenId];

    emit NftRedeemClaimed(_currentEpochId, _msgSender(), nftTokenId);
  }

  /* ============== MODIFIERS =============== */

  modifier onlyInitialized() {
    require(initialized, "Not initialized");
    _;
  }

  modifier onlyValidEpochId(uint256 epochId) {
    require(
      epochId > 0 && epochId <= _currentEpochId && _epochs[epochId].startTime > 0,
      "Invalid epoch id"
    );
    _;
  }

  modifier onlyDepositedNft(uint256 nftTokenId) {
    require(_nftDeposits.contains(nftTokenId), "Not deposited");
    _;
  }

  modifier onlyRedeemedNft(uint256 nftTokenId) {
    require(_nftRedeems.contains(nftTokenId), "Not redeemed");
    _;
  }

  modifier onUserAction() {
    // Epoch 1 should be started by admin
    if (_currentEpochId > 0) {
      Constants.Epoch memory currentEpoch = _epochs[_currentEpochId];
      if (block.timestamp > currentEpoch.startTime + currentEpoch.duration) {
        _startNewEpoch();
      }
    }
    _;
  }

  modifier noneZeroAmount(uint256 amount) {
    require(amount > 0, "Amount must be greater than 0");
    _;
  }

  modifier noneZeroAddress(address addr) {
    require(addr != address(0), "Zero address detected");
    _;
  }

  /* =============== EVENTS ============= */

  event Initialized(uint256 epochDuration, uint256 nftVtAmount, uint256 nftVestingEndTime, uint256 nftVestingDuration, address ytSwapPaymentToken, uint256 ytSwapPrice);
  event ReInitialized(uint256 epochDuration, uint256 nftVtAmount, uint256 nftVestingEndTime, uint256 nftVestingDuration, address ytSwapPaymentToken, uint256 ytSwapPrice);

  event EpochStarted(uint256 epochId, uint256 startTime, uint256 duration);

  event NftDeposit(uint256 indexed epochId, address indexed user, uint256 indexed tokenId);
  event NftDepositClaimed(uint256 indexed epochId, address indexed user, uint256 indexed tokenId);

  event UpdateNftDepositClaimableTime(uint256 indexed nftTokenId, uint256 prevClaimableTime, uint256 newClaimableTime);

  event VTokenMinted(address indexed user, uint256 nftTokenId, uint256 vTokenNetAmount, uint256 vTokenFeesAmount);
  event VTokenBurned(address indexed user, uint256 nftTokenId, uint256 vTokenBurnAmount);

  event Swap(uint256 indexed epochId, address indexed user, uint256 ytSwapPaymentAmount, uint256 fees, uint256 yTokenAmount);

  event NftRedeem(uint256 indexed epochId, address indexed user, uint256 indexed tokenId);
  event NftRedeemClaimed(uint256 indexed epochId, address indexed user, uint256 indexed tokenId);

  event NftVestingTokenDeposite(address indexed sender, uint256 amount);
  event NftVestingTokenWithdrawn(address indexed sender, uint256 amount);
  event NftVestingTokenClaimed(address indexed user, uint256 amount);
}
