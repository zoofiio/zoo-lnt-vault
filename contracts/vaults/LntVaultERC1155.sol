// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

// import "hardhat/console.sol";

import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import "../interfaces/ILntVault.sol";
import "../interfaces/IProtocolSettings.sol";
import "../interfaces/IVestingToken.sol";
import "../libs/Constants.sol";
import "../libs/NftTypeChecker.sol";
import "../settings/ProtocolOwner.sol";
import "./LntVaultBase.sol";

contract LntVaultERC1155 is LntVaultBase, ERC1155Holder {
  using Math for uint256;
  using EnumerableSet for EnumerableSet.UintSet;

  VestingSchedule[] internal _vestingSchedules;
  EnumerableSet.UintSet internal _tokenIds;
  mapping(uint256 => VestingSchedule) internal _tokenVestingSchedule;

  constructor(
    address _protocol, address _settings, address _nft, address _T, VestingSchedule[] memory _vestingSchedules_
  ) LntVaultBase(_protocol, _settings, _nft, _T) {
    require(NFTType == Constants.NftType.ERC1155, "Invalid NFT");

    require(_vestingSchedules_.length > 0, "Invalid vesting schedules");
    _vestingSchedules = _vestingSchedules_;
    for (uint256 i = 0; i < _vestingSchedules.length; i++) {
      VestingSchedule memory schedule = _vestingSchedules[i];
      require(schedule.vestingTokenAmountPerNft > 0 && schedule.vestingStartTime > 0 && schedule.vestingDuration > 0, "Invalid vesting schedule");
      require(!_tokenIds.contains(schedule.tokenId), "Duplicate vesting schedule");
      _tokenIds.add(schedule.tokenId);
      _tokenVestingSchedule[schedule.tokenId] = schedule;
    }
  }

  /* ================= VIEWS ================ */

  function vestingSchedules() external view returns (VestingSchedule[] memory) {
    return _vestingSchedules;
  }
  
  /* ========== MUTATIVE FUNCTIONS ========== */

  

  /* ========== INTERNAL FUNCTIONS ========== */

  function _vestingEnded()  internal override virtual returns (bool) {
    for (uint256 i = 0; i < _vestingSchedules.length; i++) {
      VestingSchedule memory schedule = _vestingSchedules[i];
      if (block.timestamp < schedule.vestingStartTime + schedule.vestingDuration) {
        return false;
      }
    }
    return true;
  }

  function _deposit(address receiver, uint256 tokenId, uint256 value) internal override virtual {
    IERC1155(NFT).safeTransferFrom(_msgSender(), address(this), tokenId, value, "");

    uint256 fees;
    uint256 vtNetAmount;
    (fees, vtNetAmount) = _calcFeesAndNetAmount(tokenId, value);

    if (fees > 0) {
      IVestingToken(VT).mint(IProtocolSettings(settings).treasury(), fees);
    }
    if (vtNetAmount > 0) {
      IVestingToken(VT).mint(receiver, vtNetAmount);
    }
    emit VTMinted(_msgSender(), receiver, fees, vtNetAmount);
  }

  function _redeem(address receiver, uint256 tokenId, uint256 value) internal override virtual {
    IERC1155(NFT).safeTransferFrom(address(this), receiver, tokenId, value, "");

    uint256 vtBurnAmount;
    (, vtBurnAmount) = _calcFeesAndNetAmount(tokenId, value);
    if (vtBurnAmount > 0) {
      IVestingToken(VT).burn(_msgSender(), vtBurnAmount);
    }
    emit VTBurned(_msgSender(), vtBurnAmount);
  }

  function _calcFeesAndNetAmount(uint256 tokenId, uint256 value) internal view returns (uint256, uint256) {
    require(_tokenIds.contains(tokenId), "Invalid token id");
    VestingSchedule memory schedule = _tokenVestingSchedule[tokenId];
    uint256 vestingTokenAmountPerNft = schedule.vestingTokenAmountPerNft;
    uint256 vestingStartTime = schedule.vestingStartTime;
    uint256 vestingDuration = schedule.vestingDuration;

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
  function supportsInterface(bytes4 interfaceId) public view virtual override(LntVaultBase, ERC1155Holder) returns (bool) {
    return
      interfaceId == type(IERC1155Receiver).interfaceId ||
      super.supportsInterface(interfaceId);
  }
  
  /* =============== EVENTS ============= */

}