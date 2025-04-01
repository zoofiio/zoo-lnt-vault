// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "../interfaces/ILntContractFactory.sol";
import "../interfaces/ILntYieldsVault.sol";
import "../interfaces/IYieldToken.sol";
import "../interfaces/IYTSwap.sol";
import "../libs/TokensHelper.sol";

contract YTSwap is Context, ReentrancyGuard, IYTSwap {
  using Math for uint256;

  bool public initialized;

  address public immutable factory;
  address public immutable vault;

  address public YT;
  address public ytSwapPaymentToken;
  uint256 public ytSwapPrice;

  uint256 public epochStartTime;
  uint256 public epochDuration;

  uint256 public constant SCALE = 10 ** 18;
  uint256 public X;
  uint256 public k0;

  constructor(address _vault)  {
    require(_vault != address(0), "Zero address detected");
    vault = _vault;

    factory = _msgSender();
  }

  /* ========== MUTATIVE FUNCTIONS ========== */

  function swap(uint256 paymentTokenAmount) external nonReentrant onlyInitialized {
    require(paymentTokenAmount > 0, "Amount must be greater than 0");
    require(block.timestamp < epochStartTime + epochDuration, "Epoch ended");

    require(paymentTokenAmount <= IERC20(ytSwapPaymentToken).balanceOf(_msgSender()));
    require(paymentTokenAmount <= IERC20(ytSwapPaymentToken).allowance(_msgSender(), address(this)));

    require(IERC20(YT).balanceOf(vault) > 0);

    TokensHelper.transferTokens(ytSwapPaymentToken, _msgSender(), address(this), paymentTokenAmount);

    uint256 fees = paymentTokenAmount * ILntYieldsVault(vault).paramValue("f2") / (10 ** ILntYieldsVault(vault).settingDecimals());
    if (fees > 0) {
      TokensHelper.transferTokens(ytSwapPaymentToken, address(this), ILntContractFactory(factory).treasury(), fees);
    }
    uint256 netAmount = paymentTokenAmount - fees;

    require(k0 > 0);
    (uint256 _X, uint256 m) = _calcSwap(netAmount);
    X = _X;

    uint256 yTokenAmount = m;
    require(IERC20(YT).balanceOf(vault) >= yTokenAmount, "Not enough yTokens");
    TokensHelper.transferTokens(YT, vault, _msgSender(), yTokenAmount);

    emit Swap(_msgSender(), paymentTokenAmount, fees, yTokenAmount);

    if (ytSwapPaymentToken == Constants.NATIVE_TOKEN) {
      ILntYieldsVault(vault).addNftStakingRewards{value: fees}(ytSwapPaymentToken, fees);
    }
    else {
      IERC20(ytSwapPaymentToken).approve(vault, fees);
      ILntYieldsVault(vault).addNftStakingRewards(ytSwapPaymentToken, fees);
    }
  }

 
  /* ========== RESTRICTED FUNCTIONS ========== */

  function initialize(
    address _yt, address _ytSwapPaymentToken, uint256 _ytSwapPrice,
    uint256 _epochStartTime, uint256 _epochDuration, uint256 _ytInitAmount
  ) external override nonReentrant onlyVault initializer {
    require(_yt != address(0) && _ytSwapPaymentToken != address(0), "Zero address detected");
    require(_ytSwapPrice > 0, "Invalid price");
    require(_epochStartTime + _epochDuration > block.timestamp, "Invalid epoch start time or duration");
    require(_ytInitAmount > 0, "Invalid init amount");

    if (_ytSwapPaymentToken != Constants.NATIVE_TOKEN) {
      require(IERC20Metadata(_ytSwapPaymentToken).decimals() <= 18, "Invalid payment token");
    }

    YT = _yt;
    ytSwapPaymentToken = _ytSwapPaymentToken;
    ytSwapPrice = _ytSwapPrice;
    epochStartTime = _epochStartTime;
    epochDuration = _epochDuration;

    _initXK0(_ytInitAmount);
  }

  /* ========== INTERNAL FUNCTIONS ========== */

  function _swapPaymentTokenDecimals() internal view returns (uint256) {
    if (ytSwapPaymentToken == Constants.NATIVE_TOKEN) {
      return 18;
    }
    else {
      return IERC20Metadata(ytSwapPaymentToken).decimals();
    }
  }

  function _calcY() internal view returns (uint256) {
    require(block.timestamp < epochStartTime + epochDuration, "Epoch ended");
    uint256 deltaT = block.timestamp - epochStartTime;

    // Y = k0 / (X * (1 + ∆t / 86400)2) = k0 / X / (1 + ∆t / 86400) / (1 + ∆t / 86400)
    uint256 scale = 10 ** Constants.PROTOCOL_DECIMALS;
    uint256 decayPeriod = ILntYieldsVault(vault).paramValue("D") / 30;
    uint256 Y = k0.mulDiv(
      scale,
      scale + deltaT.mulDiv(scale, decayPeriod)
    ).mulDiv(
      scale,
      scale + deltaT.mulDiv(scale, decayPeriod)
    ) / X / (10 ** Constants.PROTOCOL_DECIMALS);

    return Y;
  }

  function _initXK0(uint256 N) internal {
    X = N;

    // Y(0) = X * P
    uint256 Y0 = X * ytSwapPrice;  // scale: DECIMALS

    // k0 = X * Y0
    k0 = X * Y0;  // scale: DECIMALS

    uint256 ytSwapPaymentTokenDecimals = _swapPaymentTokenDecimals();
    uint256 decimalsOffset = IERC20Metadata(YT).decimals() - ytSwapPaymentTokenDecimals;
    if (decimalsOffset > 0) {
      k0 = k0 / (10 ** decimalsOffset);
    }
  }

  function _calcSwap(uint256 n) internal view returns (uint256, uint256) {
    require(block.timestamp < epochStartTime + epochDuration, "Epoch ended");

    // X' = X * k0 / (k0 + X * n * (1 + ∆t / 86400)2)

    uint256 deltaT = block.timestamp - epochStartTime;
    uint256 decayPeriod = ILntYieldsVault(vault).paramValue("D") / 30;
    uint256 T1 = SCALE + (
      deltaT.mulDiv(SCALE, decayPeriod)
    );  // scale: 18

    // X * n * (1 + ∆t / 86400)2
    uint256 T2 = X.mulDiv(n.mulDiv(T1 * T1, SCALE), SCALE);   // scale: 1

    // k0 + X * n * (1 + ∆t / 86400)2
    uint256 T3 = k0 + (T2 * (10 ** Constants.PROTOCOL_DECIMALS));  // scale: PROTOCOL_DECIMALS

    // X' = X * k0 / (k0 + X * n * (1 + ∆t / 86400)2)
    uint256 X_updated = X.mulDiv(k0, T3);

    // m = X - X'
    uint256 m = X - X_updated;

    return (X_updated, m);
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

  modifier onlyVault() {
    require(vault == _msgSender(), "Caller is not Vault");
    _;
  }

}
