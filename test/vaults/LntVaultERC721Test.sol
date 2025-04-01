// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../../src/vaults/LntVaultERC721.sol";
import "../../src/tokens/VestingToken.sol";
import "../../src/tokens/YieldToken.sol";
import "../mocks/MockERC721.sol";
import "../mocks/MockERC20.sol";
import "../mocks/WETH.sol";
import "../../src/market/LntMarketRouter.sol";
import "../../src/market/LntMarketFactory.sol";

contract LntVaultERC721Test is Test {
    // Main contracts
    LntVaultERC721 public vault;
    VestingToken public vt;
    YieldToken public yt;
    
    // Mock contracts
    MockERC721 public mockNFT;
    MockERC20 public mockToken;
    WETH public weth;
    
    // Market contracts
    LntMarketRouter public router;
    LntMarketFactory public factory;
    
    // Users
    address public owner;
    address public user1;
    address public user2;
    address public treasury;
    
    // Test data
    uint256[] public tokenIds;
    uint256 public constant NFT_PRICE = 10 ether;
    uint256 public vestingStartTime;
    uint256 public vestingDuration = 365 days;
    
    function setUp() public {
        owner = makeAddr("owner");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        treasury = makeAddr("treasury");
        vestingStartTime = block.timestamp;
        
        vm.startPrank(owner);
        
        // Deploy mock NFT
        mockNFT = new MockERC721("Mock NFT", "MNFT");
        
        // Deploy mock token
        mockToken = new MockERC20("Mock Token", "MTKN", 18);
        
        // Deploy WETH
        weth = new WETH();
        
        // Deploy market factory and router
        factory = new LntMarketFactory();
        router = new LntMarketRouter(address(factory), address(weth));
        
        // Deploy vault
        vault = new LntVaultERC721(owner);
        
        // Deploy VT and YT tokens
        vt = new VestingToken(address(vault), "Vesting Token", "VT");
        yt = new YieldToken(address(vault), "Yield Token", "YT");
        
        // Initialize vault with token addresses
        vault.initialize(
            address(mockNFT),
            address(router),
            address(vt),
            NFT_PRICE,
            vestingStartTime,
            vestingDuration
        );
        
        // Mint NFTs to users - using safeMint and making sure the owner is a tester
        for (uint i = 1; i <= 5; i++) {
            mockNFT.safeMint(user1, i); // Using safeMint instead of mint
            tokenIds.push(i);
        }
        
        // Mint tokens to treasury and users
        mockToken.mint(address(vault), 1000 ether);
        mockToken.mint(user1, 100 ether);
        mockToken.mint(user2, 100 ether);
        
        vm.stopPrank();
        
        // Setup vault parameters
        vm.startPrank(owner);
        vault.upsertParamConfig("f1", 800, 100, 1000); // 80% (in basis points)
        vault.upsertParamConfig("f2", 200, 0, 1000);   // 20% (in basis points)
        vault.initializeT(address(mockToken));
        vm.stopPrank();
    }
    
    function testInitialization() public {
        assertEq(vault.NFT(), address(mockNFT));
        assertEq(uint(vault.NFTType()), uint(Constants.NftType.ERC721));
        assertEq(vault.VT(), address(vt));
        // YT token is set separately in our test setup, and is accessed via T()
        assertEq(vault.T(), address(mockToken));
        assertEq(vault.vestingTokenAmountPerNft(), NFT_PRICE);
        assertTrue(vault.initialized());
        assertTrue(vault.initializedT());
    }
    
    function testDeposit() public {
        vm.startPrank(user1);
        
        // Approve NFT for vault
        mockNFT.setApprovalForAll(address(vault), true);
        
        // Deposit NFT
        uint256 depositId = vault.deposit(tokenIds[0], 1);
        vm.stopPrank();
        
        // Check deposit info
        LntVaultBase.DepositInfo memory info = vault.depositInfo(depositId);
        assertEq(info.depositId, depositId);
        assertEq(info.user, user1);
        assertEq(info.tokenId, tokenIds[0]);
        assertEq(info.value, 1);
        assertEq(info.redeemed, false);
        assertEq(info.f1OnDeposit, 800); // 80% in basis points
        
        // Check NFT ownership
        assertEq(mockNFT.ownerOf(tokenIds[0]), address(vault));
        
        // Check VT and YT balances
        assertEq(vt.balanceOf(user1), NFT_PRICE * 80 / 100); // 80% of NFT price
        assertEq(yt.balanceOf(user1), NFT_PRICE * 20 / 100); // 20% of NFT price
    }
    
    function testBatchDeposit() public {
        vm.startPrank(user1);
        
        // Approve NFT for vault
        mockNFT.setApprovalForAll(address(vault), true);
        
        // Deposit multiple NFTs (using first 3 tokens)
        uint256[] memory selectedTokenIds = new uint256[](3);
        uint256[] memory amounts = new uint256[](3);
        
        for (uint i = 0; i < 3; i++) {
            selectedTokenIds[i] = tokenIds[i];
            amounts[i] = 1;
        }
        
        uint256[] memory depositIds = vault.batchDeposit(selectedTokenIds, amounts);
        vm.stopPrank();
        
        // Check deposit info for each NFT
        for (uint i = 0; i < 3; i++) {
            LntVaultBase.DepositInfo memory info = vault.depositInfo(depositIds[i]);
            assertEq(info.depositId, depositIds[i]);
            assertEq(info.user, user1);
            assertEq(info.tokenId, tokenIds[i]);
            assertEq(info.value, 1);
            assertEq(info.redeemed, false);
        }
        
        // Check NFT ownership
        for (uint i = 0; i < 3; i++) {
            assertEq(mockNFT.ownerOf(tokenIds[i]), address(vault));
        }
        
        // Check VT and YT balances (3 NFTs deposited)
        assertEq(vt.balanceOf(user1), 3 * NFT_PRICE * 80 / 100); // 80% of NFT price * 3
        assertEq(yt.balanceOf(user1), 3 * NFT_PRICE * 20 / 100); // 20% of NFT price * 3
    }
    
    function testRedeem() public {
        // First deposit an NFT
        vm.startPrank(user1);
        mockNFT.setApprovalForAll(address(vault), true);
        uint256 depositId = vault.deposit(tokenIds[0], 1);
        
        // Try to redeem too early (should fail)
        vm.expectRevert();
        vault.redeem(depositId, tokenIds[0], 1);
        
        // Simulate time passing for vesting to complete
        vm.warp(block.timestamp + 366 days);
        
        // Should be able to redeem now
        vault.redeem(depositId, tokenIds[0], 1);
        vm.stopPrank();
        
        // Check NFT ownership after redemption
        assertEq(mockNFT.ownerOf(tokenIds[0]), user1);
        
        // Check deposit status
        LntVaultBase.DepositInfo memory info = vault.depositInfo(depositId);
        assertTrue(info.redeemed);
    }
    
    function testRedeemT() public {
        // First deposit an NFT
        vm.startPrank(user1);
        mockNFT.setApprovalForAll(address(vault), true);
        vault.deposit(tokenIds[0], 1);
        
        // Get initial VT balance
        uint256 initialVTBalance = vt.balanceOf(user1);
        
        // Try to redeem T too early (should fail)
        vm.expectRevert();
        vault.redeemT(initialVTBalance);
        
        // Simulate time passing for vesting to complete
        vm.warp(block.timestamp + 366 days);
        
        // Should be able to redeem T now
        vault.redeemT(initialVTBalance);
        vm.stopPrank();
        
        // Check balances after redemption
        assertEq(vt.balanceOf(user1), 0);
        assertEq(mockToken.balanceOf(user1), 100 ether + initialVTBalance); // Initial balance + redeemed amount
    }
    
    function testBuyback() public {
        // Setup market for VT/T pair
        vm.startPrank(owner);
        
        // Create liquidity in the market
        mockToken.mint(owner, 100 ether);
        vt.mint(owner, 100 ether);
        
        mockToken.approve(address(router), 50 ether);
        vt.approve(address(router), 50 ether);
        
        router.addLiquidity(
            address(mockToken),
            address(vt),
            50 ether,
            50 ether,
            0,
            0,
            owner,
            block.timestamp + 1 days
        );
        
        // Perform buyback
        vault.buyback(10 ether, 9 ether); // Expecting at least 9 VT for 10 T
        vm.stopPrank();
        
        // Check that T tokens were spent
        assertLe(mockToken.balanceOf(address(vault)), 990 ether); // 1000 - 10
    }
    
    function testUserDeposits() public {
        vm.startPrank(user1);
        mockNFT.setApprovalForAll(address(vault), true);
        
        // Deposit multiple NFTs
        uint256 depositId1 = vault.deposit(tokenIds[0], 1);
        uint256 depositId2 = vault.deposit(tokenIds[1], 1);
        uint256 depositId3 = vault.deposit(tokenIds[2], 1);
        vm.stopPrank();
        
        // Get user deposits
        uint256[] memory userDeposits = vault.userDeposits(user1);
        
        // Check results
        assertEq(userDeposits.length, 3);
        assertEq(userDeposits[0], depositId1);
        assertEq(userDeposits[1], depositId2);
        assertEq(userDeposits[2], depositId3);
    }

    function testDepositCount() public {
        vm.startPrank(user1);
        mockNFT.setApprovalForAll(address(vault), true);
        
        // Check initial count
        assertEq(vault.depositCount(), 0);
        
        // Deposit multiple NFTs
        vault.deposit(tokenIds[0], 1);
        assertEq(vault.depositCount(), 1);
        
        vault.deposit(tokenIds[1], 1);
        assertEq(vault.depositCount(), 2);
        
        vault.deposit(tokenIds[2], 1);
        assertEq(vault.depositCount(), 3);
        vm.stopPrank();
    }
}