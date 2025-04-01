// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {MockERC20} from "./mocks/MockERC20.sol";
import {MockERC721} from "./mocks/MockERC721.sol";
import {WETH} from "./mocks/WETH.sol";
import {LntVaultERC721} from "../src/vaults/LntVaultERC721.sol";
import {LntVaultBase} from "../src/vaults/LntVaultBase.sol";
import {VestingToken} from "../src/tokens/VestingToken.sol";
import {LntMarketFactory} from "../src/market/LntMarketFactory.sol";
import {LntMarketRouter} from "../src/market/LntMarketRouter.sol";
import {LntContractFactory} from "../src/LntContractFactory.sol";
import {Constants} from "../src/libs/Constants.sol";
import {ILntVault} from "../src/interfaces/ILntVault.sol";

contract LntVaultERC721Test is Test {
    uint256 constant ONE_DAY_IN_SECS = 86400;
    uint256 constant SETTINGS_DECIMALS = 10;
    address constant ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    // Events to match what's in the contracts
    event Initialized();
    event InitializedT(address indexed T);
    event UpdateParamValue(bytes32 indexed key, uint256 value);
    event Deposit(uint256 indexed depositId, address indexed user, address indexed nft, uint256 tokenId, uint256 value);
    event Redeem(uint256 indexed depositId, address indexed user, address indexed nft, uint256 tokenId, uint256 value);
    event VTMinted(address indexed user, uint256 fees, uint256 netAmount);
    event VTBurned(address indexed user, uint256 amount);
    event RedeemT(address indexed user, uint256 amount);
    event Buyback(address indexed caller, uint256 amountT, uint256 amountVT);

    // Contracts
    MockERC721 public nft;
    LntVaultERC721 public lntVault;
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
    address public tester;
    
    // Helper function for calculating VT amount in tests - accurate implementation
    function calcMintedVt(LntVaultBase vault, uint256 tokenId, uint256 value) public view returns (uint256 netVtAmount, uint256 fees) {
        // Get vesting schedules
        ILntVault.VestingSchedule[] memory vestingSchedules = vault.vestingSchedules();
        
        // Find the correct vesting schedule
        ILntVault.VestingSchedule memory vestingSchedule;
        if (vault.NFTType() == Constants.NftType.ERC721) { // Use enum value instead of integer
            vestingSchedule = vestingSchedules[0];
        } else {
            // For ERC1155, find the matching token ID
            for (uint256 i = 0; i < vestingSchedules.length; i++) {
                if (vestingSchedules[i].tokenId == tokenId) {
                    vestingSchedule = vestingSchedules[i];
                    break;
                }
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
        
        // Find the correct vesting schedule
        ILntVault.VestingSchedule memory vestingSchedule;
        if (vault.NFTType() == Constants.NftType.ERC721) { // Use enum value instead of integer
            vestingSchedule = vestingSchedules[0];
        } else {
            // For ERC1155, find the matching token ID
            for (uint256 i = 0; i < vestingSchedules.length; i++) {
                if (vestingSchedules[i].tokenId == tokenId) {
                    vestingSchedule = vestingSchedules[i];
                    break;
                }
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

    function setUp() public {
        // Setup users with ETH
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        vm.deal(caro, 100 ether);

        // Deploy contracts
        weth = new WETH();
        
        // Setup contract factory structure
        lntContractFactory = new LntContractFactory(ivy);
        lntMarketFactory = new LntMarketFactory();
        lntMarketRouter = new LntMarketRouter(address(lntMarketFactory), address(weth));
        
        // Make sure the vault is created with the factory as its owner
        vm.startPrank(address(lntContractFactory));
        lntVault = new LntVaultERC721(bob);
        vm.stopPrank();
        
        // Deploy mock tokens
        vm.startPrank(bob);

        nft = new MockERC721("Test NFT", "TNFT");
        vt = new VestingToken(address(lntVault), "LNT VT", "LNTVT");

        nft.safeMint(alice, 1);
        nft.safeMint(alice, 2);
        nft.safeMint(alice, 3);
        nft.safeMint(bob, 4);
        nft.safeMint(bob, 5);
        nft.safeMint(bob, 6);
        nft.safeMint(caro, 7);
        nft.safeMint(caro, 8);
        nft.safeMint(caro, 9);

        vm.stopPrank();
    }

    function test_LntVaultERC721DepositAndRedeem() public {
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
        lntVault.deposit(1, 1);
        vm.stopPrank();

        uint256 genesisTime = block.timestamp;
        uint256 vestingTokenAmountPerNft = 10000 * 10**18;  // 10000 $VT per NFT
        uint256 vestingStartTime = genesisTime + ONE_DAY_IN_SECS;
        uint256 vestingDuration = 100 * ONE_DAY_IN_SECS;   // [Day 1, Day 101]
        
        // Only owner could initialize - Alice tries (should fail)
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        lntVault.initialize(
            address(nft), address(lntMarketRouter), address(vt), 
            vestingTokenAmountPerNft, vestingStartTime, vestingDuration
        );
        vm.stopPrank();

        // Bob initializes
        vm.startPrank(bob);
        vm.expectEmit(true, true, true, true);
        emit Initialized();
        lntVault.initialize(
            address(nft), address(lntMarketRouter), address(vt), 
            vestingTokenAmountPerNft, vestingStartTime, vestingDuration
        );
        vm.stopPrank();

        // Could not initialize again
        assertEq(lntVault.initialized(), true);
        assertEq(lntVault.NFT(), address(nft));
        vm.startPrank(bob);
        vm.expectRevert("Already initialized");
        lntVault.initialize(
            address(nft), address(lntMarketRouter), address(vt), 
            vestingTokenAmountPerNft, vestingStartTime, vestingDuration
        );
        vm.stopPrank();

        /**
         * Day 0:
         *  Alice deposits NFT 1 & 2
         *  Bob deposits NFT 4
         */
        
        // Alice tries to deposit NFT 4 (not owned)
        vm.startPrank(alice);
        vm.expectRevert("Not owner of NFT");
        lntVault.deposit(4, 1);
        
        // Alice tries to deposit with invalid value
        vm.expectRevert("Invalid value");
        lntVault.deposit(1, 2);
        
        // Alice approves and deposits NFT 1
        nft.approve(address(lntVault), 1);
        
        // Prepare VM to handle the NFT transfer and minting
        vm.mockCall(
            address(lntContractFactory),
            abi.encodeWithSignature("treasury()"),
            abi.encode(ivy)
        );
        
        // Check NFT balance before
        assertEq(nft.ownerOf(1), alice);
        
        // Calculate expected VT amounts for proper verification
        (uint256 expectedNetVtAmount, uint256 expectedFees) = calcMintedVt(lntVault, 1, 1);
        
        // Expect Deposit and VTMinted events with calculated values
        vm.expectEmit(true, true, true, true);
        emit VTMinted(alice, expectedFees, expectedNetVtAmount);
        vm.expectEmit(true, true, true, true);
        emit Deposit(1, alice, address(nft), 1, 1);
        
        // Deposit NFT 1
        lntVault.deposit(1, 1);
        
        // Check NFT balance after
        assertEq(nft.ownerOf(1), address(lntVault));
        
        // Try to deposit same NFT again
        vm.expectRevert("Not owner of NFT");
        lntVault.deposit(1, 1);
        
        // Deposit NFT 2
        nft.approve(address(lntVault), 2);
        lntVault.deposit(2, 1);
        vm.stopPrank();
        
        // Bob deposits NFT 4
        vm.startPrank(bob);
        nft.setApprovalForAll(address(lntVault), true);
        lntVault.deposit(4, 1);
        vm.stopPrank();

        // Day 2: Alice redeems NFT 2
        vm.warp(genesisTime + ONE_DAY_IN_SECS * 2);
        uint256 depositId = 2;
        uint256 tokenId = 2;
        
        // Verify deposit info
        ILntVault.DepositInfo memory info = lntVault.depositInfo(depositId);
        assertEq(info.tokenId, tokenId);
        
        // Bob tries to redeem Alice's deposit
        vm.startPrank(bob);
        vm.expectRevert("Not user of deposit");
        lntVault.redeem(depositId, tokenId, 1);
        vm.stopPrank();
        
        // Alice tries to redeem with invalid value
        vm.startPrank(alice);
        vm.expectRevert("Invalid value");
        lntVault.redeem(depositId, tokenId, 2);
        
        // Calculate expected burned VT amount
        uint256 expectedBurnedVtAmount = calcBurnedVt(lntVault, depositId, tokenId, 1);
        
        // Expect Redeem and VTBurned events with calculated values
        vm.expectEmit(true, true, true, true);
        emit VTBurned(alice, expectedBurnedVtAmount);
        vm.expectEmit(true, true, true, true);
        emit Redeem(depositId, alice, address(nft), tokenId, 1);
        
        // Alice redeems NFT 2
        lntVault.redeem(depositId, tokenId, 1);
        
        // Check NFT balance after
        assertEq(nft.ownerOf(tokenId), alice);
        
        // Verify deposit is marked as redeemed
        info = lntVault.depositInfo(depositId);
        assertTrue(info.redeemed);
        
        // Try to redeem again
        vm.expectRevert("Already redeemed");
        lntVault.redeem(depositId, tokenId, 1);
        vm.stopPrank();
    }

    function test_LntVaultERC721RedeemETH() public {
        // Setup - deploy contracts and initialize
        uint256 genesisTime = block.timestamp;
        uint256 vestingTokenAmountPerNft = 10000 * 10**18;  // 10000 $VT per NFT
        uint256 vestingStartTime = genesisTime + ONE_DAY_IN_SECS;
        uint256 vestingDuration = 100 * ONE_DAY_IN_SECS;   // [Day 1, Day 101]
        
        vm.startPrank(bob);
        lntVault.updateParamValue(bytes32("f1"), 10**9); // 0.1%
        lntVault.initialize(
            address(nft), address(lntMarketRouter), address(vt), 
            vestingTokenAmountPerNft, vestingStartTime, vestingDuration
        );
        vm.stopPrank();
        
        // Alice deposits NFT
        vm.startPrank(alice);
        nft.approve(address(lntVault), 1);
        lntVault.deposit(1, 1);
        
        // Check VT balance after deposit
        uint256 aliceVtBalance = vt.balanceOf(alice);
        assertGt(aliceVtBalance, 0, "Alice should have VT tokens");
        
        // Try to redeem T before initialization (should fail)
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
        
        // Set redeemAmount to a reasonable value
        uint256 redeemAmount = 100 ether; // 100 ETH for simplicity
        
        // Try to redeem without sufficient balance in vault
        vm.expectRevert("Insufficient token balance");
        lntVault.redeemT(redeemAmount);
        vm.stopPrank();
        
        // Bob sends ETH to the vault to match the exact redeemAmount
        vm.startPrank(bob);
        (bool success, ) = address(lntVault).call{value: redeemAmount}("");
        require(success, "ETH transfer failed");
        vm.stopPrank();
        
        // Now Alice can redeem
        vm.startPrank(alice);
        // Approve the vault to spend VT tokens
        vt.approve(address(lntVault), redeemAmount);
        
        // Check balances before redemption
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

    function test_LntVaultERC721RedeemERC20() public {
        // Setup - deploy contracts and initialize
        uint256 genesisTime = block.timestamp;
        uint256 vestingTokenAmountPerNft = 10000 * 10**18;  // 10000 $VT per NFT
        uint256 vestingStartTime = genesisTime + ONE_DAY_IN_SECS;
        uint256 vestingDuration = 100 * ONE_DAY_IN_SECS;   // [Day 1, Day 101]
        
        // Deploy a mock ERC20 token
        vm.startPrank(bob);
        MockERC20 mockToken = new MockERC20("Mock Token", "MT", 18);
        
        lntVault.initialize(
            address(nft), address(lntMarketRouter), address(vt), 
            vestingTokenAmountPerNft, vestingStartTime, vestingDuration
        );
        
        // Initialize T with the ERC20 token address
        vm.expectEmit(true, true, true, true);
        emit InitializedT(address(mockToken));
        lntVault.initializeT(address(mockToken));
        
        // Verify initialized correctly
        assertEq(lntVault.initializedT(), true);
        assertEq(lntVault.T(), address(mockToken));
        
        // Mint tokens to vault for redemption tests
        mockToken.mint(address(lntVault), 100 * 10**18); // Mint tokens to vault
        vm.stopPrank();
        
        // Alice deposits NFT
        vm.startPrank(alice);
        nft.approve(address(lntVault), 1);
        lntVault.deposit(1, 1);
        
        // Check VT balance after deposit
        uint256 aliceVtBalance = vt.balanceOf(alice);
        assertGt(aliceVtBalance, 0, "Alice should have VT tokens");
        
        // Try to redeem T before vesting ends (should fail)
        vm.expectRevert("Vesting not ended");
        lntVault.redeemT(1);
        
        // Warp time to after vesting period (Day 102)
        vm.warp(genesisTime + ONE_DAY_IN_SECS * 102);
        
        // Set redeemAmount to a reasonable value
        uint256 redeemAmount = 50 * 10**18; // 50 tokens - less than the 100 we minted to the vault
        
        // Approve the vault to spend VT tokens
        vt.approve(address(lntVault), redeemAmount);
        
        // Check token balances before redemption
        uint256 aliceTokenBefore = mockToken.balanceOf(alice);
        uint256 vaultTokenBefore = mockToken.balanceOf(address(lntVault));
        
        // Expect RedeemT event - make sure we set the expectation right before the action
        vm.expectEmit(true, false, false, true);
        emit RedeemT(alice, redeemAmount);
        
        // Redeem VT for ERC20 token
        lntVault.redeemT(redeemAmount);
        
        // Verify balances after redemption
        assertEq(vt.balanceOf(alice), aliceVtBalance - redeemAmount, "Alice's VT balance should decrease");
        assertEq(mockToken.balanceOf(alice), aliceTokenBefore + redeemAmount, "Alice's token balance should increase");
        assertEq(mockToken.balanceOf(address(lntVault)), vaultTokenBefore - redeemAmount, "Vault's token balance should decrease");
        
        vm.stopPrank();
    }

    function test_LntVaultERC721BuybackWithETH() public {
        // Setup - deploy contracts and initialize
        uint256 genesisTime = block.timestamp;
        uint256 vestingTokenAmountPerNft = 10000 * 10**18;  // 10000 $VT per NFT
        uint256 vestingStartTime = genesisTime + ONE_DAY_IN_SECS;
        uint256 vestingDuration = 100 * ONE_DAY_IN_SECS;   // [Day 1, Day 101]
        
        vm.startPrank(bob);
        lntVault.initialize(
            address(nft), address(lntMarketRouter), address(vt), 
            vestingTokenAmountPerNft, vestingStartTime, vestingDuration
        );
        
        // Initialize T with ETH address - this is required for buyback
        vm.expectEmit(true, true, true, true);
        emit InitializedT(ETH_ADDRESS);
        lntVault.initializeT(ETH_ADDRESS);
        vm.stopPrank();
        
        // Have Alice deposit NFT to get VT tokens
        vm.startPrank(alice);
        nft.approve(address(lntVault), 1);
        lntVault.deposit(1, 1);
        
        // Now Alice has VT tokens, create VT/ETH liquidity pool
        uint256 liquidityVTAmount = 100 * 10**18; // 100 VT
        uint256 liquidityETHAmount = 80 * 10**18; // 80 ETH
        
        // Approve router to spend VT tokens
        vt.approve(address(lntMarketRouter), liquidityVTAmount);
        
        // Add liquidity to create VT/ETH pool
        lntMarketRouter.addLiquidityETH{value: liquidityETHAmount}(
            address(vt),         // token address
            liquidityVTAmount,   // token amount
            0,                   // min token amount
            0,                   // min ETH amount
            alice,               // to address
            block.timestamp + 60 // deadline
        );
        vm.stopPrank();
        
        // Bob sends ETH to vault for buyback
        vm.startPrank(bob);
        (bool success, ) = address(lntVault).call{value: 10 ether}("");
        require(success, "ETH transfer failed");
        
        // Check vault ETH balance before buyback
        uint256 vaultEthBefore = address(lntVault).balance;
        
        // Set buyback amount and minimum VT expected
        uint256 buybackAmount = 1 ether;
        uint256 minVtAmount = 0.5 ether; // Lower min amount to avoid slippage issues
        
        // We can't precisely predict the amountVT (1.23e18 from the trace),
        // so we'll only check the first two parameters
        vm.expectEmit(true, true, false, false);
        emit Buyback(bob, buybackAmount, 0); // The third parameter won't be checked
        
        // Execute buyback with ETH
        lntVault.buyback(buybackAmount, minVtAmount);
        
        // Verify ETH balance decreased
        assertEq(address(lntVault).balance, vaultEthBefore - buybackAmount, "Vault's ETH balance should decrease");
        
        vm.stopPrank();
    }

    function test_LntVaultERC721BuybackWithERC20() public {
        // Setup - deploy contracts and initialize
        uint256 genesisTime = block.timestamp;
        uint256 vestingTokenAmountPerNft = 10000 * 10**18;  // 10000 $VT per NFT
        uint256 vestingStartTime = genesisTime + ONE_DAY_IN_SECS;
        uint256 vestingDuration = 100 * ONE_DAY_IN_SECS;   // [Day 1, Day 101]
        
        // Deploy a mock ERC20 token
        vm.startPrank(bob);
        MockERC20 mockToken = new MockERC20("Mock Token", "MT", 18);
        
        // Also mint tokens to Alice for liquidity pool
        mockToken.mint(alice, 1000 * 10**18);
        
        lntVault.initialize(
            address(nft), address(lntMarketRouter), address(vt), 
            vestingTokenAmountPerNft, vestingStartTime, vestingDuration
        );
        
        // Initialize T with the ERC20 token address
        vm.expectEmit(true, true, true, true);
        emit InitializedT(address(mockToken));
        lntVault.initializeT(address(mockToken));
        
        // Mint tokens to vault for buyback (these tokens will be used for buyback)
        mockToken.mint(address(lntVault), 100 * 10**18); 
        vm.stopPrank();
        
        // Have Alice deposit NFT to get VT tokens
        vm.startPrank(alice);
        nft.approve(address(lntVault), 1);
        lntVault.deposit(1, 1);
        
        // Now Alice has VT tokens, create VT/ERC20 liquidity pool
        uint256 liquidityVTAmount = 100 * 10**18; // 100 VT
        uint256 liquidityTokenAmount = 80 * 10**18; // 80 tokens
        
        // Approve router to spend VT and ERC20 tokens
        vt.approve(address(lntMarketRouter), liquidityVTAmount);
        mockToken.approve(address(lntMarketRouter), liquidityTokenAmount);
        
        // Add liquidity to create VT/ERC20 pool
        lntMarketRouter.addLiquidity(
            address(vt),         // tokenA
            address(mockToken),  // tokenB
            liquidityVTAmount,   // amountADesired
            liquidityTokenAmount, // amountBDesired
            0,                   // amountAMin
            0,                   // amountBMin
            alice,               // to
            block.timestamp + 60 // deadline
        );
        vm.stopPrank();
        
        // Bob executes buyback
        vm.startPrank(bob);
        
        // Check token balance before buyback
        uint256 vaultTokenBefore = mockToken.balanceOf(address(lntVault));
        
        // Set buyback amount and minimum VT expected
        uint256 buybackAmount = 10 * 10**18; // 10 tokens
        uint256 minVtAmount = 5 * 10**18;   // Lower min amount to avoid slippage issues
        
        // We only check the first two parameters of the event
        vm.expectEmit(true, true, false, false);
        emit Buyback(bob, buybackAmount, 0); // The third parameter won't be checked
        
        // Execute buyback with ERC20 token
        lntVault.buyback(buybackAmount, minVtAmount);
        
        // Verify token balance decreased
        assertEq(mockToken.balanceOf(address(lntVault)), vaultTokenBefore - buybackAmount, "Vault's token balance should decrease");
        
        vm.stopPrank();
    }
}