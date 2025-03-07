// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

// import "hardhat/console.sol";

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "../interfaces/ILntVault.sol";
import "../interfaces/IProtocolSettings.sol";
import "../interfaces/IVestingToken.sol";
import "../libs/Constants.sol";
import "../libs/NftTypeChecker.sol";
import "../settings/ProtocolOwner.sol";
import "./LntVaultBase.sol";

contract LntVaultERC721 is LntVaultBase, ERC721Holder {
  using Math for uint256;

  uint256 public immutable vestingTokenAmountPerNft;
  uint256 public immutable vestingStartTime;
  uint256 public immutable vestingDuration;

  constructor(
    address _protocol, address _settings, address _nft, address _T,
    uint256 _vestingTokenAmountPerNft, uint256 _vestingStartTime, uint256 _vestingDuration
  ) LntVaultBase(_protocol, _settings, _nft, _T) {
    require(_vestingTokenAmountPerNft > 0 && _vestingStartTime > 0 && _vestingDuration > 0, "Invalid parameters");
    require(NFTType == Constants.NftType.ERC721, "Invalid NFT");

    vestingTokenAmountPerNft = _vestingTokenAmountPerNft;
    vestingStartTime = _vestingStartTime;
    vestingDuration = _vestingDuration;
  }

  /* ================= VIEWS ================ */

  function vestingSchedules() external view returns (VestingSchedule[] memory) {
    VestingSchedule[] memory schedules = new VestingSchedule[](1);
    schedules[0] = VestingSchedule({
      tokenId: 0,
      vestingTokenAmountPerNft: vestingTokenAmountPerNft,
      vestingStartTime: vestingStartTime,
      vestingDuration: vestingDuration
    });
    return schedules;
  }

  
  /* ========== MUTATIVE FUNCTIONS ========== */

  

  /* ========== INTERNAL FUNCTIONS ========== */

  function _vestingEnded()  internal override virtual returns (bool) {
    return block.timestamp >= vestingStartTime + vestingDuration;
  }

  function _deposit(address receiver, uint256 tokenId, uint256 value) internal override virtual {
    require(value == 1, "Invalid value");
    IERC721(NFT).safeTransferFrom(_msgSender(), address(this), tokenId);

    uint256 fees;
    uint256 vtNetAmount;
    (fees, vtNetAmount) = _calcFeesAndNetAmount(value);

    if (fees > 0) {
      IVestingToken(VT).mint(IProtocolSettings(settings).treasury(), fees);
    }
    if (vtNetAmount > 0) {
      IVestingToken(VT).mint(receiver, vtNetAmount);
    }
    emit VTMinted(_msgSender(), receiver, fees, vtNetAmount);
  }

  function _redeem(address receiver, uint256 tokenId, uint256 value) internal override virtual {
    require(value == 1, "Invalid value");
    IERC721(NFT).safeTransferFrom(address(this), receiver, tokenId);

    uint256 vtBurnAmount;
    (, vtBurnAmount) = _calcFeesAndNetAmount(value);
    if (vtBurnAmount > 0) {
      IVestingToken(VT).burn(_msgSender(), vtBurnAmount);
    }
    emit VTBurned(_msgSender(), vtBurnAmount);
  }

  function _calcFeesAndNetAmount(uint256 value) internal view returns (uint256, uint256) {
    uint256 remainingTime = 0;
    if (block.timestamp < vestingStartTime + vestingDuration) {
      remainingTime = vestingStartTime + vestingDuration - block.timestamp;
    }
    remainingTime = Math.min(remainingTime, vestingDuration);

    uint256 vtAmount = vestingTokenAmountPerNft.mulDiv(remainingTime * value, vestingDuration);
    uint256 fees = vtAmount.mulDiv(paramValue("f1"), 10 ** IProtocolSettings(settings).decimals());
    uint256 vtNetAmount = vtAmount - fees;
    return (fees, vtNetAmount);
  }


  /* ========== RESTRICTED FUNCTIONS ========== */



  /* ============== MODIFIERS =============== */


  /**
   * @dev See {IERC165-supportsInterface}.
   */
  function supportsInterface(bytes4 interfaceId) public view virtual override(LntVaultBase) returns (bool) {
    return
      interfaceId == type(IERC721Receiver).interfaceId ||
      super.supportsInterface(interfaceId);
  }
  
  /* =============== EVENTS ============= */

}