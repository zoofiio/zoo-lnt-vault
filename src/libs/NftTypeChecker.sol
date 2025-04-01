// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import {Constants} from "./Constants.sol";

library NftTypeChecker {

    bytes4 private constant INTERFACE_ID_ERC721 = 0x80ac58cd;
    bytes4 private constant INTERFACE_ID_ERC1155 = 0xd9b67a26;

    function getNftType(address nft) internal view returns (Constants.NftType) {
        if (IERC165(nft).supportsInterface(INTERFACE_ID_ERC721)) {
            return Constants.NftType.ERC721;
        }
        if (IERC165(nft).supportsInterface(INTERFACE_ID_ERC1155)) {
            return Constants.NftType.ERC1155;
        }
        return Constants.NftType.UNKNOWN;
    }

}
