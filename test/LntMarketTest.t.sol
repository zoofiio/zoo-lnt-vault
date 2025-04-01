// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {MockERC20} from "./mocks/MockERC20.sol";
import {WETH} from "./mocks/WETH.sol";
import {LntMarket} from "../src/market/LntMarket.sol";
import {LntMarketFactory} from "../src/market/LntMarketFactory.sol";
import {LntMarketRouter} from "../src/market/LntMarketRouter.sol";

contract LntMarketTest is Test {
    // Contracts
    MockERC20 public tokenA;
    MockERC20 public tokenB;
    WETH public weth;
    LntMarketFactory public factory;
    LntMarketRouter public router;

    // Users
    address public alice = address(0x1);
    address public bob = address(0x2);

    // Constants
    uint256 constant ONE_DAY = 86400; // 1 day in seconds
    uint256 constant INITIAL_AMOUNT = 10000 ether;

    function setUp() public {
        // Set up users with ETH
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);

        // Deploy WETH
        weth = new WETH();

        // Deploy factory
        factory = new LntMarketFactory();

        // Deploy router using factory and WETH
        router = new LntMarketRouter(address(factory), address(weth));

        // Deploy test tokens
        tokenA = new MockERC20("Token A", "TKA", 18);
        tokenB = new MockERC20("Token B", "TKB", 18);

        // Mint initial tokens to users
        tokenA.mint(alice, INITIAL_AMOUNT);
        tokenA.mint(bob, INITIAL_AMOUNT);
        tokenB.mint(alice, INITIAL_AMOUNT);
        tokenB.mint(bob, INITIAL_AMOUNT);
    }

    function test_FactoryCreatesPairsCorrectly() public {
        // Create a new pair
        vm.prank(alice);
        factory.createPair(address(tokenA), address(tokenB));

        // Check if pair was created correctly
        address pairAddress = factory.getPair(address(tokenA), address(tokenB));
        assertFalse(pairAddress == address(0), "Pair should not be zero address");

        // Pair should be retrievable regardless of token order
        address pairAddressReversed = factory.getPair(address(tokenB), address(tokenA));
        assertEq(pairAddress, pairAddressReversed, "Pair addresses should match regardless of token order");

        // Check all pairs length
        assertEq(factory.allPairsLength(), 1, "All pairs length should be 1");

        // Verify the pair at index 0
        address pairAtIndex = factory.allPairs(0);
        assertEq(pairAtIndex, pairAddress, "Pair at index 0 should match pair address");
    }

    function test_RouterAddsERC20ToERC20LiquidityCorrectly() public {
        // Approve router to spend tokens
        uint256 amountA = 100 ether;
        uint256 amountB = 200 ether;

        vm.startPrank(alice);
        tokenA.approve(address(router), amountA);
        tokenB.approve(address(router), amountB);

        // Add liquidity
        uint256 deadline = block.timestamp + ONE_DAY;
        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            amountA,
            amountB,
            amountA, // Min amount A
            amountB, // Min amount B
            alice,
            deadline
        );
        vm.stopPrank();

        // Get pair address and contract
        address pairAddress = factory.getPair(address(tokenA), address(tokenB));
        LntMarket pair = LntMarket(pairAddress);

        // Check liquidity tokens were minted to Alice
        uint256 liquidityBalance = pair.balanceOf(alice);
        assertTrue(liquidityBalance > 0, "Alice should have received liquidity tokens");

        // Check reserves
        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
        address token0 = pair.token0();

        if (token0 == address(tokenA)) {
            assertEq(uint256(reserve0), amountA, "Reserve0 should match amountA");
            assertEq(uint256(reserve1), amountB, "Reserve1 should match amountB");
        } else {
            assertEq(uint256(reserve0), amountB, "Reserve0 should match amountB");
            assertEq(uint256(reserve1), amountA, "Reserve1 should match amountA");
        }
    }

    function test_RouterAddsETHToERC20LiquidityCorrectly() public {
        // Approve router to spend token
        uint256 tokenAmount = 100 ether;
        uint256 ethAmount = 1 ether;

        vm.startPrank(alice);
        tokenA.approve(address(router), tokenAmount);

        // Add liquidity with ETH
        uint256 deadline = block.timestamp + ONE_DAY;
        router.addLiquidityETH{value: ethAmount}(
            address(tokenA),
            tokenAmount,
            tokenAmount, // Min token amount
            ethAmount,   // Min ETH amount
            alice,
            deadline
        );
        vm.stopPrank();

        // Get pair address and contract
        address pairAddress = factory.getPair(address(tokenA), address(weth));
        LntMarket pair = LntMarket(pairAddress);

        // Check liquidity tokens were minted to Alice
        uint256 liquidityBalance = pair.balanceOf(alice);
        assertTrue(liquidityBalance > 0, "Alice should have received liquidity tokens");

        // Check reserves
        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
        address token0 = pair.token0();

        if (token0 == address(tokenA)) {
            assertEq(uint256(reserve0), tokenAmount, "Reserve0 should match tokenAmount");
            assertEq(uint256(reserve1), ethAmount, "Reserve1 should match ethAmount");
        } else {
            assertEq(uint256(reserve0), ethAmount, "Reserve0 should match ethAmount");
            assertEq(uint256(reserve1), tokenAmount, "Reserve1 should match tokenAmount");
        }
    }

    function test_RouterSwapsERC20ToERC20TokensCorrectly() public {
        // First add liquidity
        uint256 amountA = 1000 ether;
        uint256 amountB = 1000 ether;
        uint256 deadline = block.timestamp + ONE_DAY;

        vm.startPrank(alice);
        tokenA.approve(address(router), amountA);
        tokenB.approve(address(router), amountB);

        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            amountA,
            amountB,
            0, // Min amount A
            0, // Min amount B
            alice,
            deadline
        );
        vm.stopPrank();

        // Bob swaps tokens
        uint256 swapAmount = 10 ether;
        uint256 minOutputAmount = 9 ether; // Allow for some slippage

        vm.startPrank(bob);
        // Approve router
        tokenA.approve(address(router), swapAmount);

        // Check balances before swap
        uint256 bobTokenABefore = tokenA.balanceOf(bob);
        uint256 bobTokenBBefore = tokenB.balanceOf(bob);

        // Perform the swap (exact tokens for tokens)
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        
        router.swapExactTokensForTokens(
            swapAmount,
            minOutputAmount,
            path,
            bob,
            deadline
        );

        // Check balances after swap
        uint256 bobTokenAAfter = tokenA.balanceOf(bob);
        uint256 bobTokenBAfter = tokenB.balanceOf(bob);
        vm.stopPrank();

        // Verify Bob spent tokenA
        assertEq(bobTokenABefore - bobTokenAAfter, swapAmount, "Bob should have spent correct amount of tokenA");

        // Verify Bob received tokenB
        assertTrue(bobTokenBAfter - bobTokenBBefore >= minOutputAmount, "Bob should have received at least minOutputAmount of tokenB");
    }

    function test_RouterSwapsETHForTokensCorrectly() public {
        // First add liquidity
        uint256 tokenAmount = 1000 ether;
        uint256 ethAmount = 10 ether;
        uint256 deadline = block.timestamp + ONE_DAY;

        vm.startPrank(alice);
        tokenA.approve(address(router), tokenAmount);

        router.addLiquidityETH{value: ethAmount}(
            address(tokenA),
            tokenAmount,
            tokenAmount, // Min token amount
            ethAmount,   // Min ETH amount
            alice,
            deadline
        );
        vm.stopPrank();

        // Bob swaps ETH for tokens
        uint256 swapEthAmount = 1 ether;
        uint256 minOutputAmount = 90 ether; // Expected tokens based on pool ratio

        vm.startPrank(bob);

        // Check balances before swap
        uint256 bobTokenABefore = tokenA.balanceOf(bob);
        uint256 bobEthBefore = bob.balance;

        // Perform the swap (ETH for exact tokens)
        address[] memory path = new address[](2);
        path[0] = address(weth);
        path[1] = address(tokenA);
        
        router.swapExactETHForTokens{value: swapEthAmount}(
            minOutputAmount,
            path,
            bob,
            deadline
        );

        // Check balances after swap
        uint256 bobTokenAAfter = tokenA.balanceOf(bob);
        uint256 bobEthAfter = bob.balance;
        vm.stopPrank();

        // Verify Bob spent ETH
        assertEq(bobEthBefore - bobEthAfter, swapEthAmount, "Bob should have spent correct amount of ETH");

        // Verify Bob received tokenA
        assertTrue(bobTokenAAfter - bobTokenABefore >= minOutputAmount, "Bob should have received at least minOutputAmount of tokenA");
    }

    function test_RouterSwapsTokensForETHCorrectly() public {
        // First add liquidity
        uint256 tokenAmount = 1000 ether;
        uint256 ethAmount = 10 ether;
        uint256 deadline = block.timestamp + ONE_DAY;

        vm.startPrank(alice);
        tokenA.approve(address(router), tokenAmount);

        router.addLiquidityETH{value: ethAmount}(
            address(tokenA),
            tokenAmount,
            tokenAmount, // Min token amount
            ethAmount,   // Min ETH amount
            alice,
            deadline
        );
        vm.stopPrank();

        // Bob swaps tokens for ETH
        uint256 swapTokenAmount = 100 ether;
        uint256 minEthOutput = 0.9 ether; // Expected ETH based on pool ratio

        vm.startPrank(bob);
        // Approve router
        tokenA.approve(address(router), swapTokenAmount);

        // Check balances before swap
        uint256 bobTokenABefore = tokenA.balanceOf(bob);
        uint256 bobEthBefore = bob.balance;

        // Perform the swap (tokens for exact ETH)
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(weth);
        
        router.swapExactTokensForETH(
            swapTokenAmount,
            minEthOutput,
            path,
            bob,
            deadline
        );

        // Check balances after swap
        uint256 bobTokenAAfter = tokenA.balanceOf(bob);
        uint256 bobEthAfter = bob.balance;
        vm.stopPrank();

        // Verify Bob spent tokenA
        assertEq(bobTokenABefore - bobTokenAAfter, swapTokenAmount, "Bob should have spent correct amount of tokenA");

        // Verify Bob received ETH
        assertTrue(bobEthAfter - bobEthBefore >= minEthOutput, "Bob should have received at least minEthOutput of ETH");
    }

    function test_RouterRemovesERC20ToERC20LiquidityCorrectly() public {
        // First add liquidity
        uint256 amountA = 100 ether;
        uint256 amountB = 200 ether;
        uint256 deadline = block.timestamp + ONE_DAY;

        vm.startPrank(alice);
        tokenA.approve(address(router), amountA);
        tokenB.approve(address(router), amountB);

        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            amountA,
            amountB,
            amountA, // Min amount A
            amountB, // Min amount B
            alice,
            deadline
        );

        // Get pair address and liquidity token balance
        address pairAddress = factory.getPair(address(tokenA), address(tokenB));
        LntMarket pair = LntMarket(pairAddress);
        uint256 liquidityBalance = pair.balanceOf(alice);

        // Approve router to spend LP tokens
        pair.approve(address(router), liquidityBalance);

        // Check token balances before removing liquidity
        uint256 aliceTokenABefore = tokenA.balanceOf(alice);
        uint256 aliceTokenBBefore = tokenB.balanceOf(alice);

        // Remove all liquidity
        router.removeLiquidity(
            address(tokenA),
            address(tokenB),
            liquidityBalance,
            0, // Min amount A
            0, // Min amount B
            alice,
            deadline
        );

        // Check token balances after removing liquidity
        uint256 aliceTokenAAfter = tokenA.balanceOf(alice);
        uint256 aliceTokenBAfter = tokenB.balanceOf(alice);
        vm.stopPrank();

        // Verify that Alice received tokens back
        assertApproxEqRel(aliceTokenAAfter - aliceTokenABefore, amountA, 0.01e18, "Alice should have received approximately amountA tokens back");
        assertApproxEqRel(aliceTokenBAfter - aliceTokenBBefore, amountB, 0.01e18, "Alice should have received approximately amountB tokens back");

        // Verify LP balance is zero
        assertEq(pair.balanceOf(alice), 0, "Alice's LP balance should be zero after removal");
    }

    function test_RouterRemovesETHToERC20LiquidityCorrectly() public {
        // First add liquidity
        uint256 tokenAmount = 100 ether;
        uint256 ethAmount = 1 ether;
        uint256 deadline = block.timestamp + ONE_DAY;

        vm.startPrank(alice);
        tokenA.approve(address(router), tokenAmount);

        router.addLiquidityETH{value: ethAmount}(
            address(tokenA),
            tokenAmount,
            tokenAmount, // Min token amount
            ethAmount,   // Min ETH amount
            alice,
            deadline
        );

        // Get pair address and liquidity token balance
        address pairAddress = factory.getPair(address(tokenA), address(weth));
        LntMarket pair = LntMarket(pairAddress);
        uint256 liquidityBalance = pair.balanceOf(alice);

        // Approve router to spend LP tokens
        pair.approve(address(router), liquidityBalance);

        // Check balances before removing liquidity
        uint256 aliceTokenABefore = tokenA.balanceOf(alice);
        uint256 aliceEthBefore = alice.balance;

        // Remove all liquidity
        router.removeLiquidityETH(
            address(tokenA),
            liquidityBalance,
            0, // Min token amount
            0, // Min ETH amount
            alice,
            deadline
        );

        // Check balances after removing liquidity
        uint256 aliceTokenAAfter = tokenA.balanceOf(alice);
        uint256 aliceEthAfter = alice.balance;
        vm.stopPrank();

        // Verify that Alice received tokens back
        assertApproxEqRel(aliceTokenAAfter - aliceTokenABefore, tokenAmount, 0.01e18, "Alice should have received approximately tokenAmount back");

        // Verify that Alice received ETH back
        assertApproxEqRel(aliceEthAfter - aliceEthBefore, ethAmount, 0.01e18, "Alice should have received approximately ethAmount back");

        // Verify LP balance is zero
        assertEq(pair.balanceOf(alice), 0, "Alice's LP balance should be zero after removal");
    }

    function test_RouterHandlesExactOutputSwapsCorrectly() public {
        // First add liquidity
        uint256 amountA = 1000 ether;
        uint256 amountB = 1000 ether;
        uint256 deadline = block.timestamp + ONE_DAY;

        vm.startPrank(alice);
        tokenA.approve(address(router), amountA);
        tokenB.approve(address(router), amountB);

        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            amountA,
            amountB,
            0, // Min amount A
            0, // Min amount B
            alice,
            deadline
        );
        vm.stopPrank();

        // Bob wants exactly 20 tokenB
        uint256 exactOutputAmount = 20 ether;
        uint256 maxInputAmount = 25 ether; // Willing to spend up to 25 tokenA

        vm.startPrank(bob);
        // Approve router
        tokenA.approve(address(router), maxInputAmount);

        // Check balances before swap
        uint256 bobTokenABefore = tokenA.balanceOf(bob);
        uint256 bobTokenBBefore = tokenB.balanceOf(bob);

        // Perform the swap (tokens for exact tokens)
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        
        router.swapTokensForExactTokens(
            exactOutputAmount,
            maxInputAmount,
            path,
            bob,
            deadline
        );

        // Check balances after swap
        uint256 bobTokenAAfter = tokenA.balanceOf(bob);
        uint256 bobTokenBAfter = tokenB.balanceOf(bob);
        vm.stopPrank();

        // Verify Bob received exactly the requested amount of tokenB
        assertEq(bobTokenBAfter - bobTokenBBefore, exactOutputAmount, "Bob should have received exactly the requested amount of tokenB");

        // Verify Bob spent less than or equal to the max amount of tokenA
        uint256 tokenASpent = bobTokenABefore - bobTokenAAfter;
        assertTrue(tokenASpent <= maxInputAmount, "Bob should have spent less than or equal to maxInputAmount");
    }
}