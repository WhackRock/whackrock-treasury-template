// script/SimulateDeployment.s.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "forge-std/Test.sol";  // Added for VM functionality

/**
 * @title Simulation Script for Deployment JSON Output
 * @notice This script simulates the JSON output functionality without deploying contracts
 */
contract SimulateDeploymentScript is Script {
    // Structure to hold deployment info that will be written to JSON
    struct DeploymentInfo {
        string network;
        uint256 deploymentTimestamp;
        address deployer;
        address oracle;
        address adapter;
        address factory;
        address initialVault;
        address[] allowedAssets;
        address[] initialVaultAssets;
        uint256[] initialVaultWeights;
        address usdc;
        address weth;
        address wrkRewards;
    }

    function setUp() public {}

    function run() public {
        console.log("=== SIMULATING DEPLOYMENT TO BASE MAINNET ===");
        
        // Create mock deployment info
        DeploymentInfo memory deploymentInfo;
        deploymentInfo.network = "Base Mainnet (Simulation)";
        deploymentInfo.deploymentTimestamp = block.timestamp;
        deploymentInfo.deployer = address(0x123);
        deploymentInfo.oracle = address(0xABC);
        deploymentInfo.adapter = address(0xDEF);
        deploymentInfo.factory = address(0x789);
        deploymentInfo.initialVault = address(0x456);
        deploymentInfo.usdc = 0xd9aAEc86B65D86f6A7B5B1b0c42FFA531710b6CA;
        deploymentInfo.weth = 0x4200000000000000000000000000000000000006;
        deploymentInfo.wrkRewards = 0x90cfB07A46EE4bb20C970Dda18AaD1BA3c9450Ae;
        
        // Create mock allowed assets
        address[] memory allowedAssets = new address[](4);
        allowedAssets[0] = 0x4200000000000000000000000000000000000006; // WETH
        allowedAssets[1] = 0xd9aAEc86B65D86f6A7B5B1b0c42FFA531710b6CA; // USDC
        allowedAssets[2] = 0x1a35EE4640b0A3B87705B0A4B45D227Ba60Ca2ad; // WBTC
        allowedAssets[3] = 0x50c5725949A6F0c72E6C4a641F24049A917DB0Cb; // DAI
        deploymentInfo.allowedAssets = allowedAssets;
        
        // Create mock vault assets
        address[] memory vaultAssets = new address[](3);
        vaultAssets[0] = 0x4200000000000000000000000000000000000006; // WETH
        vaultAssets[1] = 0xd9aAEc86B65D86f6A7B5B1b0c42FFA531710b6CA; // USDC
        vaultAssets[2] = 0x1a35EE4640b0A3B87705B0A4B45D227Ba60Ca2ad; // WBTC
        deploymentInfo.initialVaultAssets = vaultAssets;
        
        // Create mock vault weights
        uint256[] memory vaultWeights = new uint256[](3);
        vaultWeights[0] = 5000; // 50% WETH
        vaultWeights[1] = 3000; // 30% USDC
        vaultWeights[2] = 2000; // 20% WBTC
        deploymentInfo.initialVaultWeights = vaultWeights;
        
        // Create deployments directory if it doesn't exist
        vm.createDir("deployments", true);
        
        // Generate and save the JSON
        string memory deploymentFilePath = "deployments/simulation_base_mainnet.json";
        string memory deploymentJson = _generateDeploymentJson(deploymentInfo);
        
        // Write the JSON to file
        vm.writeFile(deploymentFilePath, deploymentJson);
        console.log("Simulation JSON saved to:", deploymentFilePath);
        
        // Print summary
        console.log("\n=== SIMULATION SUMMARY ===");
        console.log("Oracle: %s", deploymentInfo.oracle);
        console.log("Adapter: %s", deploymentInfo.adapter);
        console.log("Factory: %s", deploymentInfo.factory);
        console.log("Initial Vault: %s", deploymentInfo.initialVault);
        console.log("=========================\n");
        
        console.log("Simulation completed successfully!");
    }
    
    /**
     * @dev Helper function to generate JSON for deployment info
     * @param info Deployment info structure
     * @return json JSON string with deployment information
     */
    function _generateDeploymentJson(DeploymentInfo memory info) internal pure returns (string memory) {
        string memory json = "{";
        
        // Basic info
        json = string(abi.encodePacked(json, '"network": "', info.network, '",'));
        json = string(abi.encodePacked(json, '"deploymentTimestamp": ', vm.toString(info.deploymentTimestamp), ','));
        json = string(abi.encodePacked(json, '"deployer": "', vm.toString(info.deployer), '",'));
        
        // Core contracts
        json = string(abi.encodePacked(json, '"contracts": {'));
        json = string(abi.encodePacked(json, '"oracle": "', vm.toString(info.oracle), '",'));
        json = string(abi.encodePacked(json, '"adapter": "', vm.toString(info.adapter), '",'));
        json = string(abi.encodePacked(json, '"factory": "', vm.toString(info.factory), '",'));
        json = string(abi.encodePacked(json, '"initialVault": "', vm.toString(info.initialVault), '"'));
        json = string(abi.encodePacked(json, '},'));
        
        // Config addresses
        json = string(abi.encodePacked(json, '"config": {'));
        json = string(abi.encodePacked(json, '"usdc": "', vm.toString(info.usdc), '",'));
        json = string(abi.encodePacked(json, '"weth": "', vm.toString(info.weth), '",'));
        json = string(abi.encodePacked(json, '"wrkRewards": "', vm.toString(info.wrkRewards), '"'));
        json = string(abi.encodePacked(json, '},'));
        
        // Allowed assets array
        json = string(abi.encodePacked(json, '"allowedAssets": ['));
        for (uint i = 0; i < info.allowedAssets.length; i++) {
            if (info.allowedAssets[i] != address(0)) {
                json = string(abi.encodePacked(json, '"', vm.toString(info.allowedAssets[i]), '"'));
                if (i < info.allowedAssets.length - 1) {
                    json = string(abi.encodePacked(json, ','));
                }
            }
        }
        json = string(abi.encodePacked(json, '],'));
        
        // Initial vault info
        json = string(abi.encodePacked(json, '"initialVaultConfig": {'));
        
        // Initial vault assets
        json = string(abi.encodePacked(json, '"assets": ['));
        for (uint i = 0; i < info.initialVaultAssets.length; i++) {
            json = string(abi.encodePacked(json, '"', vm.toString(info.initialVaultAssets[i]), '"'));
            if (i < info.initialVaultAssets.length - 1) {
                json = string(abi.encodePacked(json, ','));
            }
        }
        json = string(abi.encodePacked(json, '],'));
        
        // Initial vault weights
        json = string(abi.encodePacked(json, '"weights": ['));
        for (uint i = 0; i < info.initialVaultWeights.length; i++) {
            json = string(abi.encodePacked(json, vm.toString(info.initialVaultWeights[i])));
            if (i < info.initialVaultWeights.length - 1) {
                json = string(abi.encodePacked(json, ','));
            }
        }
        json = string(abi.encodePacked(json, ']'));
        
        json = string(abi.encodePacked(json, '}'));
        json = string(abi.encodePacked(json, '}'));
        
        return json;
    }
} 