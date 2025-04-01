// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../../src/interfaces/IYieldToken.sol";
import "../../src/libs/Constants.sol";

contract MockVault is Ownable {
    IYieldToken public yieldToken;
    bool public initialized;
    
    constructor() Ownable(msg.sender) {
        initialized = false;
    }
    
    // Initialize with yieldToken address - only owner can call
    function initialize(address _yieldToken) external onlyOwner {
        require(!initialized, "Already initialized");
        require(_yieldToken != address(0), "Zero address detected");
        yieldToken = IYieldToken(_yieldToken);
        initialized = true;
    }
    
    // Function to mint tokens - simulating what a real vault would do
    function mintYieldToken(address to, uint256 amount) external onlyInitialized {
        yieldToken.mint(to, amount);
    }
    
    // Set the epoch end timestamp - only vault can do this
    function setEpochEndTimestamp(uint256 _epochEndTimestamp) external onlyInitialized {
        yieldToken.setEpochEndTimestamp(_epochEndTimestamp);
    }
    
    // Add standard rewards with possible ETH value
    function addRewards(address rewardToken, uint256 amount) external payable onlyInitialized {
        if(rewardToken == Constants.NATIVE_TOKEN) {
            // ETH as reward
            require(msg.value == amount, "Invalid msg.value");
            yieldToken.addRewards{value: amount}(rewardToken, amount);
        } else {
            // ERC20 as reward
            require(msg.value == 0, "Invalid msg.value");
            IERC20(rewardToken).transferFrom(msg.sender, address(this), amount);
            IERC20(rewardToken).approve(address(yieldToken), amount);
            yieldToken.addRewards(rewardToken, amount);
        }
    }
    
    // Add time-weighted rewards with possible ETH value
    function addTimeWeightedRewards(address rewardToken, uint256 amount) external payable onlyInitialized {
        if(rewardToken == Constants.NATIVE_TOKEN) {
            // ETH as reward
            require(msg.value == amount, "Invalid msg.value");
            yieldToken.addTimeWeightedRewards{value: amount}(rewardToken, amount);
        } else {
            // ERC20 as reward
            require(msg.value == 0, "Invalid msg.value");
            IERC20(rewardToken).transferFrom(msg.sender, address(this), amount);
            IERC20(rewardToken).approve(address(yieldToken), amount);
            yieldToken.addTimeWeightedRewards(rewardToken, amount);
        }
    }
    
    // Modifier to check if contract is initialized
    modifier onlyInitialized() {
        require(initialized, "Not initialized");
        _;
    }
    
    // To receive ETH
    receive() external payable {}
}
