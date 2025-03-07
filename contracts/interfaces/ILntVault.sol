// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import "../libs/Constants.sol";

interface ILntVault is IERC165 {

  /// @dev emitted when new nft is deposited to mint vesting token
  event Deposit(
    address indexed caller,
    address indexed receiver,
    address indexed nft,
    uint256 tokenId,
    uint256 value
  );

  /// @dev emitted when vesting token is burned to redeem nft
  event Redeem(
    address indexed caller,
    address indexed receiver,
    address indexed nft,
    uint256 tokenId,
    uint256 value
  );

  event VTMinted(
    address indexed caller,
    address indexed receiver,
    uint256 fees,
    uint256 amount
  );

  event VTBurned(
    address indexed caller,
    uint256 amount
  );

  struct VestingSchedule {
    uint256 tokenId;  // 0 for ERC721
    uint256 vestingTokenAmountPerNft;
    uint256 vestingStartTime;
    uint256 vestingDuration;
  }

  function initialize(address _VT) external;

  /**
   * @notice deposit nft into the vault. Caller should own the nft or is approved to transfer it
   * @param receiver address to receive the vesting token
   * @param tokenId token id
   * @param value amount of tokens to deposit. Shoud be 1 for ERC721
   */
  function deposit(address receiver, uint256 tokenId, uint256 value) external;

  /**
   * @notice redeem nft from the vault by burning the vesting token. Caller will receive the nft
   * @param receiver address to receive the nft
   * @param tokenId token id
   * @param value amount of tokens to redeem. Should be 1 for ERC721
   */
  function redeem(address receiver, uint256 tokenId, uint256 value) external;

  function NFT() external view returns (address);

  function NFTType() external view returns (Constants.NftType);

  /**
   * @notice vesting token
   */
  function VT() external view returns (address);

  /**
   * @notice asset token
   */
  function T() external view returns (address);

  function vestingSchedules() external view returns (VestingSchedule[] memory);

}
