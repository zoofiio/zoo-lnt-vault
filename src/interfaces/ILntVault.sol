// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import {IVaultSettings} from "./IVaultSettings.sol";
import {Constants} from "../libs/Constants.sol";

interface ILntVault is IVaultSettings, IERC165 {

    /// @dev emitted when new nft is deposited to mint vesting token
    event Deposit(
        uint256 indexed depositId,
        address indexed user,
        address indexed nft,
        uint256 tokenId,
        uint256 value
    );

    /// @dev emitted when vesting token is burned to redeem nft
    event Redeem(
        uint256 indexed depositId,
        address indexed user,
        address indexed nft,
        uint256 tokenId,
        uint256 value
    );

    event VTMinted(
        address indexed user,
        uint256 fees,
        uint256 amount
    );

    event VTBurned(
        address indexed user,
        uint256 amount
    );

    struct DepositInfo {
        uint256 depositId;
        address user;
        uint256 tokenId;
        uint256 value;
        uint256 depositTime;
        bool redeemed;
        uint256 f1OnDeposit;
    }

    struct VestingSchedule {
        uint256 tokenId;  // always 0 for ERC721
        uint256 weight;  // always 1 for ERC721
        uint256 vestingTokenAmountPerNft;
        uint256 vestingStartTime;
        uint256 vestingDuration;
    }

    function deposit(uint256 tokenId, uint256 value) external returns (uint256);

    function redeem(uint256 depositId, uint256 tokenId, uint256 value) external;

    function depositCount() external view returns (uint256);

    function depositInfo(uint256 depositId) external view returns (DepositInfo memory);

    function userDeposits(address user) external view returns (uint256[] memory);

    function NFT() external view returns (address);

    function NFTType() external view returns (Constants.NftType);

    function VT() external view returns (address);

    function T() external view returns (address);

    function vestingSchedules() external view returns (VestingSchedule[] memory);

}
