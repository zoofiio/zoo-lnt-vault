// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "./MockERC20.sol";
import "./WETH.sol";

contract MockTest is Test {
    MockERC20 public token;
    WETH public weth;
    address public user;
    
    function setUp() public {
        user = makeAddr("user");
        token = new MockERC20("Test Token", "TT", 18); // Fix: Add decimals parameter
        weth = new WETH();
        
        vm.deal(user, 10 ether);
        token.mint(user, 1000 * 10**18);
    }
    
    function testTokenMint() public {
        assertEq(token.balanceOf(user), 1000 * 10**18);
    }
    
    function testWethDeposit() public {
        vm.startPrank(user);
        weth.deposit{value: 1 ether}();
        vm.stopPrank();
        
        assertEq(weth.balanceOf(user), 1 ether);
    }
    
    function testWethWithdraw() public {
        vm.startPrank(user);
        weth.deposit{value: 1 ether}();
        uint256 balanceBefore = user.balance;
        weth.withdraw(0.5 ether);
        vm.stopPrank();
        
        assertEq(weth.balanceOf(user), 0.5 ether);
        assertEq(user.balance, balanceBefore + 0.5 ether);
    }
}