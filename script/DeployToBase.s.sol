// script/DeployToBase.s.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/core/WeightedTreasuryVault.sol";
import "../src/core/WhackRockTreasuryFactory.sol";
import "../src/core/interfaces/ISwapAdapter.sol";
import "../src/core/interfaces/IPriceOracle.sol";
import "../src/core/adapters/UniTwapDualOracle.sol";
import "../src/core/adapters/UniAdapter.sol";

/**
 * @title WhackRock Treasury Deployment Script for Base Mainnet
 * @notice Deploys all contracts needed for the WhackRock Treasury protocol on Base Mainnet
 *         and saves deployed addresses to a JSON file
 *
 * Environment variables required (in .env file):
 * - PRIVATE_KEY: Deployer private key (can include 0x prefix)
 * - USDC_ADDRESS: Address of USDC on Base (0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913)
 * - WETH_ADDRESS: Address of WETH on Base (0x4200000000000000000000000000000000000006)
 * - WETH_USDC_POOL: Address of WETH/USDC pool on Base (0xd0b53D9277642d899DF5C87A3966A349A798F224)
 * - UNIVERSAL_ROUTER: Address of Universal Router on Base
 * - WRK_REWARDS_ADDRESS: Address where 20% of fees go
 * - INITIAL_ASSETS: Comma-separated list of initial allowed asset addresses
 * - VIRTUALS_ADDRESS: Address of Virtuals token (0x0b3e328455c4059EEb9e3f84b5543F74E24e7E1b)
 * - VIRTUALS_POOL: Address of Virtuals/WETH V2 pool (0xE31c372a7Af875b3B5E0F3713B17ef51556da667)
 * - BASESCAN_API_KEY: API key for verification on Basescan
 *
 * To deploy:
 * 1. Make sure your .env file is set up with the correct values
 * 2. Run: forge script script/DeployToBase.s.sol:DeployToBaseScript --rpc-url https://mainnet.base.org --broadcast --verify -vvv
 */
contract DeployToBaseScript is Script {
    function run() external {
        // Load configuration from environment variables
        string memory privateKey = vm.envString("PRIVATE_KEY");  // Include the 0x prefix in your .env file
        uint256 deployerPrivateKey = uint256(vm.parseBytes32(privateKey));
        
        address usdcAddress = vm.envAddress("USDC_ADDRESS");
        address wethAddress = vm.envAddress("WETH_ADDRESS");
        address wethUsdcPoolAddress = vm.envAddress("WETH_USDC_POOL");
        address universalRouterAddress = vm.envAddress("UNIVERSAL_ROUTER");
        address wrkRewardsAddress = vm.envAddress("WRK_REWARDS_ADDRESS");
        string memory initialAssetsStr = vm.envString("INITIAL_ASSETS");
        string memory rpcUrl = vm.envString("RPC_URL");
        
        console.log("=== DEPLOYMENT TO BASE MAINNET ===");
        console.log("RPC URL: %s", rpcUrl);
        console.log("USDC Address: %s", usdcAddress);
        console.log("WETH Address: %s", wethAddress);
        
        // Parse the comma-separated list of initial allowed assets
        string[] memory assetStrs = _split(initialAssetsStr, ',');
        address[] memory allowedAssets = new address[](assetStrs.length);
        
        for (uint i = 0; i < assetStrs.length; i++) {
            if (bytes(assetStrs[i]).length > 0) {
                allowedAssets[i] = vm.parseAddress(assetStrs[i]);
                console.log("Allowed asset %d: %s", i, allowedAssets[i]);
            }
        }
        
        // Validate USDC is included in allowed assets
        bool hasUsdc = false;
        for (uint i = 0; i < allowedAssets.length; i++) {
            if (allowedAssets[i] == usdcAddress) {
                hasUsdc = true;
                break;
            }
        }
        
        if (!hasUsdc) {
            console.log("Warning: USDC not found in allowed assets, adding it automatically");
            address[] memory newAllowedAssets = new address[](allowedAssets.length + 1);
            for (uint i = 0; i < allowedAssets.length; i++) {
                newAllowedAssets[i] = allowedAssets[i];
            }
            newAllowedAssets[allowedAssets.length] = usdcAddress;
            allowedAssets = newAllowedAssets;
        }
        
        // Start broadcasting transactions
        vm.startBroadcast(deployerPrivateKey);
        
        // Step 1: Deploy UniTwapDualOracle
        console.log("Deploying UniTwapDualOracle...");
        UniTwapDualOracle oracle = new UniTwapDualOracle(
            usdcAddress, 
            wethAddress,
            wethUsdcPoolAddress
        );
        console.log("UniTwapDualOracle deployed at:", address(oracle));
        
        // // Step 2: Configure Virtuals token to use Uniswap V2 pool
        // console.log("Configuring Virtuals token in oracle...");
        // oracle.setPoolConfig(
        //     virtualsAddress,
        //     virtualsPoolAddress,
        //     true,  // viaWeth - calculate via WETH
        //     true   // isV2 - this is a Uniswap V2 pool
        // );
        // console.log("Virtuals token configured to use V2 pool");
        
        // Step 3: Deploy UniAdapter
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
        
        // Initial vault creation is now skipped per user request
        
        vm.stopBroadcast();
        
        // Print deployment summary with all important information
        console.log("\n=== BASE MAINNET DEPLOYMENT SUMMARY ===");
        console.log("============= CONTRACT ADDRESSES =============");
        console.log("UniTwapDualOracle:         %s", address(oracle));
        console.log("UniAdapter:                %s", address(adapter));
        console.log("WhackRockTreasuryFactory:  %s", address(factory));
        console.log("============= CONFIG ADDRESSES =============");
        console.log("USDC.b:                    %s", usdcAddress);
        console.log("WETH:                      %s", wethAddress);
        console.log("WRK Rewards:               %s", wrkRewardsAddress);
        console.log("============= ALLOWED ASSETS =============");
        for (uint i = 0; i < allowedAssets.length; i++) {
            if (allowedAssets[i] != address(0)) {
                console.log("Asset %d:                  %s", i, allowedAssets[i]);
            }
        }
        console.log("==========================================\n");
        
        console.log("IMPORTANT: Save these addresses as they won't be written to a file!");
        console.log("Next steps:");
        console.log("1. Verify contracts on Basescan");
        console.log("2. Create vaults using the factory");
        console.log("3. Set up frontend to interact with contracts");
        console.log("4. Configure any other token pairs in the oracle using setPoolConfig");
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