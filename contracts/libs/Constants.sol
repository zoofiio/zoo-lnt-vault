// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

library Constants {
  /**
   * @notice The address interpreted as native token of the chain.
   */
  address public constant NATIVE_TOKEN = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

  uint256 public constant PROTOCOL_DECIMALS = 10;

  enum NftType {
    UNKNOWN,
    ERC721,
    ERC1155
  }

}