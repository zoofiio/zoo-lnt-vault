// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {LntMarketFactory} from "../src/market/LntMarketFactory.sol";
import {LntMarketRouter} from "../src/market/LntMarketRouter.sol";
import {LntContractFactory} from "../src/LntContractFactory.sol";

contract DeployContracts is Script {
    using stdJson for string;

    function getWETHAddress(string memory network) internal pure returns (string memory) {
        if (keccak256(bytes(network)) == keccak256(bytes("mainnet"))) return "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2";
        if (keccak256(bytes(network)) == keccak256(bytes("sepolia"))) return "0xfff9976782d46cc05630d1f6ebab18b2324d6b14";
        return "0xfff9976782d46cc05630d1f6ebab18b2324d6b14"; // Default to sepolia
    }

     // Network-specific deployment file path
    function getDeploymentPath(string memory network) internal pure returns (string memory) {
        return string(abi.encodePacked("./deployments/", network, ".json"));
    }
    
    // Check if a contract is already deployed
    function isContractDeployed(string memory network, string memory contractName) internal view returns (bool, address) {
        string memory deploymentPath = getDeploymentPath(network);
        
        // Check if the deployment file exists
        try vm.readFile(deploymentPath) returns (string memory json) {
            // Make sure the JSON is not empty and is valid
            if (bytes(json).length == 0 || keccak256(bytes(json)) == keccak256(bytes("{}"))) {
                return (false, address(0));
            }
            
            // Use vm.parseJson directly - it returns bytes that need to be decoded
            string memory addressPath = string(abi.encodePacked(".", contractName, ".address"));
            
            try vm.parseJson(json, addressPath) returns (bytes memory rawAddress) {
                if (rawAddress.length > 0) {
                    // Convert the bytes to an address
                    address contractAddress = abi.decode(rawAddress, (address));
                    return (true, contractAddress);
                } else {
                    return (false, address(0));
                }
            } catch {
                return (false, address(0));
            }
        } catch {
            // Deployment file doesn't exist or can't be read
            return (false, address(0));
        }
    }
    
    // Format JSON with indentation and line breaks
    function formatJson(string memory jsonStr) internal pure returns (string memory) {
        bytes memory jsonBytes = bytes(jsonStr);
        uint256 indent = 0;
        bool inQuotes = false;
        
        string memory result = "";
        string memory indentStr = "";
        
        for (uint256 i = 0; i < jsonBytes.length; i++) {
            bytes1 char = jsonBytes[i];
            
            // Track whether we're inside quotes
            if (char == '"' && (i == 0 || jsonBytes[i-1] != '\\')) {
                inQuotes = !inQuotes;
            }
            
            // Only apply formatting if outside quotes
            if (!inQuotes) {
                // Handle opening braces
                if (char == '{' || char == '[') {
                    // Add opening brace followed by new line
                    result = string(abi.encodePacked(result, string(abi.encodePacked(char)), "\n"));
                    indent++;
                    indentStr = getIndent(indent);
                    result = string(abi.encodePacked(result, indentStr));
                    continue;
                }
                
                // Handle closing braces
                if (char == '}' || char == ']') {
                    // Add new line and indentation before closing brace
                    result = string(abi.encodePacked(result, "\n"));
                    indent--;
                    indentStr = getIndent(indent);
                    result = string(abi.encodePacked(result, indentStr, string(abi.encodePacked(char))));
                    continue;
                }
                
                // Handle commas
                if (char == ',') {
                    // Add comma followed by new line and indentation
                    result = string(abi.encodePacked(result, string(abi.encodePacked(char)), "\n", indentStr));
                    continue;
                }
                
                // Handle colons
                if (char == ':') {
                    // Add colon followed by a space
                    result = string(abi.encodePacked(result, ": "));
                    continue;
                }
            }
            
            // Add all other characters
            result = string(abi.encodePacked(result, string(abi.encodePacked(char))));
        }
        
        return result;
    }
    
    // Generate indentation string
    function getIndent(uint256 level) internal pure returns (string memory) {
        string memory indent = "";
        for (uint256 i = 0; i < level; i++) {
            indent = string(abi.encodePacked(indent, "  ")); // 2 spaces per level
        }
        return indent;
    }
    
    // Save deployment information to network-specific file
    function saveDeployment(string memory network, string memory contractsJson) internal {
        string memory deploymentPath = getDeploymentPath(network);
        string memory existingJson = "{}";
        
        // Check if deployment file exists and read it
        try vm.readFile(deploymentPath) returns (string memory json) {
            if (bytes(json).length > 0 && keccak256(bytes(json)) != keccak256(bytes("{}"))) {
                existingJson = json;
            }
        } catch {
            // If file doesn't exist, we'll create it
        }
        
        // Merge the new contracts with existing JSON
        string memory mergedJson = mergeJson(existingJson, contractsJson);
        
        // Create directory if it doesn't exist
        string[] memory mkdirCmd = new string[](3);
        mkdirCmd[0] = "mkdir";
        mkdirCmd[1] = "-p";
        mkdirCmd[2] = "./deployments";
        vm.ffi(mkdirCmd);
        
        // Format the JSON before saving
        string memory formattedJson = formatJson(mergedJson);
        
        // Directly write to the file, overwriting any existing content
        vm.writeFile(deploymentPath, formattedJson);
        
        console.log("\nDeployment info saved to:");
        console.log("- %s", deploymentPath);
    }
    
    // Merge two JSON objects
    function mergeJson(string memory existingJson, string memory newJson) internal pure returns (string memory) {
        // Quick check if either JSON is empty
        if (keccak256(bytes(existingJson)) == keccak256(bytes("{}"))) {
            return newJson;
        }
        if (keccak256(bytes(newJson)) == keccak256(bytes("{}"))) {
            return existingJson;
        }
        
        // Remove the leading '{' and trailing '}' from both strings
        string memory existingContent = substring(existingJson, 1, bytes(existingJson).length - 2);
        string memory newContent = substring(newJson, 1, bytes(newJson).length - 2);
        
        // Combine the content and wrap in curly braces
        return string(abi.encodePacked("{", existingContent, ",", newContent, "}"));
    }
    
    // Helper function to extract a substring
    function substring(string memory str, uint256 startIndex, uint256 endIndex) internal pure returns (string memory) {
        bytes memory strBytes = bytes(str);
        bytes memory result = new bytes(endIndex - startIndex + 1);
        for (uint256 i = startIndex; i <= endIndex; i++) {
            result[i - startIndex] = strBytes[i];
        }
        return string(result);
    }

    LntMarketFactory public lntMarketFactory;
    LntMarketRouter public lntMarketRouter;
    LntContractFactory public lntContractFactory;

    function run() public {
        // Load private key from .env
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        // Get network name and treasury address
        string memory network = vm.envOr("NETWORK", string("sepolia"));
        address ivyAddress = vm.envOr("TREASURY_ADDRESS", address(deployer));

        console.log("Deploying contracts to network:", network);
        console.log("Deployer address:", deployer);
        console.log("Treasury address:", ivyAddress);

        // Create JSON objects to store deployment info for each contract
        string memory factoryJson = "{}";
        string memory routerJson = "{}";
        string memory contractFactoryJson = "{}";
        
        vm.startBroadcast(deployerPrivateKey);

        // Deploy LntMarketFactory if not already deployed
        bool deployed;
        address existingAddress; // Changed from address payable to address
        (deployed, existingAddress) = isContractDeployed(network, "LntMarketFactory");
        if (deployed) {
            console.log("LntMarketFactory already deployed at:", existingAddress);
            lntMarketFactory = LntMarketFactory(existingAddress);
        } else {
            lntMarketFactory = new LntMarketFactory();
            console.log("LntMarketFactory deployed at:", address(lntMarketFactory));
            
            // Format contract info as a nested object
            string memory obj = "{";
            obj = string(abi.encodePacked(obj, "\"address\":\"", vm.toString(address(lntMarketFactory)), "\","));
            obj = string(abi.encodePacked(obj, "\"contract\":\"src/market/LntMarketFactory.sol:LntMarketFactory\","));
            obj = string(abi.encodePacked(obj, "\"args\":[]"));
            obj = string(abi.encodePacked(obj, "}"));
            
            // Build JSON
            factoryJson = string(abi.encodePacked("{\"LntMarketFactory\":", obj, "}"));
        }

        // Get WETH address for the network
        address wethAddress = vm.parseAddress(getWETHAddress(network));
        console.log("Using WETH address:", wethAddress);

        // Deploy LntMarketRouter if not already deployed
        (deployed, existingAddress) = isContractDeployed(network, "LntMarketRouter");
        if (deployed) {
            console.log("LntMarketRouter already deployed at:", existingAddress);
            // Use payable(existingAddress) to convert to address payable when needed
            lntMarketRouter = LntMarketRouter(payable(existingAddress));
        } else {
            lntMarketRouter = new LntMarketRouter(address(lntMarketFactory), wethAddress);
            console.log("LntMarketRouter deployed at:", address(lntMarketRouter));
            
            // Format contract info as a nested object
            string memory obj = "{";
            obj = string(abi.encodePacked(obj, "\"address\":\"", vm.toString(address(lntMarketRouter)), "\","));
            obj = string(abi.encodePacked(obj, "\"contract\":\"src/market/LntMarketRouter.sol:LntMarketRouter\","));
            obj = string(abi.encodePacked(obj, "\"args\":[\"", vm.toString(address(lntMarketFactory)), "\",\"", vm.toString(wethAddress), "\"]"));
            obj = string(abi.encodePacked(obj, "}"));
            
            // Build JSON
            routerJson = string(abi.encodePacked("{\"LntMarketRouter\":", obj, "}"));
        }

        // Deploy LntContractFactory if not already deployed
        (deployed, existingAddress) = isContractDeployed(network, "LntContractFactory");
        if (deployed) {
            console.log("LntContractFactory already deployed at:", existingAddress);
            lntContractFactory = LntContractFactory(existingAddress);
        } else {
            lntContractFactory = new LntContractFactory(ivyAddress);
            console.log("LntContractFactory deployed at:", address(lntContractFactory));
            
            // Format contract info as a nested object
            string memory obj = "{";
            obj = string(abi.encodePacked(obj, "\"address\":\"", vm.toString(address(lntContractFactory)), "\","));
            obj = string(abi.encodePacked(obj, "\"contract\":\"src/LntContractFactory.sol:LntContractFactory\","));
            obj = string(abi.encodePacked(obj, "\"args\":[\"", vm.toString(ivyAddress), "\"]"));
            obj = string(abi.encodePacked(obj, "}"));
            
            // Build JSON
            contractFactoryJson = string(abi.encodePacked("{\"LntContractFactory\":", obj, "}"));
        }

        // Output deployment summary
        console.log("\nDeployment Summary:");
        console.log("LntMarketFactory:", address(lntMarketFactory));
        console.log("LntMarketRouter:", address(lntMarketRouter));
        console.log("LntContractFactory:", address(lntContractFactory));

        vm.stopBroadcast();
        
        // Collect all newly deployed contracts
        string memory newDeployments = "{}";
        
        // Add each contract JSON to newDeployments if it was deployed
        if (bytes(factoryJson).length > 2) { // More than just "{}"
            newDeployments = factoryJson;
        }
        
        if (bytes(routerJson).length > 2) {
            if (bytes(newDeployments).length <= 2) {
                newDeployments = routerJson;
            } else {
                // Use the mergeJson function instead of string manipulation
                newDeployments = mergeJson(newDeployments, routerJson);
            }
        }
        
        if (bytes(contractFactoryJson).length > 2) {
            if (bytes(newDeployments).length <= 2) {
                newDeployments = contractFactoryJson;
            } else {
                // Use the mergeJson function instead of string manipulation
                newDeployments = mergeJson(newDeployments, contractFactoryJson);
            }
        }
        
        // Save deployment info - now this will merge with existing JSON
        saveDeployment(network, newDeployments);
    }
}