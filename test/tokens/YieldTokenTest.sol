// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../../src/tokens/YieldToken.sol";
import "../mocks/MockERC20.sol";
import "../../src/libs/Constants.sol";

contract YieldTokenTest is Test {
        YieldToken public yieldToken;
        address public vault;
        address public owner;
        address public user1;
        address public user2;
        MockERC20 public rewardToken1;
        MockERC20 public rewardToken2;

        function setUp() public {
                owner = makeAddr("owner");
                vault = makeAddr("vault");
                user1 = makeAddr("user1");
                user2 = makeAddr("user2");
                
                vm.startPrank(owner);
                
                // Deploy the YieldToken
                yieldToken = new YieldToken(vault, "Yield Token", "YT");
                
                // Deploy mock tokens for rewards
                rewardToken1 = new MockERC20("Reward Token 1", "RWD1", 18);
                rewardToken2 = new MockERC20("Reward Token 2", "RWD2", 18);
                
                // Mint some YieldTokens to test accounts
                vm.startPrank(vault);
                yieldToken.mint(user1, 1000 ether);
                yieldToken.mint(user2, 500 ether);
                vm.stopPrank();
                
                // Mint reward tokens to vault for distribution
                rewardToken1.mint(vault, 10000 ether);
                rewardToken2.mint(vault, 10000 ether);
                
                vm.stopPrank();
        }
        
        function testInitialization() public view {
                assertEq(yieldToken.name(), "Yield Token");
                assertEq(yieldToken.symbol(), "YT");
                assertEq(yieldToken.totalSupply(), 1500 ether);
                assertEq(yieldToken.balanceOf(user1), 1000 ether);
                assertEq(yieldToken.balanceOf(user2), 500 ether);
                assertEq(yieldToken.vault(), vault);
                assertEq(yieldToken.circulatingSupply(), 1500 ether);
        }
        
        function testExcludedAddresses() public {
                assertTrue(yieldToken.excludedFromRewards(vault));
                assertTrue(yieldToken.excludedFromRewards(address(yieldToken)));
                assertFalse(yieldToken.excludedFromRewards(user1));
                assertFalse(yieldToken.excludedFromRewards(user2));
        }
        
        function testAddRewards() public {
                vm.startPrank(vault);
                
                // Approve reward tokens for YieldToken contract
                rewardToken1.approve(address(yieldToken), 1000 ether);
                
                // Add rewards
                yieldToken.addRewards(address(rewardToken1), 1000 ether);
                vm.stopPrank();
                
                // Check reward tokens list
                address[] memory rewardTokens = yieldToken.getRewardsTokens();
                assertEq(rewardTokens.length, 1);
                assertEq(rewardTokens[0], address(rewardToken1));
                
                // Check that tokens were transferred
                assertEq(rewardToken1.balanceOf(address(yieldToken)), 1000 ether);
        }
        
        function testAddTimeWeightedRewards() public {
                vm.startPrank(vault);
                
                // First, users need to collect time weighted balance
                vm.warp(block.timestamp + 1 days);
                
                vm.stopPrank();
                
                // User1 collects time weighted balance
                vm.prank(user1);
                yieldToken.collectTimeWeightedBalance();
                
                // Add time weighted rewards
                vm.startPrank(vault);
                rewardToken2.approve(address(yieldToken), 500 ether);
                yieldToken.addTimeWeightedRewards(address(rewardToken2), 500 ether);
                vm.stopPrank();
                
                // Check time-weighted reward tokens list
                address[] memory twRewardTokens = yieldToken.getTimeWeightedRewardsTokens();
                assertEq(twRewardTokens.length, 1);
                assertEq(twRewardTokens[0], address(rewardToken2));
                
                // Check that tokens were transferred
                assertEq(rewardToken2.balanceOf(address(yieldToken)), 500 ether);
        }
        
        function testCollectTimeWeightedBalance() public {
                // Warp time forward to accumulate time-weighted balance
                uint startTime = block.timestamp;
                vm.warp(startTime + 1 days);
                
                // Check collectible balance before collection
                (uint collectTimestamp, uint deltaTimeWeightedAmount) = yieldToken.collectableTimeWeightedBalance(user1);
                assertEq(collectTimestamp, startTime + 1 days);
                assertEq(deltaTimeWeightedAmount, 1000 ether * 1 days);
                
                // Collect time-weighted balance
                vm.prank(user1);
                yieldToken.collectTimeWeightedBalance();
                
                // Check time-weighted balance after collection
                assertEq(yieldToken.timeWeightedBalanceOf(user1), 1000 ether * 1 days);
                assertEq(yieldToken.totalTimeWeightedBalance(), 1000 ether * 1 days);
                assertEq(yieldToken.lastCollectTime(user1), startTime + 1 days);
        }
        
        function testClaimRewards() public {
                // Setup: Add rewards and time-weighted balance
                vm.warp(block.timestamp + 1 days);
                
                vm.startPrank(vault);
                rewardToken1.approve(address(yieldToken), 1000 ether);
                yieldToken.addRewards(address(rewardToken1), 1000 ether);
                vm.stopPrank();
                
                // User1 collects time-weighted balance
                vm.prank(user1);
                yieldToken.collectTimeWeightedBalance();
                
                // Add time-weighted rewards
                vm.startPrank(vault);
                rewardToken2.approve(address(yieldToken), 500 ether);
                yieldToken.addTimeWeightedRewards(address(rewardToken2), 500 ether);
                vm.stopPrank();
                
                // Calculate expected rewards using integer math without overflow
                uint256 totalSupply = yieldToken.totalSupply();
                uint256 user1Supply = yieldToken.balanceOf(user1);
                uint256 user2Supply = yieldToken.balanceOf(user2);
                uint256 rewardsAmount = 1000 ether;
                
                uint256 expectedReward1 = rewardsAmount * user1Supply / totalSupply;
                
                // User1 claims rewards
                vm.prank(user1);
                yieldToken.claimRewards();
                
                // Check that rewards were transferred to user1
                assertEq(rewardToken1.balanceOf(user1), expectedReward1);
                
                // User2 claims rewards
                uint256 expectedReward2 = rewardsAmount * user2Supply / totalSupply;
                
                vm.prank(user2);
                yieldToken.claimRewards();
                
                // Check that rewards were transferred to user2
                assertEq(rewardToken1.balanceOf(user2), expectedReward2);
                
                // Verify all rewards were distributed
                assertApproxEqAbs(
                        rewardToken1.balanceOf(user1) + rewardToken1.balanceOf(user2),
                        1000 ether,
                        10 // Allow small rounding errors due to integer division
                );
        }
        
        function testTransferWithRewards() public {
                // Setup: Add rewards
                vm.prank(vault);
                rewardToken1.approve(address(yieldToken), 1000 ether);
                yieldToken.addRewards(address(rewardToken1), 1000 ether);
                
                // Record balances before transfer
                uint user1BalanceBefore = yieldToken.balanceOf(user1);
                uint user2BalanceBefore = yieldToken.balanceOf(user2);
                
                // Transfer tokens from user1 to user2
                vm.prank(user1);
                yieldToken.transfer(user2, 300 ether);
                
                // Check balances after transfer
                assertEq(yieldToken.balanceOf(user1), user1BalanceBefore - 300 ether);
                assertEq(yieldToken.balanceOf(user2), user2BalanceBefore + 300 ether);
                
                // Check that rewards were claimed during transfer
                assertGt(rewardToken1.balanceOf(user1), 0);
        }
        
        function testEpochEndTimestamp() public {
                // Set epoch end timestamp
                uint epochEnd = block.timestamp + 30 days;
                vm.prank(vault);
                yieldToken.setEpochEndTimestamp(epochEnd);
                
                assertEq(yieldToken.epochEndTimestamp(), epochEnd);
                
                // Warp past epoch end
                vm.warp(block.timestamp + 60 days);
                
                // Check collectible time-weighted balance is capped at epoch end
                (uint collectTimestamp, uint deltaTimeWeightedAmount) = yieldToken.collectableTimeWeightedBalance(user1);
                assertEq(collectTimestamp, epochEnd);
                assertEq(deltaTimeWeightedAmount, 1000 ether * 30 days);
        }
}
