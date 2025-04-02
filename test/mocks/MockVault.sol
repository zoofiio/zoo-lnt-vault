// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {YieldToken} from "../../src/tokens/YieldToken.sol";

/**
 * @title MockVault
 * @dev Mock implementation of a vault for testing YieldToken
 */
contract MockVault {
    address public yieldToken;
    address constant ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    constructor() {}

    function initialize(address _yieldToken) external {
        yieldToken = _yieldToken;
    }

    function mintYieldToken(address to, uint256 amount) external {
        YieldToken(yieldToken).mint(to, amount);
    }

    function addRewards(address token, uint256 amount) external payable {
        if (token == ETH_ADDRESS) {
            require(msg.value == amount, "MockVault: ETH amount mismatch");
            YieldToken(yieldToken).addRewards{value: amount}(token, amount);
        } else {
            require(msg.value == 0, "Invalid msg.value");
            IERC20(token).transferFrom(msg.sender, address(this), amount);
            IERC20(token).approve(address(yieldToken), amount);
            YieldToken(yieldToken).addRewards(token, amount);
        }
    }

    function addTimeWeightedRewards(address token, uint256 amount) external payable {
        if (token == ETH_ADDRESS) {
            require(msg.value == amount, "MockVault: ETH amount mismatch");
            YieldToken(yieldToken).addTimeWeightedRewards{value: amount}(token, amount);
        } else {
            require(msg.value == 0, "Invalid msg.value");
            IERC20(token).transferFrom(msg.sender, address(this), amount);
            IERC20(token).approve(address(yieldToken), amount);
            YieldToken(yieldToken).addTimeWeightedRewards(token, amount);
        }
    }

    function setEpochEndTimestamp(uint256 timestamp) external {
        YieldToken(yieldToken).setEpochEndTimestamp(timestamp);
    }
}
