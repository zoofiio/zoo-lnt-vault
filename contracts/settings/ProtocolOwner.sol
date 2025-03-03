// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/Context.sol";
import "../interfaces/IZooProtocol.sol";

abstract contract ProtocolOwner is Context {
  IZooProtocol public immutable protocol;

  constructor(address _protocol_) {
    require(_protocol_ != address(0), "Zero address detected");
    protocol = IZooProtocol(_protocol_);
  }

  modifier onlyProtocol() {
    require(_msgSender() == address(protocol), "Ownable: caller is not the protocol");
    _;
  }

  modifier onlyOwner() {
    require(_msgSender() == IZooProtocol(protocol).protocolOwner(), "Ownable: caller is not the owner");
    _;
  }

  function owner() public view returns(address) {
    return IZooProtocol(protocol).protocolOwner();
  }
}