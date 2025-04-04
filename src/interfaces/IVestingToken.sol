// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IVestingToken is IERC20 {
    
    function mint(address to, uint256 amount) external;

    function burn(address account, uint256 amount) external;
}
