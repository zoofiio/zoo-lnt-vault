// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/tokens/VestingToken.sol";
import "../src/tokens/YieldToken.sol";
import "../src/vaults/LntVaultERC721.sol";
import "../src/vaults/LntVaultERC1155.sol";
import "../src/market/LntMarketFactory.sol";
import "../src/market/LntMarketRouter.sol";
import "../test/mocks/WETH.sol";
import "../test/mocks/MockERC721.sol";
import "../src/LntContractFactory.sol";

contract DeployContracts is Script {
    // Configuration
    address public treasury;
    address public nftContract;
    address public weth;
    uint256 public nftPrice = 10 ether;
    
    // Deployment timestamps and durations
    uint256 public vestingStartTime;
    uint256 public vestingDuration = 365 days;
    
    // Deployed contract addresses
    LntContractFactory public factory;
    LntMarketFactory public marketFactory;
    LntMarketRouter public router;
    LntVaultERC721 public vault;
    VestingToken public vt;
    YieldToken public yt;

    function setUp() public virtual {
        // Load environment variables
        treasury = vm.envOr("TREASURY_ADDRESS", address(0));
        nftContract = vm.envOr("NFT_CONTRACT_ADDRESS", address(0));
        
        // Default to deploying WETH if not provided
        if (vm.envOr("USE_EXISTING_WETH", false)) {
            weth = vm.envAddress("WETH_ADDRESS");
        }
        
        // Set vesting start time to now
        vestingStartTime = block.timestamp;
    }

    function run() public virtual {
        // A treasury address is required for deployment
        require(treasury != address(0), "Treasury address must be set");
        
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy WETH if needed
        if (weth == address(0)) {
            WETH wethContract = new WETH();
            weth = address(wethContract);
            console.log("WETH deployed at:", weth);
        }

        // Deploy contract factory with treasury
        factory = new LntContractFactory(treasury);
        console.log("LntContractFactory deployed at:", address(factory));

        // Deploy market factory
        marketFactory = new LntMarketFactory();
        console.log("LntMarketFactory deployed at:", address(marketFactory));

        // Deploy market router
        router = new LntMarketRouter(address(marketFactory), weth);
        console.log("LntMarketRouter deployed at:", address(router));
        
        // Deploy vault first (we'll need its address for the tokens)
        vault = new LntVaultERC721(msg.sender);
        console.log("LntVaultERC721 deployed at:", address(vault));

        // Now deploy tokens with the vault address
        vt = new VestingToken(address(vault), "Vesting Token", "VT");
        console.log("VestingToken deployed at:", address(vt));
        
        yt = new YieldToken(address(vault), "Yield Token", "YT");
        console.log("YieldToken deployed at:", address(yt));
        
        // Initialize vault with proper parameters
        vault.initialize(
            nftContract,             // NFT contract address
            address(router),         // LntMarketRouter address
            address(vt),             // VT token address
            nftPrice,                // vestingTokenAmountPerNft
            vestingStartTime,        // vestingStartTime
            vestingDuration          // vestingDuration
        );
        
        // Set up vault parameters
        vault.upsertParamConfig("f1", 800, 100, 1000); // 80% (in basis points)
        vault.upsertParamConfig("f2", 200, 0, 1000);   // 20% (in basis points)
        
        vm.stopBroadcast();
        
        // Save deployment addresses to file
        string memory deploymentData = vm.toString(block.chainid);
        deploymentData = string.concat(deploymentData, ",", vm.toString(block.timestamp));
        deploymentData = string.concat(deploymentData, ",LntContractFactory,", vm.toString(address(factory)));
        deploymentData = string.concat(deploymentData, ",LntMarketFactory,", vm.toString(address(marketFactory)));
        deploymentData = string.concat(deploymentData, ",LntMarketRouter,", vm.toString(address(router)));
        deploymentData = string.concat(deploymentData, ",LntVaultERC721,", vm.toString(address(vault)));
        deploymentData = string.concat(deploymentData, ",VestingToken,", vm.toString(address(vt)));
        deploymentData = string.concat(deploymentData, ",YieldToken,", vm.toString(address(yt)));
        deploymentData = string.concat(deploymentData, ",WETH,", vm.toString(weth));
        
        string memory fileName = string.concat("deployment/", vm.toString(block.chainid), "-", vm.toString(block.timestamp), ".csv");
        vm.writeFile(fileName, deploymentData);
        console.log("Deployment data saved to", fileName);
    }
}

contract DeployWithMocksScript is DeployContracts {
    function setUp() public override {
        super.setUp();
        
        // For mock deployment, set the treasury address
        treasury = makeAddr("treasury");
    }

    function run() public override {
        uint256 deployerPrivateKey = vm.envOr("PRIVATE_KEY", uint256(1));
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy mock WETH
        WETH wethContract = new WETH();
        weth = address(wethContract);
        
        // Deploy mock NFT
        MockERC721 mockNFT = new MockERC721("Mock NFT", "MNFT");
        nftContract = address(mockNFT);
        
        // Stop broadcast before calling parent run
        vm.stopBroadcast();
        
        // Now run the parent deployment with our mock addresses
        super.run();
    }
}