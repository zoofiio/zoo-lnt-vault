// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

// import "hardhat/console.sol";

import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {ILntContractFactory} from "../interfaces/ILntContractFactory.sol";
import {ILntVault} from "../interfaces/ILntVault.sol";
import {IVestingToken} from "../interfaces/IVestingToken.sol";
import {Constants} from "../libs/Constants.sol";
import {NftTypeChecker} from "../libs/NftTypeChecker.sol";
import {LntVaultBase} from "./LntVaultBase.sol";

contract LntVaultERC1155 is LntVaultBase, ERC1155Holder {
    using Math for uint256;
    using EnumerableSet for EnumerableSet.UintSet;

    VestingSchedule[] internal _vestingSchedules;
    EnumerableSet.UintSet internal _tokenIds;
    mapping(uint256 => VestingSchedule) internal _tokenVestingSchedule;

    constructor(address _owner) LntVaultBase(_owner) {
        
    }

    /* ================= VIEWS ================ */

    function vestingSchedules() external view onlyInitialized returns (VestingSchedule[] memory) {
        return _vestingSchedules;
    }

    /**
        * @dev See {IERC165-supportsInterface}.
        */
    function supportsInterface(bytes4 interfaceId) public view virtual override(LntVaultBase, ERC1155Holder) returns (bool) {
        return
            interfaceId == type(IERC1155Receiver).interfaceId ||
            super.supportsInterface(interfaceId);
    }
    

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

    function _deposit(uint256 tokenId, uint256 value) internal override virtual {
        require(IERC1155(NFT).balanceOf(_msgSender(), tokenId) >= value, "Insufficient balance");
        IERC1155(NFT).safeTransferFrom(_msgSender(), address(this), tokenId, value, "");

        uint256 fees;
        uint256 vtNetAmount;
        (fees, vtNetAmount) = _calcFeesAndNetAmount(tokenId, value, paramValue("f1"));

        if (fees > 0) {
            IVestingToken(VT).mint(ILntContractFactory(factory).treasury(), fees);
        }
        if (vtNetAmount > 0) {
            IVestingToken(VT).mint(_msgSender(), vtNetAmount);
        }
        emit VTMinted(_msgSender(), fees, vtNetAmount);
    }

    function _redeem(uint256 tokenId, uint256 value, uint256 f1) internal override virtual {
        IERC1155(NFT).safeTransferFrom(address(this), _msgSender(), tokenId, value, "");

        uint256 vtBurnAmount;
        (, vtBurnAmount) = _calcFeesAndNetAmount(tokenId, value, f1);
        if (vtBurnAmount > 0) {
            IVestingToken(VT).burn(_msgSender(), vtBurnAmount);
        }
        emit VTBurned(_msgSender(), vtBurnAmount);
    }

    function _calcFeesAndNetAmount(uint256 tokenId, uint256 value, uint256 f1) internal view returns (uint256, uint256) {
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
        uint256 fees = vtAmount.mulDiv(f1, 10 ** settingDecimals);
        uint256 vtNetAmount = vtAmount - fees;
        return (fees, vtNetAmount);
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function initialize(address _NFT, address _lntMarketRouter, address _VT, VestingSchedule[] memory _vestingSchedules_) external nonReentrant initializer onlyOwner {
        __LntVaultBase_init(_NFT, _lntMarketRouter, _VT);
        require(NFTType == Constants.NftType.ERC1155, "Invalid NFT");

        require(_vestingSchedules_.length > 0, "Invalid vesting schedules");

        delete _vestingSchedules;
        for (uint256 i = 0; i < _vestingSchedules_.length; i++) {
            VestingSchedule memory schedule = _vestingSchedules_[i];
            require(schedule.vestingTokenAmountPerNft > 0 && schedule.vestingStartTime > 0 && schedule.vestingDuration > 0, "Invalid vesting schedule");
            require(!_tokenIds.contains(schedule.tokenId), "Duplicate vesting schedule");
            _vestingSchedules.push(schedule);
            _tokenIds.add(schedule.tokenId);
            _tokenVestingSchedule[schedule.tokenId] = schedule;
        }
    }

}
