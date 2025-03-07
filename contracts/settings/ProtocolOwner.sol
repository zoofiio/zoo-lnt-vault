// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/Context.sol";
import "../interfaces/IZooProtocol.sol";

abstract contract ProtocolOwner is Context {
  address public immutable protocol;

  constructor(address _protocol_) {
    require(_protocol_ != address(0), "Zero address detected");
    protocol = _protocol_;
  }

  modifier onlyOwner() {
    require(_msgSender() == owner(), "Ownable: caller is not the owner");
    _;
  }

  function owner() public view returns(address) {
    return IZooProtocol(protocol).protocolOwner();
  }
}