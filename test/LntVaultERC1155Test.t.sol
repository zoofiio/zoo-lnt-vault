// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {MockERC20} from "./mocks/MockERC20.sol";
import {MockERC1155} from "./mocks/MockERC1155.sol";
import {WETH} from "./mocks/WETH.sol";
import {LntVaultERC1155} from "../src/vaults/LntVaultERC1155.sol";
import {LntVaultBase} from "../src/vaults/LntVaultBase.sol";
import {VestingToken} from "../src/tokens/VestingToken.sol";
import {LntMarketFactory} from "../src/market/LntMarketFactory.sol";
import {LntMarketRouter} from "../src/market/LntMarketRouter.sol";
import {LntContractFactory} from "../src/LntContractFactory.sol";
import {Constants} from "../src/libs/Constants.sol";
import {ILntVault} from "../src/interfaces/ILntVault.sol";

contract LntVaultERC1155Test is Test {
    uint256 constant ONE_DAY_IN_SECS = 86400;
    uint256 constant SETTINGS_DECIMALS = 10;
    address constant ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    // Events to match what's in the contracts
    event Initialized();
    event InitializedT(address indexed T);
    event UpdateParamValue(bytes32 indexed key, uint256 value);
    event UpdateVestingSchedule(uint256 indexed tokenId, uint256 weight, uint256 vestingTokenAmountPerNft, uint256 vestingStartTime, uint256 vestingDuration);
    event Deposit(uint256 indexed depositId, address indexed user, address indexed nft, uint256 tokenId, uint256 value);
    event Redeem(uint256 indexed depositId, address indexed user, address indexed nft, uint256 tokenId, uint256 value);
    event VTMinted(address indexed user, uint256 fees, uint256 netAmount);
    event VTBurned(address indexed user, uint256 amount);
    event RedeemT(address indexed user, uint256 amount);
    event Buyback(address indexed caller, uint256 amountT, uint256 amountVT);

    // Contracts
    MockERC1155 public nft;
    LntVaultERC1155 public lntVault;
    VestingToken public vt;
    LntMarketRouter public lntMarketRouter;
    LntContractFactory public lntContractFactory;
    LntMarketFactory public lntMarketFactory;
    WETH public weth;

    // User addresses
    address public alice = address(0x1);
    address public bob = address(0x2);
    address public caro = address(0x3);
    address public ivy = address(0x5);
    
    // Token IDs for testing
    uint256 public tokenId1 = 1;
    uint256 public tokenId2 = 2;
    uint256 public tokenId3 = 3;
    uint256 public tokenId4 = 4;
    
    // Helper function for calculating VT amount in tests
    function calcMintedVt(LntVaultBase vault, uint256 tokenId, uint256 value) public view returns (uint256 netVtAmount, uint256 fees) {
        // Get vesting schedules
        ILntVault.VestingSchedule[] memory vestingSchedules = vault.vestingSchedules();
        
        // Find the correct vesting schedule for the tokenId
        ILntVault.VestingSchedule memory vestingSchedule;
        for (uint256 i = 0; i < vestingSchedules.length; i++) {
            if (vestingSchedules[i].tokenId == tokenId) {
                vestingSchedule = vestingSchedules[i];
                break;
            }
        }
        
        uint256 nftVtAmountPerNft = vestingSchedule.vestingTokenAmountPerNft;
        uint256 nftVestingStartTime = vestingSchedule.vestingStartTime;
        uint256 nftVestingDuration = vestingSchedule.vestingDuration;
        uint256 f1 = vault.paramValue(bytes32("f1"));
        
        uint256 remainingTime = 0;
        uint256 currentTime = block.timestamp;
        if (currentTime < nftVestingStartTime + nftVestingDuration) {
            remainingTime = nftVestingStartTime + nftVestingDuration - currentTime;
        }
        // Use the min of remaining time and vesting duration
        remainingTime = remainingTime < nftVestingDuration ? remainingTime : nftVestingDuration;
        
        uint256 vtAmount = (nftVtAmountPerNft * value) * remainingTime / nftVestingDuration;
        fees = vtAmount * f1 / (10**SETTINGS_DECIMALS);
        netVtAmount = vtAmount - fees;
        
        return (netVtAmount, fees);
    }

    // Helper function for calculating burned VT amount in tests
    function calcBurnedVt(LntVaultBase vault, uint256 depositId, uint256 tokenId, uint256 value) public view returns (uint256 netVtAmount) {
        // Get vesting schedules
        ILntVault.VestingSchedule[] memory vestingSchedules = vault.vestingSchedules();
        
        // Find the correct vesting schedule for the tokenId
        ILntVault.VestingSchedule memory vestingSchedule;
        for (uint256 i = 0; i < vestingSchedules.length; i++) {
            if (vestingSchedules[i].tokenId == tokenId) {
                vestingSchedule = vestingSchedules[i];
                break;
            }
        }
        
        uint256 nftVtAmountPerNft = vestingSchedule.vestingTokenAmountPerNft;
        uint256 nftVestingStartTime = vestingSchedule.vestingStartTime;
        uint256 nftVestingDuration = vestingSchedule.vestingDuration;
        
        ILntVault.DepositInfo memory nftDepositInfo = vault.depositInfo(depositId);
        uint256 f1 = nftDepositInfo.f1OnDeposit;
        
        uint256 remainingTime = 0;
        uint256 currentTime = block.timestamp;
        if (currentTime < nftVestingStartTime + nftVestingDuration) {
            remainingTime = nftVestingStartTime + nftVestingDuration - currentTime;
        }
        // Use the min of remaining time and vesting duration
        remainingTime = remainingTime < nftVestingDuration ? remainingTime : nftVestingDuration;
        
        uint256 vtAmount = (nftVtAmountPerNft * value) * remainingTime / nftVestingDuration;
        uint256 fees = vtAmount * f1 / (10**SETTINGS_DECIMALS);
        netVtAmount = vtAmount - fees;
        
        return netVtAmount;
    }
    
    // Helper function to create vesting schedules for testing
    function createVestingSchedules(uint256 vestingStartTime, uint256 vestingDuration) public view returns (ILntVault.VestingSchedule[] memory) {
        ILntVault.VestingSchedule[] memory vestingSchedules = new ILntVault.VestingSchedule[](3);
        
        // Schedule for tokenId1
        vestingSchedules[0] = ILntVault.VestingSchedule({
            tokenId: tokenId1,
            weight: 1,
            vestingTokenAmountPerNft: 1000 * 10**18, // 1000 $VT per NFT
            vestingStartTime: vestingStartTime,
            vestingDuration: vestingDuration
        });
        
        // Schedule for tokenId2
        vestingSchedules[1] = ILntVault.VestingSchedule({
            tokenId: tokenId2,
            weight: 2,
            vestingTokenAmountPerNft: 1500 * 10**18, // 1500 $VT per NFT
            vestingStartTime: vestingStartTime,
            vestingDuration: vestingDuration
        });
        
        // Schedule for tokenId3
        vestingSchedules[2] = ILntVault.VestingSchedule({
            tokenId: tokenId3,
            weight: 3,
            vestingTokenAmountPerNft: 2000 * 10**18, // 2000 $VT per NFT
            vestingStartTime: vestingStartTime,
            vestingDuration: vestingDuration
        });
        
        return vestingSchedules;
    }

    function setUp() public {
        // Setup users with ETH
        vm.deal(alice, 10000 ether);
        vm.deal(bob, 10000 ether);
        vm.deal(caro, 10000 ether);

        // Deploy contracts
        weth = new WETH();
        
        // Setup contract factory structure
        lntContractFactory = new LntContractFactory(ivy);
        lntMarketFactory = new LntMarketFactory();
        lntMarketRouter = new LntMarketRouter(address(lntMarketFactory), address(weth));
        
        // Make sure the vault is created with the factory as its owner
        vm.startPrank(address(lntContractFactory));
        lntVault = new LntVaultERC1155(bob);
        vt = new VestingToken(address(lntVault), "LNT VT", "LNTVT");
        vm.stopPrank();
        
        vm.startPrank(bob);

        nft = new MockERC1155();
        nft.mint(alice, tokenId1, 10, "");
        nft.mint(alice, tokenId2, 20, "");
        nft.mint(alice, tokenId3, 30, "");
        nft.mint(bob, tokenId1, 15, "");
        nft.mint(bob, tokenId2, 25, "");
        nft.mint(bob, tokenId3, 35, "");
        nft.mint(caro, tokenId1, 5, "");
        nft.mint(caro, tokenId2, 10, "");
        nft.mint(caro, tokenId3, 15, "");

        vm.stopPrank();
    }

    function test_LntVaultERC1155DepositAndRedeem() public {
        // Check initial state
        assertEq(lntVault.initialized(), false, "Vault should not be initialized");
        assertEq(lntVault.owner(), bob, "Bob should be the owner");

        // Update settings - Alice tries (should fail)
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        lntVault.updateParamValue(bytes32("f1"), 10**9);
        vm.stopPrank();

        // Update settings - Bob succeeds
        vm.startPrank(bob);
        vm.expectEmit(true, true, true, true);
        emit UpdateParamValue(bytes32("f1"), 10**9);
        lntVault.updateParamValue(bytes32("f1"), 10**9);
        vm.stopPrank();

        // Cannot deposit before initialization
        vm.startPrank(alice);
        vm.expectRevert("Not initialized");
        lntVault.deposit(tokenId1, 5);
        vm.stopPrank();

        uint256 genesisTime = block.timestamp;
        uint256 vestingStartTime = genesisTime + ONE_DAY_IN_SECS;
        uint256 vestingDuration = 100 * ONE_DAY_IN_SECS;   // [Day 1, Day 101]
        
        ILntVault.VestingSchedule[] memory vestingSchedules = createVestingSchedules(
            vestingStartTime, 
            vestingDuration
        );
        
        // Only owner could initialize - Alice tries (should fail)
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        lntVault.initialize(
            address(nft), address(lntMarketRouter), address(vt), vestingSchedules
        );
        vm.stopPrank();

        // Bob initializes
        vm.startPrank(bob);
        vm.expectEmit(true, true, true, true);
        emit Initialized();
        lntVault.initialize(
            address(nft), address(lntMarketRouter), address(vt), vestingSchedules
        );
        vm.stopPrank();

        // Could not initialize again
        assertEq(lntVault.initialized(), true);
        assertEq(lntVault.NFT(), address(nft));
        vm.startPrank(bob);
        vm.expectRevert("Already initialized");
        lntVault.initialize(
            address(nft), address(lntMarketRouter), address(vt), vestingSchedules
        );
        vm.stopPrank();

        /**
         * Day 0:
         *  Alice deposits tokenId1 (5 units) and tokenId2 (10 units)
         *  Bob deposits tokenId1 (3 units)
         */
        
        // Alice tries to deposit more than owned
        vm.startPrank(alice);
        vm.expectRevert("Insufficient balance");
        lntVault.deposit(tokenId1, 50);
        
        // Alice approves and deposits tokenId1
        nft.setApprovalForAll(address(lntVault), true);
        
        // Prepare VM to handle the NFT transfer and minting
        vm.mockCall(
            address(lntContractFactory),
            abi.encodeWithSignature("treasury()"),
            abi.encode(ivy)
        );
        
        // Check NFT balance before
        assertEq(nft.balanceOf(alice, tokenId1), 10);
        
        // Calculate expected VT amounts for proper verification
        (uint256 expectedNetVtAmount, uint256 expectedFees) = calcMintedVt(lntVault, tokenId1, 5);
        
        // Expect Deposit and VTMinted events with calculated values
        vm.expectEmit(true, true, true, true);
        emit VTMinted(alice, expectedFees, expectedNetVtAmount);
        vm.expectEmit(true, true, true, true);
        emit Deposit(1, alice, address(nft), tokenId1, 5);
        
        // Deposit 5 of tokenId1
        lntVault.deposit(tokenId1, 5);
        
        // Check NFT balance after
        assertEq(nft.balanceOf(alice, tokenId1), 5);
        assertEq(nft.balanceOf(address(lntVault), tokenId1), 5);
        
        // Deposit 10 of tokenId2
        (expectedNetVtAmount, expectedFees) = calcMintedVt(lntVault, tokenId2, 10);
        vm.expectEmit(true, true, true, true);
        emit VTMinted(alice, expectedFees, expectedNetVtAmount);
        vm.expectEmit(true, true, true, true);
        emit Deposit(2, alice, address(nft), tokenId2, 10);
        lntVault.deposit(tokenId2, 10);
        
        // Check NFT balance after
        assertEq(nft.balanceOf(alice, tokenId2), 10);
        assertEq(nft.balanceOf(address(lntVault), tokenId2), 10);
        vm.stopPrank();
        
        // Bob deposits tokenId1
        vm.startPrank(bob);
        nft.setApprovalForAll(address(lntVault), true);
        lntVault.deposit(tokenId1, 3);
        vm.stopPrank();

        // Day 2: Alice redeems tokenId2
        vm.warp(genesisTime + ONE_DAY_IN_SECS * 2);
        uint256 depositId = 2;
        
        // Verify deposit info
        ILntVault.DepositInfo memory info = lntVault.depositInfo(depositId);
        assertEq(info.tokenId, tokenId2);
        assertEq(info.value, 10);
        
        // Bob tries to redeem Alice's deposit
        vm.startPrank(bob);
        vm.expectRevert("Not user of deposit");
        lntVault.redeem(depositId, tokenId2, 10);
        vm.stopPrank();
        
        // Alice tries to redeem more than deposited
        vm.startPrank(alice);
        vm.expectRevert("Invalid value");
        lntVault.redeem(depositId, tokenId2, 20);
        
        // Calculate expected burned VT amount
        uint256 expectedBurnedVtAmount = calcBurnedVt(lntVault, depositId, tokenId2, 10);
        
        // Expect Redeem and VTBurned events with calculated values
        vm.expectEmit(true, true, true, true);
        emit VTBurned(alice, expectedBurnedVtAmount);
        vm.expectEmit(true, true, true, true);
        emit Redeem(depositId, alice, address(nft), tokenId2, 10);
        
        // Alice redeems all of tokenId2
        lntVault.redeem(depositId, tokenId2, 10);
        
        // Check NFT balance after
        assertEq(nft.balanceOf(alice, tokenId2), 20); // Original 10 + 10 redeemed
        assertEq(nft.balanceOf(address(lntVault), tokenId2), 0);
        
        // Verify deposit is marked as redeemed
        info = lntVault.depositInfo(depositId);
        assertTrue(info.redeemed);
        
        // Try to redeem again
        vm.expectRevert("Already redeemed");
        lntVault.redeem(depositId, tokenId2, 10);
        vm.stopPrank();
    }

    function test_LntVaultERC1155RedeemETH() public {
        // Setup - deploy contracts and initialize
        uint256 genesisTime = block.timestamp;
        uint256 vestingStartTime = genesisTime + ONE_DAY_IN_SECS;
        uint256 vestingDuration = 100 * ONE_DAY_IN_SECS;   // [Day 1, Day 101]
        
        // Create vesting schedules for the tokens we'll use
        ILntVault.VestingSchedule[] memory vestingSchedules = new ILntVault.VestingSchedule[](2);
        
        // Schedule for tokenId1
        vestingSchedules[0] = ILntVault.VestingSchedule({
            tokenId: tokenId1,
            weight: 1,
            vestingTokenAmountPerNft: 1000 * 10**18, // 1000 $VT per NFT unit
            vestingStartTime: vestingStartTime,
            vestingDuration: vestingDuration
        });
        
        // Schedule for tokenId2
        vestingSchedules[1] = ILntVault.VestingSchedule({
            tokenId: tokenId2,
            weight: 1,
            vestingTokenAmountPerNft: 1000 * 10**18, // 1000 $VT per NFT unit
            vestingStartTime: vestingStartTime,
            vestingDuration: vestingDuration
        });
        
        // Initialize vault
        vm.startPrank(bob);
        lntVault.initialize(
            address(nft), address(lntMarketRouter), address(vt), vestingSchedules
        );
        vm.stopPrank();
        
        // Alice and Bob deposit NFTs
        vm.startPrank(alice);
        nft.setApprovalForAll(address(lntVault), true);
        lntVault.deposit(tokenId1, 5); // Deposit 5 units of tokenId1
        vm.stopPrank();
        
        vm.startPrank(bob);
        nft.setApprovalForAll(address(lntVault), true);
        lntVault.deposit(tokenId2, 5); // Deposit 5 units of tokenId2
        vm.stopPrank();
        
        // Try to redeem T before initialization (should fail)
        vm.startPrank(alice);
        vm.expectRevert("Not initialized T");
        lntVault.redeemT(1);
        vm.stopPrank();
        
        // Initialize T with ETH address
        vm.startPrank(bob);
        vm.expectEmit(true, true, true, true);
        emit InitializedT(ETH_ADDRESS);
        lntVault.initializeT(ETH_ADDRESS);
        
        // Verify initialized correctly
        assertEq(lntVault.initializedT(), true);
        assertEq(lntVault.T(), ETH_ADDRESS);
        
        // Try to initialize T again (should fail)
        vm.expectRevert("Already initialized");
        lntVault.initializeT(ETH_ADDRESS);
        vm.stopPrank();
        
        // Try to redeem T before vesting ends (should fail)
        vm.startPrank(alice);
        vm.expectRevert("Vesting not ended");
        lntVault.redeemT(1);
        
        // Warp time to after vesting period (Day 102)
        vm.warp(genesisTime + ONE_DAY_IN_SECS * 102);
        
        // Set redeemAmount based on calculation: 5 units * 1000 VT per unit * half = 2500
        uint256 redeemAmount = 2500 * 10**18;
        
        // Try to redeem without sufficient balance in vault
        vm.expectRevert("Insufficient token balance");
        lntVault.redeemT(redeemAmount);
        vm.stopPrank();
        
        // Bob sends ETH to the vault for redemption tests
        vm.startPrank(bob);
        (bool success, ) = address(lntVault).call{value: 5000 ether}("");
        require(success, "ETH transfer failed");
        vm.stopPrank();
        
        // Now Alice can redeem
        vm.startPrank(alice);
        // Approve the vault to spend VT tokens
        vt.approve(address(lntVault), redeemAmount);
        
        // Check balances before redemption
        uint256 aliceVtBalance = vt.balanceOf(alice);
        uint256 aliceEthBefore = alice.balance;
        uint256 vaultEthBefore = address(lntVault).balance;
        
        // Expect RedeemT event
        vm.expectEmit(true, false, false, true);
        emit RedeemT(alice, redeemAmount);
        
        // Now redeem should succeed
        lntVault.redeemT(redeemAmount);
        
        // Verify balances after redemption
        assertEq(vt.balanceOf(alice), aliceVtBalance - redeemAmount, "Alice's VT balance should decrease");
        assertEq(alice.balance, aliceEthBefore + redeemAmount, "Alice's ETH balance should increase");
        assertEq(address(lntVault).balance, vaultEthBefore - redeemAmount, "Vault's ETH balance should decrease");
        
        vm.stopPrank();
    }

    function test_LntVaultERC1155RedeemERC20() public {
        // Setup - deploy contracts and initialize
        uint256 genesisTime = block.timestamp;
        uint256 vestingStartTime = genesisTime + ONE_DAY_IN_SECS;
        uint256 vestingDuration = 100 * ONE_DAY_IN_SECS;   // [Day 1, Day 101]
        
        // Create vesting schedules for the tokens we'll use
        ILntVault.VestingSchedule[] memory vestingSchedules = new ILntVault.VestingSchedule[](2);
        
        // Schedule for tokenId1 and tokenId2
        vestingSchedules[0] = ILntVault.VestingSchedule({
            tokenId: tokenId1,
            weight: 1,
            vestingTokenAmountPerNft: 1000 * 10**18,
            vestingStartTime: vestingStartTime,
            vestingDuration: vestingDuration
        });
        
        vestingSchedules[1] = ILntVault.VestingSchedule({
            tokenId: tokenId2,
            weight: 2,
            vestingTokenAmountPerNft: 1000 * 10**18,
            vestingStartTime: vestingStartTime,
            vestingDuration: vestingDuration
        });
        
        // Deploy a mock ERC20 token
        vm.startPrank(bob);
        MockERC20 mockToken = new MockERC20("Mock Token", "MT", 18);
        
        // Initialize vault
        lntVault.initialize(
            address(nft), address(lntMarketRouter), address(vt), vestingSchedules
        );
        
        // Initialize T with the mock token address
        vm.expectEmit(true, true, true, true);
        emit InitializedT(address(mockToken));
        lntVault.initializeT(address(mockToken));
        
        // Verify initialized correctly
        assertEq(lntVault.initializedT(), true);
        assertEq(lntVault.T(), address(mockToken));
        
        // Mint tokens to vault for redemption
        mockToken.mint(address(lntVault), 5000 * 10**18);
        vm.stopPrank();
        
        // Alice and Bob deposit NFTs
        vm.startPrank(alice);
        nft.setApprovalForAll(address(lntVault), true);
        lntVault.deposit(tokenId1, 5); // Deposit 5 units of tokenId1
        vm.stopPrank();
        
        vm.startPrank(bob);
        nft.setApprovalForAll(address(lntVault), true);
        lntVault.deposit(tokenId2, 5); // Deposit 5 units of tokenId2
        vm.stopPrank();
        
        // Try to redeem before vesting ends
        vm.startPrank(alice);
        vm.expectRevert("Vesting not ended");
        lntVault.redeemT(1);
        
        // Warp time to after vesting period (Day 102)
        vm.warp(genesisTime + ONE_DAY_IN_SECS * 102);
        
        // Set redeemAmount to 2500 tokens (5 units * 1000 tokens * 0.5)
        uint256 redeemAmount = 2500 * 10**18;
        
        // Approve vault to spend VT tokens
        vt.approve(address(lntVault), redeemAmount);
        
        // Check balances before redemption
        uint256 aliceVtBalance = vt.balanceOf(alice);
        uint256 aliceTokenBefore = mockToken.balanceOf(alice);
        uint256 vaultTokenBefore = mockToken.balanceOf(address(lntVault));
        
        // Expect RedeemT event
        vm.expectEmit(true, false, false, true);
        emit RedeemT(alice, redeemAmount);
        
        // Now redeem should succeed
        lntVault.redeemT(redeemAmount);
        
        // Verify balances after redemption
        assertEq(vt.balanceOf(alice), aliceVtBalance - redeemAmount, "Alice's VT balance should decrease");
        assertEq(mockToken.balanceOf(alice), aliceTokenBefore + redeemAmount, "Alice's token balance should increase");
        assertEq(mockToken.balanceOf(address(lntVault)), vaultTokenBefore - redeemAmount, "Vault's token balance should decrease");
        
        vm.stopPrank();
    }

    function test_LntVaultERC1155BuybackWithETH() public {
        // Setup - deploy contracts and initialize
        uint256 genesisTime = block.timestamp;
        uint256 vestingStartTime = genesisTime + ONE_DAY_IN_SECS;
        uint256 vestingDuration = 100 * ONE_DAY_IN_SECS;   // [Day 1, Day 101]
        
        // Create vesting schedules for the tokens we'll use
        ILntVault.VestingSchedule[] memory vestingSchedules = new ILntVault.VestingSchedule[](2);
        
        vestingSchedules[0] = ILntVault.VestingSchedule({
            tokenId: tokenId1,
            weight: 1,
            vestingTokenAmountPerNft: 1000 * 10**18,
            vestingStartTime: vestingStartTime,
            vestingDuration: vestingDuration
        });
        
        vestingSchedules[1] = ILntVault.VestingSchedule({
            tokenId: tokenId2,
            weight: 2,
            vestingTokenAmountPerNft: 1000 * 10**18,
            vestingStartTime: vestingStartTime,
            vestingDuration: vestingDuration
        });
        
        // Initialize vault
        vm.startPrank(bob);
        lntVault.initialize(
            address(nft), address(lntMarketRouter), address(vt), vestingSchedules
        );
        
        // Initialize T with ETH address
        vm.expectEmit(true, true, true, true);
        emit InitializedT(ETH_ADDRESS);
        lntVault.initializeT(ETH_ADDRESS);
        vm.stopPrank();
        
        // Setup NFT deposits to get VT tokens
        vm.startPrank(alice);
        nft.setApprovalForAll(address(lntVault), true);
        lntVault.deposit(tokenId1, 5);
        vm.stopPrank();
        
        vm.startPrank(bob);
        nft.setApprovalForAll(address(lntVault), true);
        lntVault.deposit(tokenId2, 5);
        vm.stopPrank();
        
        // Create liquidity pool for VT/ETH
        vm.startPrank(alice);
        uint256 liquidityVTAmount = 1000 * 10**18; // 1000 VT
        uint256 liquidityETHAmount = 800 * 10**18; // 800 ETH
        
        vt.approve(address(lntMarketRouter), liquidityVTAmount);
        
        lntMarketRouter.addLiquidityETH{value: liquidityETHAmount}(
            address(vt),
            liquidityVTAmount,
            0, // min token
            0, // min ETH
            alice,
            block.timestamp + 60
        );
        vm.stopPrank();
        
        // Warp to after vesting period (Day 102)
        vm.warp(genesisTime + ONE_DAY_IN_SECS * 102);
        
        // Bob transfers ETH to vault for buyback
        vm.startPrank(bob);
        (bool success, ) = address(lntVault).call{value: 1000 ether}("");
        require(success, "ETH transfer failed");
        
        // Try to buyback too much (should fail)
        uint256 excessBuybackAmount = 2000 * 10**18;
        vm.expectRevert("Insufficient token balance");
        lntVault.buyback(excessBuybackAmount, 0);
        
        // Normal buyback amount
        uint256 buybackAmount = 500 * 10**18;
        
        // Try with high slippage protection (should fail)
        vm.expectRevert("LntMarketRouter: INSUFFICIENT_OUTPUT_AMOUNT");
        lntVault.buyback(buybackAmount, 1000 * 10**18); // Expecting too many VT tokens
        
        // Check ETH balance before buyback
        uint256 vaultEthBefore = address(lntVault).balance;
        
        // Only check the first two parameters of the event (caller and amount)
        vm.expectEmit(true, true, false, false);
        emit Buyback(bob, buybackAmount, 0); // The third parameter (amountVT) is not checked
        
        // Execute buyback with reasonable slippage protection
        lntVault.buyback(buybackAmount, 250 * 10**18);
        
        // Verify ETH balance decreased
        assertEq(address(lntVault).balance, vaultEthBefore - buybackAmount, "Vault's ETH balance should decrease");
        
        vm.stopPrank();
    }

    function test_LntVaultERC1155BuybackWithERC20() public {
        // Setup - deploy contracts and initialize
        uint256 genesisTime = block.timestamp;
        uint256 vestingStartTime = genesisTime + ONE_DAY_IN_SECS;
        uint256 vestingDuration = 100 * ONE_DAY_IN_SECS;   // [Day 1, Day 101]
        
        // Create vesting schedules for the tokens we'll use
        ILntVault.VestingSchedule[] memory vestingSchedules = new ILntVault.VestingSchedule[](2);
        
        vestingSchedules[0] = ILntVault.VestingSchedule({
            tokenId: tokenId1,
            weight: 1,
            vestingTokenAmountPerNft: 1000 * 10**18,
            vestingStartTime: vestingStartTime,
            vestingDuration: vestingDuration
        });
        
        vestingSchedules[1] = ILntVault.VestingSchedule({
            tokenId: tokenId2,
            weight: 2,
            vestingTokenAmountPerNft: 1000 * 10**18,
            vestingStartTime: vestingStartTime,
            vestingDuration: vestingDuration
        });
        
        // Deploy a mock ERC20 token and mint tokens
        vm.startPrank(bob);
        MockERC20 mockToken = new MockERC20("Mock Token", "MT", 18);
        
        // Mint tokens to Alice for liquidity and to vault for buyback
        mockToken.mint(alice, 10000 * 10**18);
        mockToken.mint(bob, 10000 * 10**18);
        
        // Initialize vault
        lntVault.initialize(
            address(nft), address(lntMarketRouter), address(vt), vestingSchedules
        );
        
        // Initialize T with ERC20 token address
        vm.expectEmit(true, true, true, true);
        emit InitializedT(address(mockToken));
        lntVault.initializeT(address(mockToken));
        
        // Transfer tokens to vault for buyback
        mockToken.transfer(address(lntVault), 1000 * 10**18);
        vm.stopPrank();
        
        // Setup NFT deposits to get VT tokens
        vm.startPrank(alice);
        nft.setApprovalForAll(address(lntVault), true);
        lntVault.deposit(tokenId1, 5);
        vm.stopPrank();
        
        vm.startPrank(bob);
        nft.setApprovalForAll(address(lntVault), true);
        lntVault.deposit(tokenId2, 5);
        vm.stopPrank();
        
        // Create liquidity pool for VT/ERC20
        vm.startPrank(alice);
        uint256 liquidityVTAmount = 3000 * 10**18; // 3000 VT
        uint256 liquidityTokenAmount = 2000 * 10**18; // 2000 tokens
        
        vt.approve(address(lntMarketRouter), liquidityVTAmount);
        mockToken.approve(address(lntMarketRouter), liquidityTokenAmount);
        
        lntMarketRouter.addLiquidity(
            address(vt),
            address(mockToken),
            liquidityVTAmount,
            liquidityTokenAmount,
            0, // min VT
            0, // min token
            alice,
            block.timestamp + 60
        );
        vm.stopPrank();
        
        // Warp to after vesting period (Day 102)
        vm.warp(genesisTime + ONE_DAY_IN_SECS * 102);
        
        // Bob executes buyback
        vm.startPrank(bob);
        
        // Try to buyback too much (should fail)
        uint256 excessBuybackAmount = 2000 * 10**18;
        vm.expectRevert("Insufficient token balance");
        lntVault.buyback(excessBuybackAmount, 0);
        
        // Normal buyback amount
        uint256 buybackAmount = 500 * 10**18;
        
        // Try with high slippage protection (should fail)
        vm.expectRevert("LntMarketRouter: INSUFFICIENT_OUTPUT_AMOUNT");
        lntVault.buyback(buybackAmount, 1000 * 10**18); // Expecting too many VT tokens
        
        // Check token balance before buyback
        uint256 vaultTokenBefore = mockToken.balanceOf(address(lntVault));
        
        // Only check the first two parameters of the event (caller and amount)
        vm.expectEmit(true, true, false, false);
        emit Buyback(bob, buybackAmount, 0); // The third parameter (amountVT) is not checked
        
        // Execute buyback with reasonable slippage protection
        lntVault.buyback(buybackAmount, 250 * 10**18);
        
        // Verify token balance decreased
        assertEq(mockToken.balanceOf(address(lntVault)), vaultTokenBefore - buybackAmount, "Vault's token balance should decrease");
        
        vm.stopPrank();
    }

    function test_LntVaultERC1155MultipleUsersTokensAndAmounts() public {
        // Setup - deploy contracts and initialize
        uint256 genesisTime = block.timestamp;
        uint256 vestingStartTime = genesisTime + ONE_DAY_IN_SECS;
        uint256 vestingDuration = 100 * ONE_DAY_IN_SECS;   // [Day 1, Day 101]
        
        // Create vesting schedules for the tokens we'll use
        ILntVault.VestingSchedule[] memory vestingSchedules = new ILntVault.VestingSchedule[](3);
        
        vestingSchedules[0] = ILntVault.VestingSchedule({
            tokenId: tokenId1,
            weight: 1,
            vestingTokenAmountPerNft: 1000 * 10**18,
            vestingStartTime: vestingStartTime,
            vestingDuration: vestingDuration
        });
        
        vestingSchedules[1] = ILntVault.VestingSchedule({
            tokenId: tokenId2,
            weight: 2,
            vestingTokenAmountPerNft: 1000 * 10**18,
            vestingStartTime: vestingStartTime,
            vestingDuration: vestingDuration
        });
        
        vestingSchedules[2] = ILntVault.VestingSchedule({
            tokenId: tokenId3,
            weight: 3,
            vestingTokenAmountPerNft: 1000 * 10**18,
            vestingStartTime: vestingStartTime,
            vestingDuration: vestingDuration
        });
        
        // Initialize vault
        vm.startPrank(bob);
        lntVault.initialize(
            address(nft), address(lntMarketRouter), address(vt), vestingSchedules
        );
        vm.stopPrank();
        
        // All users approve vault for transfers
        vm.startPrank(alice);
        nft.setApprovalForAll(address(lntVault), true);
        vm.stopPrank();
        
        vm.startPrank(bob);
        nft.setApprovalForAll(address(lntVault), true);
        vm.stopPrank();
        
        vm.startPrank(caro);
        nft.setApprovalForAll(address(lntVault), true);
        vm.stopPrank();
        
        // Each user deposits different token IDs with different amounts
        vm.prank(alice);
        uint256 aliceDeposit1 = lntVault.deposit(tokenId1, 5);
        
        vm.prank(alice);
        uint256 aliceDeposit2 = lntVault.deposit(tokenId2, 10);
        
        vm.prank(bob);
        uint256 bobDeposit1 = lntVault.deposit(tokenId1, 8);
        
        vm.prank(bob);
        uint256 bobDeposit2 = lntVault.deposit(tokenId3, 15);
        
        vm.prank(caro);
        uint256 caroDeposit1 = lntVault.deposit(tokenId1, 3);
        
        vm.prank(caro);
        uint256 caroDeposit2 = lntVault.deposit(tokenId3, 7);
        
        // Check balances after deposits
        assertEq(nft.balanceOf(alice, tokenId1), 10 - 5, "Alice should have 5 tokenId1 left");
        assertEq(nft.balanceOf(alice, tokenId2), 20 - 10, "Alice should have 10 tokenId2 left");
        assertEq(nft.balanceOf(bob, tokenId1), 15 - 8, "Bob should have 7 tokenId1 left");
        assertEq(nft.balanceOf(bob, tokenId3), 35 - 15, "Bob should have 20 tokenId3 left");
        assertEq(nft.balanceOf(caro, tokenId1), 5 - 3, "Caro should have 2 tokenId1 left");
        assertEq(nft.balanceOf(caro, tokenId3), 15 - 7, "Caro should have 8 tokenId3 left");
        
        // Check vault balances
        assertEq(nft.balanceOf(address(lntVault), tokenId1), 5 + 8 + 3, "Vault should have all tokenId1 deposits");
        assertEq(nft.balanceOf(address(lntVault), tokenId2), 10, "Vault should have all tokenId2 deposits");
        assertEq(nft.balanceOf(address(lntVault), tokenId3), 15 + 7, "Vault should have all tokenId3 deposits");
        
        // Move forward in time to allow redemptions
        vm.warp(genesisTime + ONE_DAY_IN_SECS * 10);
        
        // Users redeem their tokens
        vm.prank(alice);
        lntVault.redeem(1, tokenId1, 5);
        
        vm.prank(bob);
        lntVault.redeem(3, tokenId1, 8);
        
        vm.prank(caro);
        lntVault.redeem(5, tokenId1, 3);
        
        // Check balances after redemptions
        assertEq(nft.balanceOf(alice, tokenId1), 5 + 5, "Alice should have received her 5 tokenId1 back");
        assertEq(nft.balanceOf(bob, tokenId1), 7 + 8, "Bob should have received his 8 tokenId1 back");
        assertEq(nft.balanceOf(caro, tokenId1), 2 + 3, "Caro should have received her 3 tokenId1 back");
        
        // Verify vault has no tokenId1 left
        assertEq(nft.balanceOf(address(lntVault), tokenId1), 0, "Vault should have no tokenId1 left");
        
        // Verify other tokens remain in the vault
        assertEq(nft.balanceOf(address(lntVault), tokenId2), 10, "Vault should still have tokenId2");
        assertEq(nft.balanceOf(address(lntVault), tokenId3), 15 + 7, "Vault should still have tokenId3");
        
        // Verify redemption state
        ILntVault.DepositInfo memory info1 = lntVault.depositInfo(1);
        ILntVault.DepositInfo memory info3 = lntVault.depositInfo(3);
        ILntVault.DepositInfo memory info5 = lntVault.depositInfo(5);
        
        assertTrue(info1.redeemed, "Alice's tokenId1 deposit should be marked as redeemed");
        assertTrue(info3.redeemed, "Bob's tokenId1 deposit should be marked as redeemed");
        assertTrue(info5.redeemed, "Caro's tokenId1 deposit should be marked as redeemed");
    }
}
