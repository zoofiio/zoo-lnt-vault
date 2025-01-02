// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

// import "hardhat/console.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "./Constants.sol";
import "../interfaces/IVault.sol";

library VaultCalculator {
  using Math for uint256;
  using SafeMath for uint256;

  uint256 public constant SCALE = 10 ** 18;

  function calcY(IVault self) public view returns (uint256) {
    uint256 epochId = self.currentEpochId();
    require(epochId > 0);
    Constants.Epoch memory epoch = self.epochInfoById(epochId);

    uint256 X = self.epochNextSwapX(epochId);
    uint256 k0 = self.epochNextSwapK0(epochId);   // scale: PROTOCOL_DECIMALS

    uint256 deltaT = 0;
    if (epoch.startTime.add(epoch.duration) >= block.timestamp) {
      // in current epoch
      deltaT = block.timestamp.sub(epoch.startTime);
    }
    else {
      // in a new epoch
      deltaT = 0;
      uint256 yTokenAmount = self.ytNewEpoch();
      (X, k0) = calcInitSwapParams(self, yTokenAmount, self.ytSwapPaymentToken(), self.ytSwapPrice());
    }

    // Y = k0 / (X * (1 + ∆t / 86400)2) = k0 / X / (1 + ∆t / 86400) / (1 + ∆t / 86400)
    uint256 scale = 10 ** Constants.PROTOCOL_DECIMALS;
    uint256 decayPeriod = self.paramValue("D").div(30);
    uint256 Y = k0.mulDiv(
      scale,
      scale + deltaT.mulDiv(scale, decayPeriod)
    ).mulDiv(
      scale,
      scale + deltaT.mulDiv(scale, decayPeriod)
    ).div(X).div(10 ** Constants.PROTOCOL_DECIMALS);

    return Y;
  }

  function calcInitSwapParams(IVault self, uint256 N, address ytSwapPaymentToken, uint256 ytSwapPrice) public view returns (uint256, uint256) {
    uint256 X = N;

    // Y(0) = X * P
    uint256 Y0 = X * ytSwapPrice;  // scale: PROTOCOL_DECIMALS

    // k0 = X * Y0
    uint256 k0 = X * Y0;  // scale: PROTOCOL_DECIMALS

    uint256 ytSwapPaymentTokenDecimals = IERC20Metadata(ytSwapPaymentToken).decimals();
    uint256 decimalsOffset = self.ytDecimals() - ytSwapPaymentTokenDecimals;
    if (decimalsOffset > 0) {
      k0 = k0.div(10 ** decimalsOffset);
    }

    // console.log('calcInitSwapParams, X: %s, Y0: %s, k0: %s', X, Y0, k0);

    return (X, k0);
  }

  function doCalcSwap(IVault self, uint256 n) public view returns (uint256, uint256) {
    uint256 epochId = self.currentEpochId();
    require(epochId > 0);
    Constants.Epoch memory epoch = self.epochInfoById(epochId);

    uint256 X = self.epochNextSwapX(epochId);
    uint256 k0 = self.epochNextSwapK0(epochId); // scale: PROTOCOL_DECIMALS

    uint256 deltaT = 0;
    if (epoch.startTime.add(epoch.duration) >= block.timestamp) {
      // in current epoch
      deltaT = block.timestamp.sub(epoch.startTime);
    } 
    else {
      // in a new epoch
      deltaT = 0;
      uint256 yTokenAmount = self.ytNewEpoch();
      (X, k0) = calcInitSwapParams(self, yTokenAmount, self.ytSwapPaymentToken(), self.ytSwapPrice());
    }

    // X' = X * k0 / (k0 + X * n * (1 + ∆t / 86400)2)

    uint256 decayPeriod = self.paramValue("D").div(30);
    Constants.Terms memory T;
    T.T1 = SCALE.add(
      deltaT.mulDiv(SCALE, decayPeriod)
    );  // scale: 18

    // X * n * (1 + ∆t / 86400)2
    T.T2 = X.mulDiv(n.mulDiv(T.T1 * T.T1, SCALE), SCALE);   // scale: 1

    // k0 + X * n * (1 + ∆t / 86400)2
    T.T3 = k0.add(T.T2 * (10 ** Constants.PROTOCOL_DECIMALS));  // scale: PROTOCOL_DECIMALS

    // X' = X * k0 / (k0 + X * n * (1 + ∆t / 86400)2)
    uint256 X_updated = X.mulDiv(k0, T.T3);

    // m = X - X'
    uint256 m = X.sub(X_updated);

    // console.log('doCalcSwap, X: %s, k0: %s, deltaT: %s', X, k0, deltaT);
    // console.log('doCalcSwap, X_updated: %s, m: %s', X_updated, m);

    return (X_updated, m);
  }

}