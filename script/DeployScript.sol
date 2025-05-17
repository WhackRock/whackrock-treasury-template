// script/Deploy.s.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/core/WeightedTreasuryVault.sol";
import "../src/core/WhackRockTreasuryFactory.sol";
import "../src/core/interfaces/ISwapAdapter.sol";
import "../src/core/interfaces/IPriceOracle.sol";
import "../src/core/adapters/UniTwapOracle.sol";
import "../src/core/adapters/UniAdapter.sol";

/**
 * @title WhackRock Treasury Deployment Script
 * @notice Deploys all contracts needed for the WhackRock Treasury protocol
 *
 * Environment variables required:
 * - PRIVATE_KEY: Deployer private key
 * - USDC_ADDRESS: Address of USDC.b token
 * - WETH_ADDRESS: Address of WETH token
 * - UNISWAP_V3_FACTORY: Address of Uniswap V3 Factory
 * - WETH_USDC_POOL: Address of WETH/USDC pool (for oracle)
 * - UNIVERSAL_ROUTER: Address of Universal Router
 * - WRK_REWARDS_ADDRESS: Address where 20% of fees go
 * - INITIAL_ASSETS: Comma-separated list of initial allowed asset addresses
 */
contract DeployScript is Script {
    function run() external {
        // Load configuration from environment variables
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address usdcAddress = vm.envAddress("USDC_ADDRESS");
        address wethAddress = vm.envAddress("WETH_ADDRESS");
        address wethUsdcPoolAddress = vm.envAddress("WETH_USDC_POOL");
        address universalRouterAddress = vm.envAddress("UNIVERSAL_ROUTER");
        address wrkRewardsAddress = vm.envAddress("WRK_REWARDS_ADDRESS");
        string memory initialAssetsStr = vm.envString("INITIAL_ASSETS");

        // Parse the comma-separated list of initial allowed assets
        string[] memory assetStrs = _split(initialAssetsStr, ',');
        address[] memory allowedAssets = new address[](assetStrs.length);
        
        for (uint i = 0; i < assetStrs.length; i++) {
            allowedAssets[i] = vm.parseAddress(assetStrs[i]);
            console.log("Allowed asset %d: %s", i, allowedAssets[i]);
        }
        
        // Validate USDC is included in allowed assets
        bool hasUsdc = false;
        for (uint i = 0; i < allowedAssets.length; i++) {
            if (allowedAssets[i] == usdcAddress) {
                hasUsdc = true;
                break;
            }
        }
        require(hasUsdc, "USDC must be in allowed assets list");
        
        // Start broadcasting transactions
        vm.startBroadcast(deployerPrivateKey);
        
        // Step 1: Deploy UniTwapOracle
        console.log("Deploying UniTwapOracle...");
        UniTwapOracle oracle = new UniTwapOracle(
            usdcAddress, 
            wethAddress,
            wethUsdcPoolAddress
        );
        console.log("UniTwapOracle deployed at:", address(oracle));
        
        // Step 2: Deploy UniAdapter
        console.log("Deploying UniAdapter...");
        UniAdapter adapter = new UniAdapter(universalRouterAddress);
        console.log("UniAdapter deployed at:", address(adapter));
                
        // Step 4: Deploy the WhackRockTreasuryFactory
        console.log("Deploying WhackRockTreasuryFactory...");
        WhackRockTreasuryFactory factory = new WhackRockTreasuryFactory(
            usdcAddress,
            allowedAssets,
            adapter,
            oracle,
            wrkRewardsAddress
        );
        console.log("WhackRockTreasuryFactory deployed at:", address(factory));
        
        // Step 5 (Optional): Create an initial vault
        console.log("Creating initial vault...");
        
        // Define initial weights for each asset (must total 10000 = 100%)
        uint256[] memory initialWeights = new uint256[](allowedAssets.length);
        
        // Set equal weights for simplicity, ensuring they sum to 10000 (100%)
        uint256 equalWeight = 10000 / allowedAssets.length;
        uint256 weightSum = 0;
        
        for (uint i = 0; i < allowedAssets.length - 1; i++) {
            initialWeights[i] = equalWeight;
            weightSum += equalWeight;
        }
        
        // Assign remaining weight to the last asset to ensure they sum to exactly 10000
        initialWeights[allowedAssets.length - 1] = 10000 - weightSum;
        
        // Create the vault through the factory
        address[] memory vaultAssets = new address[](3);
        // Use a subset of assets for the first vault
        vaultAssets[0] = wethAddress;  // WETH (assuming it's in the allowed assets)
        vaultAssets[1] = usdcAddress;  // USDC
        vaultAssets[2] = allowedAssets[allowedAssets.length > 2 ? 2 : 0];  // Third asset or fallback
        
        uint256[] memory vaultWeights = new uint256[](3);
        vaultWeights[0] = 5000;  // 50% WETH
        vaultWeights[1] = 3000;  // 30% USDC
        vaultWeights[2] = 2000;  // 20% Third asset
        
        // Create the vault
        address initialVault = factory.createVault(
            "WhackRock Treasury Alpha", 
            "WRTA",
            vaultAssets,
            vaultWeights,
            msg.sender,  // Deployer as manager
            200,         // 2% management fee
            msg.sender,  // Deployer as dev wallet initially
            "ALPHA"      // Tag for indexers
        );
        console.log("Initial vault created at:", initialVault);
        
        vm.stopBroadcast();
        
        // Print deployment summary
        console.log("\n=== DEPLOYMENT SUMMARY ===");
        console.log("UniTwapOracle: %s", address(oracle));
        console.log("UniAdapter: %s", address(adapter));
        
        console.log("WhackRockTreasuryFactory: %s", address(factory));
        console.log("Initial Vault: %s", initialVault);
        console.log("==========================\n");
        
        console.log("Next steps:");
        console.log("1. Configure the GAME-Python plugin to interact with the factory and vaults");
        console.log("2. Set up the frontend to allow creating and managing vaults");
        console.log("3. Verify contracts on Etherscan or Basescan");
    }
    
    /**
     * @dev Helper function to split a string by delimiter
     * @param str String to split
     * @param delimiter Character to split by
     * @return String array of split parts
     */
    function _split(string memory str, bytes1 delimiter) internal pure returns (string[] memory) {
        // Count delimiters to determine array size
        uint count = 1;
        for (uint i = 0; i < bytes(str).length; i++) {
            if (bytes(str)[i] == delimiter) {
                count++;
            }
        }
        
        // Create result array
        string[] memory result = new string[](count);
        
        // Split the string
        count = 0;
        uint lastIndex = 0;
        for (uint i = 0; i < bytes(str).length; i++) {
            if (bytes(str)[i] == delimiter) {
                result[count] = _substring(str, lastIndex, i);
                lastIndex = i + 1;
                count++;
            }
        }
        
        // Add the last part
        result[count] = _substring(str, lastIndex, bytes(str).length);
        
        return result;
    }
    
    /**
     * @dev Helper function to extract a substring
     * @param str Source string
     * @param startIndex Start index (inclusive)
     * @param endIndex End index (exclusive)
     * @return Substring
     */
    function _substring(string memory str, uint startIndex, uint endIndex) internal pure returns (string memory) {
        bytes memory strBytes = bytes(str);
        bytes memory result = new bytes(endIndex - startIndex);
        for (uint i = startIndex; i < endIndex; i++) {
            result[i - startIndex] = strBytes[i];
        }
        return string(result);
    }
}