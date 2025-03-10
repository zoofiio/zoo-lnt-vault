// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

// import "hardhat/console.sol";

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import "../interfaces/ILntVault.sol";
import "../interfaces/IProtocolSettings.sol";
import "../interfaces/IVestingToken.sol";
import "../interfaces/market/ILntMarketRouter.sol";
import "../libs/Constants.sol";
import "../libs/NftTypeChecker.sol";
import "../libs/TokensTransfer.sol";
import "../settings/ProtocolOwner.sol";

abstract contract LntVaultBase is ILntVault, ReentrancyGuard, ProtocolOwner {
  bool public initializedVT;
  bool public initializedT;
  address public immutable settings;

  address public immutable NFT;
  Constants.NftType public immutable NFTType;
  address public VT;
  address public T;

  constructor(
    address _protocol, address _settings, address _nft
  ) ProtocolOwner(_protocol) {
    require(_settings != address(0) && _nft != address(0), "Zero address detected");

    settings = _settings;

    NFT = _nft;
    NFTType = NftTypeChecker.getNftType(_nft);
    require(NFTType != Constants.NftType.UNKNOWN, "Invalid NFT");
  }

   /* ================= VIEWS ================ */

  function paramValue(bytes32 param) public view returns (uint256) {
    return IProtocolSettings(settings).vaultParamValue(address(this), param);
  }

  function balanceOfT() public view onlyInitializedT returns (uint256) {
    if (T == Constants.NATIVE_TOKEN) {
      return address(this).balance;
    }
    else {
      return IERC20(T).balanceOf(address(this));
    }
  }

  /* ========== MUTATIVE FUNCTIONS ========== */

  function deposit(address receiver, uint256 tokenId, uint256 value) external nonReentrant onlyInitializedVT {
    require(receiver != address(0), "Zero address detected");
    require(value > 0, "Invalid value");

    _deposit(receiver, tokenId, value);

    emit Deposit(_msgSender(), receiver, NFT, tokenId, value);
  }

  function redeem(address receiver, uint256 tokenId, uint256 value) external nonReentrant onlyInitializedVT {
    require(receiver != address(0), "Zero address detected");
    require(value > 0, "Invalid value");

    _redeem(receiver, tokenId, value);

    emit Redeem(_msgSender(), receiver, NFT, tokenId, value);
  }

  function redeemT(uint256 amount) external nonReentrant onlyInitializedVT onlyInitializedT noneZeroAmount(amount) {
    require(_vestingEnded(), "Vesting not ended");
    require(IERC20(VT).balanceOf(_msgSender()) >= amount, "Insufficient VT balance");
    require(balanceOfT() >= amount, "Insufficient token balance");

    IVestingToken(VT).burn(_msgSender(), amount);
    TokensTransfer.transferTokens(T, address(this), _msgSender(), amount);

    emit RedeemT(_msgSender(), amount);
  }

  function buyback(uint256 amount) external nonReentrant onlyOwner onlyInitializedVT onlyInitializedT noneZeroAmount(amount) {
    require(balanceOfT() >= amount, "Insufficient token balance");
    ILntMarketRouter lntMarketRouter = ILntMarketRouter(IZooProtocol(protocol).lntMarketRouter());
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
      lntMarketRouter.swapExactETHForTokensSupportingFeeOnTransferTokens{value: amount}(
        0, // Accept any amount of VT (we're not concerned with slippage in buyback)
        path,
        address(this), // Send VT tokens to this vault
        deadline
      );
    } else {
      // For ERC20 tokens
      // Approve the router to spend tokens
      IERC20(T).approve(address(lntMarketRouter), amount);
      
      // Perform the swap
      lntMarketRouter.swapExactTokensForTokensSupportingFeeOnTransferTokens(
        amount,
        0, // Accept any amount of VT (we're not concerned with slippage in buyback)
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
    
    emit Buyback(msg.sender, amount, vtReceived);
  }

  /* ========== INTERNAL FUNCTIONS ========== */

  function _deposit(address receiver, uint256 tokenId, uint256 value) internal virtual;

  function _redeem(address receiver, uint256 tokenId, uint256 value) internal virtual;

  function _vestingEnded()  internal virtual returns (bool);


  /* ========== RESTRICTED FUNCTIONS ========== */

  function initializeVT(address _VT) external nonReentrant onlyLntFactory {
    require(_VT != address(0), "Zero address detected");

    require(!initializedVT, "Already initialized");
    initializedVT = true;
  
    VT = _VT;
    emit InitializedVT(_VT);
  }

  function initializeT(address _T) external nonReentrant onlyOwner {
    require(_T != address(0), "Zero address detected");

    require(!initializedT, "Already initialized");
    initializedT = true;

    T = _T;
    emit InitializedT(_T);
  }

  /* ============== MODIFIERS =============== */

  modifier onlyLntFactory() {
    require(_msgSender() == IZooProtocol(protocol).lntFactory(), "Not LntFactory");
    _;
  }

  modifier onlyInitializedVT() {
    require(initializedVT, "Not initialized VT");
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

  /**
   * @dev See {IERC165-supportsInterface}.
   */
  function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
    return interfaceId == type(ILntVault).interfaceId;
  }
  
  /* =============== EVENTS ============= */

  event InitializedVT(address indexed VT);
  event InitializedT(address indexed T);

  event WithdrawT(address indexed caller, uint256 amount);
  event RedeemT(address indexed caller, uint256 amount);
  event Buyback(address indexed caller, uint256 amountT, uint256 amountVT);
  
}