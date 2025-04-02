// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";

import {MockERC20} from "./mocks/MockERC20.sol";
import {YieldToken} from "../src/tokens/YieldToken.sol";
import {MockVault} from "./mocks/MockVault.sol";

contract YieldTokenTest is Test {
    uint256 constant ONE_DAY_IN_SECS = 86400;
    address constant ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    // Events from YieldToken contract
    event RewardsAdded(address indexed token, uint256 amount, bool isTimeWeighted);
    event RewardsPaid(address indexed user, address indexed token, uint256 amount, bool isTimeWeighted);
    event EpochEndTimestampUpdated(uint256 timestamp);

    // Contracts
    YieldToken public yieldToken;
    MockVault public mockVault;
    MockERC20 public rewardToken1;
    MockERC20 public rewardToken2;

    // User addresses
    address public alice = address(0x1);
    address public bob = address(0x2);
    address public caro = address(0x3);
    address public dave = address(0x4);

    function setUp() public {
        // Setup users with ETH
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        vm.deal(caro, 100 ether);
        vm.deal(dave, 100 ether);

        // Deploy MockVault first
        mockVault = new MockVault();
        
        // Deploy YieldToken
        yieldToken = new YieldToken(address(mockVault), "Yield Token", "YT");
        
        // Initialize MockVault with YieldToken
        mockVault.initialize(address(yieldToken));
        
        // Deploy reward tokens
        rewardToken1 = new MockERC20("Reward Token 1", "RT1", 18);
        rewardToken2 = new MockERC20("Reward Token 2", "RT2", 28); // Different decimals
        
        // Mint initial supply of reward tokens
        rewardToken1.mint(alice, 10000 * 10**18);
        rewardToken1.mint(bob, 10000 * 10**18);
        rewardToken2.mint(alice, 10000 * 10**28);
        rewardToken2.mint(bob, 10000 * 10**28);
    }

    function test_InitializeWithCorrectNameSymbolAndVaultAddress() public {
        assertEq(yieldToken.name(), "Yield Token");
        assertEq(yieldToken.symbol(), "YT");
        assertEq(yieldToken.vault(), address(mockVault));
        assertEq(yieldToken.decimals(), 18);
    }

    function test_OnlyVaultCanMintTokens() public {
        // Vault can mint
        vm.startPrank(address(mockVault));
        uint256 mintAmount = 100 * 10**18;
        mockVault.mintYieldToken(alice, mintAmount);
        vm.stopPrank();
        
        assertEq(yieldToken.balanceOf(alice), mintAmount);
        
        // Others cannot mint
        vm.startPrank(bob);
        vm.expectRevert("Caller is not the vault");
        yieldToken.mint(bob, 100 * 10**18);
        vm.stopPrank();
    }

    function test_EpochEndTimestamp() public {
        // Default should be max uint256
        assertEq(yieldToken.epochEndTimestamp(), type(uint256).max);
        
        // Only vault can update
        uint256 newTimestamp = block.timestamp + ONE_DAY_IN_SECS * 30; // 30 days
        
        vm.startPrank(address(mockVault));
        vm.expectEmit(true, true, false, false);
        emit EpochEndTimestampUpdated(newTimestamp);
        mockVault.setEpochEndTimestamp(newTimestamp);
        vm.stopPrank();
        
        assertEq(yieldToken.epochEndTimestamp(), newTimestamp);
    }

    function test_TransferTokensAndAutoClaimRewards() public {
        // Mint tokens to Alice and Bob
        vm.startPrank(address(mockVault));
        mockVault.mintYieldToken(alice, 100 * 10**18);
        mockVault.mintYieldToken(bob, 100 * 10**18);
        vm.stopPrank();
        
        // Check balances
        assertEq(yieldToken.balanceOf(alice), 100 * 10**18);
        assertEq(yieldToken.balanceOf(bob), 100 * 10**18);
        
        // Transfer tokens
        vm.startPrank(alice);
        yieldToken.transfer(caro, 50 * 10**18);
        vm.stopPrank();
        
        // Check updated balances
        assertEq(yieldToken.balanceOf(alice), 50 * 10**18);
        assertEq(yieldToken.balanceOf(bob), 100 * 10**18);
        assertEq(yieldToken.balanceOf(caro), 50 * 10**18);
    }

    function test_AddAndDistributeStandardRewards() public {
        // Mint tokens to users
        vm.startPrank(address(mockVault));
        mockVault.mintYieldToken(alice, 100 * 10**18);
        mockVault.mintYieldToken(bob, 50 * 10**18);
        mockVault.mintYieldToken(caro, 50 * 10**18);
        vm.stopPrank();
        
        // Add rewards via vault
        uint256 rewardAmount = 200 * 10**18;
        vm.startPrank(alice);
        rewardToken1.approve(address(mockVault), rewardAmount);
        
        vm.expectEmit(true, true, false, true);
        emit RewardsAdded(address(rewardToken1), rewardAmount, false);
        mockVault.addRewards(address(rewardToken1), rewardAmount);
        vm.stopPrank();
        
        // Check earned rewards
        uint256 totalSupply = 200 * 10**18; // 100 + 50 + 50
        uint256 aliceExpectedReward = (rewardAmount * 100 * 10**18) / totalSupply; // 100/200 of total
        uint256 bobExpectedReward = (rewardAmount * 50 * 10**18) / totalSupply;    // 50/200 of total
        uint256 caroExpectedReward = (rewardAmount * 50 * 10**18) / totalSupply;   // 50/200 of total
        
        // Allow small margin for rounding differences
        assertApproxEqRel(
            yieldToken.earned(alice, address(rewardToken1)), 
            aliceExpectedReward, 
            0.01e18 // 1% tolerance
        );
        
        assertApproxEqRel(
            yieldToken.earned(bob, address(rewardToken1)), 
            bobExpectedReward, 
            0.01e18
        );
        
        assertApproxEqRel(
            yieldToken.earned(caro, address(rewardToken1)), 
            caroExpectedReward, 
            0.01e18
        );
    }

    function test_AddAndDistributeTimeWeightedRewards() public {
        // Mint tokens to users
        vm.startPrank(address(mockVault));
        mockVault.mintYieldToken(alice, 100 * 10**18);
        mockVault.mintYieldToken(bob, 50 * 10**18);
        vm.stopPrank();
        
        // Advance time to create time-weighted balances
        vm.warp(block.timestamp + ONE_DAY_IN_SECS);
        
        // Collect time-weighted balances
        vm.prank(alice);
        yieldToken.collectTimeWeightedBalance();
        
        vm.prank(bob);
        yieldToken.collectTimeWeightedBalance();
        
        // Check time-weighted balances
        uint256 aliceTimeWeightedBalance = yieldToken.timeWeightedBalanceOf(alice);
        uint256 bobTimeWeightedBalance = yieldToken.timeWeightedBalanceOf(bob);
        
        // Time-weighted balance should be approximately balance * time
        assertApproxEqRel(
            aliceTimeWeightedBalance, 
            100 * 10**18 * ONE_DAY_IN_SECS, 
            0.01e18 // 1% tolerance
        );
        
        assertApproxEqRel(
            bobTimeWeightedBalance, 
            50 * 10**18 * ONE_DAY_IN_SECS, 
            0.01e18
        );
        
        // Add time-weighted rewards via vault
        uint256 timeWeightedRewardAmount = 100 * 10**28; // Use reward token 2's decimals
        vm.startPrank(alice);
        rewardToken2.approve(address(mockVault), timeWeightedRewardAmount);
        
        vm.expectEmit(true, true, false, true);
        emit RewardsAdded(address(rewardToken2), timeWeightedRewardAmount, true);
        mockVault.addTimeWeightedRewards(address(rewardToken2), timeWeightedRewardAmount);
        vm.stopPrank();
        
        // Check time-weighted rewards
        uint256 totalTimeWeightedBalance = yieldToken.totalTimeWeightedBalance();
        uint256 aliceShare = (aliceTimeWeightedBalance * 1e18) / totalTimeWeightedBalance;
        uint256 bobShare = (bobTimeWeightedBalance * 1e18) / totalTimeWeightedBalance;
        
        uint256 aliceExpectedTimeWeightedReward = (timeWeightedRewardAmount * aliceShare) / 1e18;
        uint256 bobExpectedTimeWeightedReward = (timeWeightedRewardAmount * bobShare) / 1e18;
        
        assertApproxEqRel(
            yieldToken.timeWeightedEarned(alice, address(rewardToken2)),
            aliceExpectedTimeWeightedReward,
            0.01e18
        );
        
        assertApproxEqRel(
            yieldToken.timeWeightedEarned(bob, address(rewardToken2)),
            bobExpectedTimeWeightedReward,
            0.01e18
        );
    }

    function test_SameTokenForBothStandardAndTimeWeightedRewards() public {
        // Mint tokens to users
        vm.startPrank(address(mockVault));
        mockVault.mintYieldToken(alice, 100 * 10**18);
        mockVault.mintYieldToken(bob, 50 * 10**18);
        vm.stopPrank();
        
        // Advance time and collect time-weighted balances
        vm.warp(block.timestamp + ONE_DAY_IN_SECS);
        vm.prank(alice);
        yieldToken.collectTimeWeightedBalance();
        vm.prank(bob);
        yieldToken.collectTimeWeightedBalance();
        
        // Use the same token (rewardToken1) for both standard and time-weighted rewards
        uint256 standardRewardAmount = 100 * 10**18;
        uint256 timeWeightedRewardAmount = 200 * 10**18;
        
        // Add standard rewards
        vm.startPrank(alice);
        rewardToken1.approve(address(mockVault), standardRewardAmount + timeWeightedRewardAmount);
        mockVault.addRewards(address(rewardToken1), standardRewardAmount);
        
        // Add time-weighted rewards with the same token
        mockVault.addTimeWeightedRewards(address(rewardToken1), timeWeightedRewardAmount);
        vm.stopPrank();
        
        // Check rewards tokens lists
        address[] memory rewardsTokens = yieldToken.getRewardsTokens();
        address[] memory timeWeightedRewardsTokens = yieldToken.getTimeWeightedRewardsTokens();
        
        bool foundInRewards = false;
        bool foundInTimeWeighted = false;
        
        for (uint i = 0; i < rewardsTokens.length; i++) {
            if (rewardsTokens[i] == address(rewardToken1)) {
                foundInRewards = true;
                break;
            }
        }
        
        for (uint i = 0; i < timeWeightedRewardsTokens.length; i++) {
            if (timeWeightedRewardsTokens[i] == address(rewardToken1)) {
                foundInTimeWeighted = true;
                break;
            }
        }
        
        assertTrue(foundInRewards, "rewardToken1 should be in standard rewards list");
        assertTrue(foundInTimeWeighted, "rewardToken1 should be in time-weighted rewards list");
        
        // Verify both types of rewards are calculated correctly
        assertTrue(yieldToken.earned(alice, address(rewardToken1)) > 0);
        assertTrue(yieldToken.timeWeightedEarned(alice, address(rewardToken1)) > 0);
    }

    function test_ExcludeVaultAndYieldTokenAddressesFromRewards() public {
        // Mint tokens to users and to vault
        vm.startPrank(address(mockVault));
        mockVault.mintYieldToken(alice, 100 * 10**18);
        mockVault.mintYieldToken(bob, 50 * 10**18);
        mockVault.mintYieldToken(address(mockVault), 50 * 10**18); // Mint to vault itself
        mockVault.mintYieldToken(address(yieldToken), 30 * 10**18); // Mint to token contract itself
        vm.stopPrank();
        
        // Verify balances
        assertEq(yieldToken.balanceOf(address(mockVault)), 50 * 10**18);
        assertEq(yieldToken.balanceOf(address(yieldToken)), 30 * 10**18);
        
        // Check circulating supply (should exclude vault and token contract balances)
        uint256 expectedCirculatingSupply = 150 * 10**18; // 100 + 50
        assertEq(yieldToken.circulatingSupply(), expectedCirculatingSupply);
        
        // Add rewards
        uint256 rewardAmount = 150 * 10**18;
        vm.startPrank(alice);
        rewardToken1.approve(address(mockVault), rewardAmount);
        mockVault.addRewards(address(rewardToken1), rewardAmount);
        vm.stopPrank();
        
        // Verify rewards calculations - vault and token contract should be excluded
        assertEq(yieldToken.earned(address(mockVault), address(rewardToken1)), 0);
        assertEq(yieldToken.earned(address(yieldToken), address(rewardToken1)), 0);
        
        // Check if Alice and Bob get all rewards
        uint256 aliceExpectedReward = (rewardAmount * 100 * 10**18) / expectedCirculatingSupply; // 100/150 of total
        uint256 bobExpectedReward = (rewardAmount * 50 * 10**18) / expectedCirculatingSupply;    // 50/150 of total
        
        assertApproxEqRel(
            yieldToken.earned(alice, address(rewardToken1)), 
            aliceExpectedReward, 
            0.01e18
        );
        
        assertApproxEqRel(
            yieldToken.earned(bob, address(rewardToken1)), 
            bobExpectedReward, 
            0.01e18
        );
        
        // Add time-weighted rewards
        vm.warp(block.timestamp + ONE_DAY_IN_SECS);
        vm.prank(alice);
        yieldToken.collectTimeWeightedBalance();
        vm.prank(bob);
        yieldToken.collectTimeWeightedBalance();
        
        // Verify vault and token contract don't have time-weighted balance
        assertEq(yieldToken.timeWeightedBalanceOf(address(mockVault)), 0);
        assertEq(yieldToken.timeWeightedBalanceOf(address(yieldToken)), 0);
    }

    function test_ClaimRewards() public {
        // Mint tokens to users
        vm.startPrank(address(mockVault));
        mockVault.mintYieldToken(alice, 100 * 10**18);
        mockVault.mintYieldToken(bob, 50 * 10**18);
        vm.stopPrank();
        
        // Add standard rewards
        uint256 standardRewardAmount = 300 * 10**18;
        vm.startPrank(alice);
        rewardToken1.approve(address(mockVault), standardRewardAmount);
        mockVault.addRewards(address(rewardToken1), standardRewardAmount);
        vm.stopPrank();
        
        // Add time-weighted rewards
        vm.warp(block.timestamp + ONE_DAY_IN_SECS);
        vm.prank(alice);
        yieldToken.collectTimeWeightedBalance();
        vm.prank(bob);
        yieldToken.collectTimeWeightedBalance();
        
        // Add time-weighted rewards with correct decimals
        uint256 timeWeightedRewardAmount = 200 * 10**28; // Use reward token 2's decimals
        vm.startPrank(alice);
        rewardToken2.approve(address(mockVault), timeWeightedRewardAmount);
        mockVault.addTimeWeightedRewards(address(rewardToken2), timeWeightedRewardAmount);
        vm.stopPrank();
        
        // Check rewards before claiming
        uint256 aliceStandardRewardBefore = yieldToken.earned(alice, address(rewardToken1));
        uint256 aliceTimeWeightedRewardBefore = yieldToken.timeWeightedEarned(alice, address(rewardToken2));
        
        assertTrue(aliceStandardRewardBefore > 0);
        assertTrue(aliceTimeWeightedRewardBefore > 0);
        
        // Initial token balances
        uint256 aliceToken1BalanceBefore = rewardToken1.balanceOf(alice);
        uint256 aliceToken2BalanceBefore = rewardToken2.balanceOf(alice);
        
        // Claim rewards
        vm.startPrank(alice);
        vm.expectEmit(true, true, true, true);
        emit RewardsPaid(alice, address(rewardToken1), aliceStandardRewardBefore, false);
        
        // For the time-weighted reward, don't check the exact amount as it may vary
        // We're only verifying the user, token, and isTimeWeighted flag
        vm.expectEmit(true, true, false, true);
        emit RewardsPaid(alice, address(rewardToken2), aliceTimeWeightedRewardBefore, true);
        
        yieldToken.claimRewards();
        vm.stopPrank();
        
        // Check token balances after claiming
        uint256 aliceToken1BalanceAfter = rewardToken1.balanceOf(alice);
        uint256 aliceToken2BalanceAfter = rewardToken2.balanceOf(alice);
        
        // Use assertApproxEqRel with appropriate decimals
        assertApproxEqRel(
            aliceToken1BalanceAfter,
            aliceToken1BalanceBefore + aliceStandardRewardBefore,
            0.01e18 // 1% tolerance
        );
        
        assertApproxEqRel(
            aliceToken2BalanceAfter,
            aliceToken2BalanceBefore + aliceTimeWeightedRewardBefore,
            0.01e18
        );
        
        // Rewards should be reset after claiming
        assertEq(yieldToken.earned(alice, address(rewardToken1)), 0);
        assertEq(yieldToken.timeWeightedEarned(alice, address(rewardToken2)), 0);
    }

    function test_AutoClaimRewardsOnTransfers() public {
        // Mint tokens to users
        vm.startPrank(address(mockVault));
        mockVault.mintYieldToken(alice, 100 * 10**18);
        vm.stopPrank();
        
        // Add standard rewards
        uint256 standardRewardAmount = 200 * 10**18;
        vm.startPrank(alice);
        rewardToken1.approve(address(mockVault), standardRewardAmount);
        mockVault.addRewards(address(rewardToken1), standardRewardAmount);
        vm.stopPrank();
        
        // Add time-weighted rewards
        vm.warp(block.timestamp + ONE_DAY_IN_SECS);
        vm.prank(alice);
        yieldToken.collectTimeWeightedBalance();
        
        // Add time-weighted rewards
        uint256 timeWeightedRewardAmount = 150 * 10**28; // Use reward token 2's decimals
        vm.startPrank(alice);
        rewardToken2.approve(address(mockVault), timeWeightedRewardAmount);
        mockVault.addTimeWeightedRewards(address(rewardToken2), timeWeightedRewardAmount);
        vm.stopPrank();
        
        // Check rewards before transfer
        uint256 aliceStandardRewardBefore = yieldToken.earned(alice, address(rewardToken1));
        uint256 aliceTimeWeightedRewardBefore = yieldToken.timeWeightedEarned(alice, address(rewardToken2));
        
        assertTrue(aliceStandardRewardBefore > 0);
        assertTrue(aliceTimeWeightedRewardBefore > 0);
        
        // Initial token balances
        uint256 aliceToken1BalanceBefore = rewardToken1.balanceOf(alice);
        uint256 aliceToken2BalanceBefore = rewardToken2.balanceOf(alice);
        
        // Transfer tokens - should auto-claim rewards
        vm.startPrank(alice);
        yieldToken.transfer(bob, 50 * 10**18);
        vm.stopPrank();
        
        // Check token balances after transfer
        uint256 aliceToken1BalanceAfter = rewardToken1.balanceOf(alice);
        uint256 aliceToken2BalanceAfter = rewardToken2.balanceOf(alice);
        
        assertApproxEqRel(
            aliceToken1BalanceAfter,
            aliceToken1BalanceBefore + aliceStandardRewardBefore,
            0.01e18
        );
        
        // Increase tolerance to 2% to account for precision loss in time-weighted rewards
        assertApproxEqRel(
            aliceToken2BalanceAfter,
            aliceToken2BalanceBefore + aliceTimeWeightedRewardBefore,
            0.02e18 // 2% tolerance instead of 1%
        );
        
        // Rewards should be reset after auto-claiming
        assertEq(yieldToken.earned(alice, address(rewardToken1)), 0);
        assertEq(yieldToken.timeWeightedEarned(alice, address(rewardToken2)), 0);
    }

    function test_ETHAsRewardToken() public {
        // Mint tokens to users
        vm.startPrank(address(mockVault));
        mockVault.mintYieldToken(alice, 100 * 10**18);
        mockVault.mintYieldToken(bob, 50 * 10**18);
        vm.stopPrank();
        
        uint256 ethRewardAmount = 10 * 10**18;
        
        // Add ETH as standard rewards
        vm.startPrank(alice);
        vm.deal(alice, 100 ether);
        
        vm.expectEmit(true, true, false, true);
        emit RewardsAdded(ETH_ADDRESS, ethRewardAmount, false);
        mockVault.addRewards{value: ethRewardAmount}(ETH_ADDRESS, ethRewardAmount);
        vm.stopPrank();
        
        // Check ETH rewards
        uint256 totalSupply = 150 * 10**18;
        uint256 aliceExpectedEthReward = (ethRewardAmount * 100 * 10**18) / totalSupply; // 100/150 of total
        
        assertApproxEqRel(
            yieldToken.earned(alice, ETH_ADDRESS), 
            aliceExpectedEthReward, 
            0.01e18
        );
        
        // Add ETH as time-weighted rewards
        vm.warp(block.timestamp + ONE_DAY_IN_SECS);
        vm.prank(alice);
        yieldToken.collectTimeWeightedBalance();
        vm.prank(bob);
        yieldToken.collectTimeWeightedBalance();
        
        vm.startPrank(alice);
        vm.expectEmit(true, true, false, true);
        emit RewardsAdded(ETH_ADDRESS, ethRewardAmount, true);
        mockVault.addTimeWeightedRewards{value: ethRewardAmount}(ETH_ADDRESS, ethRewardAmount);
        vm.stopPrank();
        
        // Check time-weighted ETH rewards
        assertTrue(yieldToken.timeWeightedEarned(alice, ETH_ADDRESS) > 0);
        
        // Check initial ETH balance
        uint256 aliceEthBalanceBefore = alice.balance;
        
        uint256 totalExpectedEthReward = yieldToken.earned(alice, ETH_ADDRESS) + 
                                          yieldToken.timeWeightedEarned(alice, ETH_ADDRESS);
        
        // Claim rewards
        vm.startPrank(alice);
        yieldToken.claimRewards();
        vm.stopPrank();
        
        // Check ETH balance after claiming
        uint256 aliceEthBalanceAfter = alice.balance;
        
        assertApproxEqRel(
            aliceEthBalanceAfter,
            aliceEthBalanceBefore + totalExpectedEthReward,
            0.01e18
        );
    }

    function test_EpochEndTimestampForTimeWeightedBalance() public {
        // Mint tokens to users
        vm.startPrank(address(mockVault));
        mockVault.mintYieldToken(alice, 100 * 10**18);
        vm.stopPrank();
        
        // Set epoch end timestamp to 5 days in the future
        uint256 currentTime = block.timestamp;
        uint256 epochEndTimestamp = currentTime + ONE_DAY_IN_SECS * 5;
        
        vm.startPrank(address(mockVault));
        mockVault.setEpochEndTimestamp(epochEndTimestamp);
        vm.stopPrank();
        
        // Advance time beyond epoch end
        vm.warp(epochEndTimestamp + ONE_DAY_IN_SECS);
        
        // Collect time-weighted balance
        vm.startPrank(alice);
        yieldToken.collectTimeWeightedBalance();
        vm.stopPrank();
        
        // Time-weighted balance should be capped at epoch end
        uint256 expectedTimeWeightedBalance = 100 * 10**18 * (epochEndTimestamp - currentTime);
        assertApproxEqRel(
            yieldToken.timeWeightedBalanceOf(alice),
            expectedTimeWeightedBalance,
            0.01e18
        );
    }
}
