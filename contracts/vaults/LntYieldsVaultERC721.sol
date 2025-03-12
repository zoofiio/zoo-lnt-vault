// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

// import "hardhat/console.sol";

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "../interfaces/ILntVault.sol";
import "../interfaces/INftStakingPool.sol";
import "../interfaces/IVestingToken.sol";
import "../libs/Constants.sol";
import "../libs/NftTypeChecker.sol";
import "./LntYieldsVaultBase.sol";

contract LntYieldsVaultERC721 is LntYieldsVaultBase, ERC721Holder {
  using Math for uint256;

  uint256 public vestingTokenAmountPerNft;
  uint256 public vestingStartTime;
  uint256 public vestingDuration;

  constructor(address _treasury, address _nft) LntYieldsVaultBase(_treasury, _nft) {
    require(NFTType == Constants.NftType.ERC721, "Invalid NFT");
  }

  /* ================= VIEWS ================ */

  function vestingSchedules() external view returns (VestingSchedule[] memory) {
    VestingSchedule[] memory schedules = new VestingSchedule[](1);
    schedules[0] = VestingSchedule({
      tokenId: 0,
      weight: 1,
      vestingTokenAmountPerNft: vestingTokenAmountPerNft,
      vestingStartTime: vestingStartTime,
      vestingDuration: vestingDuration
    });
    return schedules;
  }

  /**
   * @dev See {IERC165-supportsInterface}.
   */
  function supportsInterface(bytes4 interfaceId) public view virtual override(LntYieldsVaultBase) returns (bool) {
    return
      interfaceId == type(IERC721Receiver).interfaceId ||
      super.supportsInterface(interfaceId);
  }
  
  /* ========== MUTATIVE FUNCTIONS ========== */

  

  /* ========== INTERNAL FUNCTIONS ========== */

  function _vestingEnded()  internal override virtual returns (bool) {
    return block.timestamp >= vestingStartTime + vestingDuration;
  }

  function _deposit(uint256 tokenId, uint256 value) internal override virtual {
    require(IERC721(NFT).ownerOf(tokenId) == _msgSender(), "Not owner of NFT");
    require(value == 1, "Invalid value");
    IERC721(NFT).safeTransferFrom(_msgSender(), address(this), tokenId);
    require(IERC721(NFT).ownerOf(tokenId) == address(this), "NFT transfer failed");

    uint256 fees;
    uint256 vtNetAmount;
    (fees, vtNetAmount) = _calcFeesAndNetAmount(value, paramValue("f1"));

    if (fees > 0) {
      IVestingToken(VT).mint(treasury, fees);
    }
    if (vtNetAmount > 0) {
      IVestingToken(VT).mint(_msgSender(), vtNetAmount);
    }
    emit VTMinted(_msgSender(), fees, vtNetAmount);

    totalWeightedDepositValue += value;

    INftStakingPool(nftStakingPool).notifyNftDepositForUser(_msgSender(), tokenId, 1);
  }

  function _redeem(uint256 tokenId, uint256 value, uint256 f1) internal override virtual {
    require(value == 1, "Invalid value");
    IERC721(NFT).safeTransferFrom(address(this), _msgSender(), tokenId);

    uint256 vtBurnAmount;
    (, vtBurnAmount) = _calcFeesAndNetAmount(value, f1);
    if (vtBurnAmount > 0) {
      IVestingToken(VT).burn(_msgSender(), vtBurnAmount);
    }
    emit VTBurned(_msgSender(), vtBurnAmount);

    totalWeightedDepositValue -= value;

    INftStakingPool(nftStakingPool).notifyNftRedeemForUser(_msgSender(), tokenId, 1);
  }

  function _calcFeesAndNetAmount(uint256 value, uint256 f1) internal view returns (uint256, uint256) {
    uint256 remainingTime = 0;
    if (block.timestamp < vestingStartTime + vestingDuration) {
      remainingTime = vestingStartTime + vestingDuration - block.timestamp;
    }
    remainingTime = Math.min(remainingTime, vestingDuration);

    uint256 vtAmount = vestingTokenAmountPerNft.mulDiv(remainingTime * value, vestingDuration);
    uint256 fees = vtAmount.mulDiv(f1, 10 ** decimals);
    uint256 vtNetAmount = vtAmount - fees;
    return (fees, vtNetAmount);
  }


  /* ========== RESTRICTED FUNCTIONS ========== */

  function initialize(
    address _lntMarketRouter, address _VT, address _nftStakingPool,
    uint256 _vestingTokenAmountPerNft, uint256 _vestingStartTime, uint256 _vestingDuration
  ) external nonReentrant initializer onlyOwner {
    __LntYieldVaultBase_init(_lntMarketRouter, _VT, _nftStakingPool);

    require(_vestingTokenAmountPerNft > 0 && _vestingStartTime > 0 && _vestingDuration > 0, "Invalid parameters");
    vestingTokenAmountPerNft = _vestingTokenAmountPerNft;
    vestingStartTime = _vestingStartTime;
    vestingDuration = _vestingDuration;
  }

}