// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

// import "hardhat/console.sol";

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import "../interfaces/ILntVault.sol";
import "../interfaces/IVestingToken.sol";
import "../interfaces/market/ILntMarketRouter.sol";
import "../libs/Constants.sol";
import "../libs/NftTypeChecker.sol";
import "../libs/TokensHelper.sol";
import "./VaultSettings.sol";

abstract contract LntVaultBase is ILntVault, ReentrancyGuard, VaultSettings, Ownable {
  using EnumerableSet for EnumerableSet.UintSet;

  bool public initialized;
  bool public initializedT;

  address public immutable factory;

  address public NFT;
  Constants.NftType public NFTType;
  address public VT;
  address public T;
  address public lntMarketRouter;

  uint256 internal _currentDepositId;
  mapping(uint256 => DepositInfo) internal _depositsInfo;
  mapping(address => EnumerableSet.UintSet) internal _userDeposits;

  constructor(address _owner) Ownable(_owner) {
    factory = _msgSender();
  }

  receive() external payable {}

  /* ================= VIEWS ================ */

  function depositCount() external view returns (uint256) {
    return _currentDepositId;
  }

  function depositInfo(uint256 depositId) external view returns (DepositInfo memory) {
    return _depositsInfo[depositId];
  }

  function userDeposits(address user) external view returns (uint256[] memory) {
    return _userDeposits[user].values();
  }

  /**
   * @dev See {IERC165-supportsInterface}.
   */
  function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
    return interfaceId == type(ILntVault).interfaceId;
  }

  /* ========== MUTATIVE FUNCTIONS ========== */

  function batchDeposit(uint256[] calldata tokenIds, uint256[] calldata values) external nonReentrant onlyInitialized returns (uint256[] memory) {
    require(tokenIds.length > 0 && tokenIds.length == values.length, "Invalid input");

    uint256[] memory depositIds = new uint256[](tokenIds.length);
    for (uint256 i = 0; i < tokenIds.length; i++) {
      depositIds[i] = _depositToken(tokenIds[i], values[i]);
    }

    return depositIds;
  }

  function deposit(uint256 tokenId, uint256 value) external nonReentrant onlyInitialized returns (uint256) {
    return _depositToken(tokenId, value);
  }

  function redeem(uint256 depositId, uint256 tokenId, uint256 value) external nonReentrant onlyInitialized {
    DepositInfo storage _depositInfo = _depositsInfo[depositId];
    require(depositId > 0 && _depositInfo.depositId == depositId, "Invalid depositId");
    require(_depositInfo.user == _msgSender(), "Not user of deposit");
    require(!_depositInfo.redeemed, "Already redeemed");
    require(_depositInfo.tokenId == tokenId, "Invalid tokenId");
    require(value > 0 && _depositInfo.value == value, "Invalid value");

    _depositInfo.redeemed = true;

    _redeem(tokenId, value, _depositInfo.f1OnDeposit);

    emit Redeem(depositId, _msgSender(), NFT, tokenId, value);
  }

  function redeemT(uint256 amount) external nonReentrant onlyInitialized onlyInitializedT noneZeroAmount(amount) {
    require(_vestingEnded(), "Vesting not ended");
    require(IERC20(VT).balanceOf(_msgSender()) >= amount, "Insufficient VT balance");
    require(TokensHelper.balance(address(this), T) >= amount, "Insufficient token balance");

    IVestingToken(VT).burn(_msgSender(), amount);
    TokensHelper.transferTokens(T, address(this), _msgSender(), amount);

    emit RedeemT(_msgSender(), amount);
  }

  function buyback(uint256 amountT, uint256 amountVTMin) external nonReentrant onlyOwner onlyInitialized onlyInitializedT noneZeroAmount(amountT) {
    require(TokensHelper.balance(address(this), T) >= amountT, "Insufficient token balance");
    uint256 prevBalanceVT = IERC20(VT).balanceOf(address(this));
    
    // Create a simple path array: [T, VT]
    address[] memory path = new address[](2);
    path[0] = T;
    path[1] = VT;
    
    // Calculate deadline 30 minutes from now
    uint deadline = block.timestamp + 30 minutes;
    
    // Handle based on token type
    if (T == Constants.NATIVE_TOKEN) {
      // For native token (ETH), use swapExactETHForTokens
      path[0] = ILntMarketRouter(lntMarketRouter).WETH();
      ILntMarketRouter(lntMarketRouter).swapExactETHForTokens{value: amountT}(
        amountVTMin,
        path,
        address(this), // Send VT tokens to this vault
        deadline
      );
    } else {
      // For ERC20 tokens
      // Approve the router to spend tokens
      IERC20(T).approve(address(lntMarketRouter), amountT);
      
      // Perform the swap
      ILntMarketRouter(lntMarketRouter).swapExactTokensForTokens(
        amountT,
        amountVTMin,
        path,
        address(this), // Send VT tokens to this vault
        deadline
      );
    }
    
    // After swap, we burn the VT tokens to reduce supply
    uint256 vtReceived = IERC20(VT).balanceOf(address(this)) - prevBalanceVT;
    if (vtReceived > 0) {
      IVestingToken(VT).burn(address(this), vtReceived);
    }
    
    emit Buyback(_msgSender(), amountT, vtReceived);
  }

  /* ========== INTERNAL FUNCTIONS ========== */

  function _depositToken(uint256 tokenId, uint256 value) internal returns (uint256) {
    require(value > 0, "Invalid value");

    _currentDepositId++;
    _depositsInfo[_currentDepositId] = DepositInfo({
      depositId: _currentDepositId,
      user: _msgSender(),
      tokenId: tokenId,
      value: value,
      depositTime: block.timestamp,
      redeemed: false,
      f1OnDeposit : paramValue("f1")
    });
    _userDeposits[_msgSender()].add(_currentDepositId);

    _deposit(tokenId, value);

    emit Deposit(_currentDepositId, _msgSender(), NFT, tokenId, value);

    return _currentDepositId;
  }

  function _deposit(uint256 tokenId, uint256 value) internal virtual;

  function _redeem(uint256 tokenId, uint256 value, uint256 f1) internal virtual;

  function _vestingEnded()  internal virtual returns (bool);


  /* ========== RESTRICTED FUNCTIONS ========== */

  function __LntVaultBase_init(address _NFT, address _lntMarketRouter, address _VT) internal onlyOwner {
    require(_NFT != address(0) && _lntMarketRouter != address(0) && _VT != address(0), "Zero address detected");

    NFT = _NFT;
    NFTType = NftTypeChecker.getNftType(_NFT);
    require(NFTType != Constants.NftType.UNKNOWN, "Invalid NFT");
    
    lntMarketRouter = _lntMarketRouter;
    VT = _VT;
  }

  function initializeT(address _T) external nonReentrant onlyOwner {
    require(_T != address(0), "Zero address detected");

    require(!initializedT, "Already initialized");
    initializedT = true;

    T = _T;
    emit InitializedT(_T);
  }

  function upsertParamConfig(bytes32 param, uint256 defaultValue, uint256 min, uint256 max) external nonReentrant onlyOwner {
    _upsertParamConfig(param, defaultValue, min, max);
  }

  function updateParamValue(bytes32 param, uint256 value) external nonReentrant onlyOwner {
    _updateParamValue(param, value);
  }

  /* ============== MODIFIERS =============== */

  modifier initializer() {
    require(!initialized, "Already initialized");
    _;
    initialized = true;
    emit Initialized();
  }

  modifier onlyInitialized() virtual {
    require(initialized, "Not initialized");
    _;
  }

  modifier onlyInitializedT() {
    require(initializedT, "Not initialized T");
    _;
  }

  modifier noneZeroAmount(uint256 amount) {
    require(amount > 0, "Amount must be greater than 0");
    _;
  }
  
  /* =============== EVENTS ============= */

  event Initialized();
  event InitializedT(address indexed T);

  event WithdrawT(address indexed caller, uint256 amount);
  event RedeemT(address indexed caller, uint256 amount);
  event Buyback(address indexed caller, uint256 amountT, uint256 amountVT);
  
}