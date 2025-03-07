// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

// import "hardhat/console.sol";

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import "../interfaces/ILntVault.sol";
import "../interfaces/IProtocolSettings.sol";
import "../interfaces/IVestingToken.sol";
import "../libs/Constants.sol";
import "../libs/NftTypeChecker.sol";
import "../libs/TokensTransfer.sol";
import "../settings/ProtocolOwner.sol";

abstract contract LntVaultBase is ILntVault, ReentrancyGuard, ProtocolOwner {
  bool public initialized;
  address public immutable settings;

  address public immutable NFT;
  Constants.NftType public immutable NFTType;
  address public VT;
  address public immutable T;

  constructor(
    address _protocol, address _settings, address _nft, address _T
  ) ProtocolOwner(_protocol) {
    require(_settings != address(0) && _nft != address(0) && _T != address(0), "Zero address detected");

    settings = _settings;

    NFT = _nft;
    NFTType = NftTypeChecker.getNftType(_nft);
    require(NFTType != Constants.NftType.UNKNOWN, "Invalid NFT");

    T = _T;
  }

   /* ================= VIEWS ================ */

  function paramValue(bytes32 param) public view returns (uint256) {
    return IProtocolSettings(settings).vaultParamValue(address(this), param);
  }

  /* ========== MUTATIVE FUNCTIONS ========== */

  function deposit(address receiver, uint256 tokenId, uint256 value) external nonReentrant onlyInitialized {
    require(receiver != address(0), "Zero address detected");
    require(value > 0, "Invalid value");

    _deposit(receiver, tokenId, value);

    emit Deposit(_msgSender(), receiver, NFT, tokenId, value);
  }

  function redeem(address receiver, uint256 tokenId, uint256 value) external nonReentrant onlyInitialized {
    require(receiver != address(0), "Zero address detected");
    require(value > 0, "Invalid value");

    _redeem(receiver, tokenId, value);

    emit Redeem(_msgSender(), receiver, NFT, tokenId, value);
  }

  function redeemT(uint256 amount) external nonReentrant onlyInitialized noneZeroAmount(amount) {
    require(_vestingEnded(), "Vesting not ended");
    require(IERC20(VT).balanceOf(_msgSender()) >= amount, "Insufficient VT balance");
    require(IERC20(T).balanceOf(address(this)) >= amount, "Insufficient token balance");

    IVestingToken(VT).burn(_msgSender(), amount);
    TokensTransfer.transferTokens(T, address(this), _msgSender(), amount);

    emit RedeemT(_msgSender(), amount);
  }


  /* ========== INTERNAL FUNCTIONS ========== */

  function _deposit(address receiver, uint256 tokenId, uint256 value) internal virtual;

  function _redeem(address receiver, uint256 tokenId, uint256 value) internal virtual;

  function _vestingEnded()  internal virtual returns (bool);


  /* ========== RESTRICTED FUNCTIONS ========== */

  function initialize(address _VT) external nonReentrant onlyLntFactory {
    require(_VT != address(0), "Zero address detected");

    require(!initialized, "Already initialized");
    initialized = true;
  
    VT = _VT;
    emit Initialized(_VT);
  }

  function withdrawT(uint256 amount) external nonReentrant onlyOwner onlyInitialized noneZeroAmount(amount) {
    require(IERC20(T).balanceOf(address(this)) >= amount, "Insufficient token balance");
    TokensTransfer.transferTokens(T, address(this), _msgSender(), amount);
    emit WithdrawT(_msgSender(), amount);
  }

  /* ============== MODIFIERS =============== */

  modifier onlyLntFactory() {
    require(_msgSender() == IZooProtocol(protocol).lntFactory(), "Not LntFactory");
    _;
  }

  modifier onlyInitialized() {
    require(initialized, "Not initialized");
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

  event Initialized(address indexed VT);

  event WithdrawT(address indexed caller, uint256 amount);
  event RedeemT(address indexed caller, uint256 amount);
  
}