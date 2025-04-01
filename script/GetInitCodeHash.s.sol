// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/market/LntMarket.sol";

contract GetInitCodeHash is Script {
    function run() public {
        // Get bytecode of LntMarket
        bytes memory bytecode = type(LntMarket).creationCode;
        
        // Calculate keccak256 hash of the bytecode
        bytes32 initCodeHash = keccak256(bytecode);
        
        // Print result
        console.logBytes32(initCodeHash);
        
        // Hexadecimal representation
        console.log("Init code hash for LntMarket: 0x%s", vm.toString(initCodeHash));
    }
}