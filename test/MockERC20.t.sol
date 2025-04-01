// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import "./mocks/MockERC20.sol";

contract MockERC20Test is Test {
  MockERC20 t;

  function setUp() public {
    t = new MockERC20("ERC20 Mock", "ERC20", 18);
  }

  function testName() public {
    assertEq(t.name(), "ERC20 Mock");
  }
}