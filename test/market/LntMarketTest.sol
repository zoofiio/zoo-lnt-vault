// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../../src/market/LntMarket.sol";
import "../../src/market/LntMarketFactory.sol";
import "../mocks/MockERC20.sol";

contract LntMarketTest is Test {
    LntMarketFactory public factory;
    LntMarket public market;
    MockERC20 public token0;
    MockERC20 public token1;
    address public feeTo;
    address public alice;
    address public bob;

    function setUp() public {
        // Initialize users
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        feeTo = makeAddr("feeTo");
        
        // Deploy mock tokens
        token0 = new MockERC20("Token0", "TKN0", 18);
        token1 = new MockERC20("Token1", "TKN1", 18);
        
        // Make sure token0's address is less than token1's address for consistent pair creation
        if (address(token0) > address(token1)) {
            (token0, token1) = (token1, token0);
        }

        // Deploy the factory
        factory = new LntMarketFactory();
        
        // Set fee recipient
        factory.setFeeTo(feeTo);
        
        // Create the LntMarket pair
        address marketAddress = factory.createPair(address(token0), address(token1));
        market = LntMarket(marketAddress);
        
        // Setup initial token balances
        token0.mint(alice, 1000 ether);
        token1.mint(alice, 1000 ether);
        token0.mint(bob, 1000 ether);
        token1.mint(bob, 1000 ether);
    }

    function testInitialization() public {
        assertEq(market.factory(), address(factory));
        assertEq(market.token0(), address(token0));
        assertEq(market.token1(), address(token1));
        assertEq(market.totalSupply(), 0);
        (uint112 reserve0, uint112 reserve1, ) = market.getReserves();
        assertEq(reserve0, 0);
        assertEq(reserve1, 0);
    }

    function testAddLiquidity() public {
        uint amountA = 100 ether;
        uint amountB = 200 ether;
        
        vm.startPrank(alice);
        
        token0.approve(address(market), amountA);
        token1.approve(address(market), amountB);
        
        // Transfer tokens to market contract
        token0.transfer(address(market), amountA);
        token1.transfer(address(market), amountB);
        
        // Add liquidity
        uint liquidity = market.mint(alice);
        vm.stopPrank();
        
        // Check balances and state
        assertGt(liquidity, 0, "Liquidity should be > 0");
        assertEq(market.balanceOf(alice), liquidity);
        assertEq(token0.balanceOf(address(market)), amountA);
        assertEq(token1.balanceOf(address(market)), amountB);
        
        (uint112 reserve0, uint112 reserve1, ) = market.getReserves();
        assertEq(reserve0, uint112(amountA));
        assertEq(reserve1, uint112(amountB));
    }

    function testSwap() public {
        // First add liquidity
        vm.startPrank(alice);
        uint amountA = 100 ether;
        uint amountB = 100 ether;
        
        token0.approve(address(market), amountA);
        token1.approve(address(market), amountB);
        
        token0.transfer(address(market), amountA);
        token1.transfer(address(market), amountB);
        
        market.mint(alice);
        vm.stopPrank();
        
        // Now bob swaps token0 for token1
        vm.startPrank(bob);
        uint swapAmount = 10 ether;
        token0.transfer(address(market), swapAmount);
        
        // Calculate expected output with 0.3% fee
        (uint112 reserve0, uint112 reserve1, ) = market.getReserves();
        uint outputAmount = getAmountOut(swapAmount, uint256(reserve0), uint256(reserve1));
        
        // Execute swap
        market.swap(0, outputAmount, bob, new bytes(0));
        vm.stopPrank();
        
        // Verify balances after swap
        assertEq(token1.balanceOf(bob), 1000 ether - 100 ether + outputAmount);
        
        // Verify reserves
        (uint112 newReserve0, uint112 newReserve1, ) = market.getReserves();
        assertEq(uint256(newReserve0), uint256(reserve0) + swapAmount);
        assertEq(uint256(newReserve1), uint256(reserve1) - outputAmount);
    }

    function testBurn() public {
        // First add liquidity
        vm.startPrank(alice);
        uint amountA = 100 ether;
        uint amountB = 200 ether;
        
        token0.transfer(address(market), amountA);
        token1.transfer(address(market), amountB);
        
        uint liquidity = market.mint(alice);
        
        // Remove liquidity
        market.transfer(address(market), liquidity);
        (uint amount0, uint amount1) = market.burn(alice);
        vm.stopPrank();
        
        // Check balances
        assertEq(market.balanceOf(alice), 0);
        assertEq(market.totalSupply(), 1000); // MINIMUM_LIQUIDITY remains locked
        assertEq(token0.balanceOf(alice), 1000 ether - amountA + amount0);
        assertEq(token1.balanceOf(alice), 1000 ether - amountB + amount1);
        
        // Check reserves
        (uint112 reserve0, uint112 reserve1, ) = market.getReserves();
        assertEq(reserve0, uint112(amountA - amount0));
        assertEq(reserve1, uint112(amountB - amount1));
    }

    // Helper function to calculate expected output amount with fee
    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut) internal pure returns (uint amountOut) {
        uint amountInWithFee = amountIn * 997;
        uint numerator = amountInWithFee * reserveOut;
        uint denominator = (reserveIn * 1000) + amountInWithFee;
        amountOut = numerator / denominator;
    }
}