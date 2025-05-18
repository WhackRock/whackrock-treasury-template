// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// import "forge-std/Script.sol";
// import "forge-std/console.sol";
// import "../src/core/WeightedTreasuryVault.sol";
// import "../src/core/TreasuryFactory.sol";
// import "../src/core/interfaces/ISwapAdapter.sol";
// import "../src/core/interfaces/IPriceOracle.sol";
// import "../src/core/adapters/UniTwapOracle.sol";
// import "../src/core/adapters/UniAdapter.sol";

/**
 * @title Sepolia Deployment Script
 * @notice This script deploys the WhackRock Treasury contracts to Sepolia testnet
 * 
 * To run:
 * 1. Create a .env file with:
 *    - PRIVATE_KEY=your_private_key
 *    - SEPOLIA_RPC_URL=your_rpc_url
 * 
 * 2. Run the deployment:
 *    forge script script/DeploySepolia.s.sol:DeploySepoliaScript --rpc-url sepolia --broadcast --verify
 */
// contract DeploySepoliaScript is Script {
contract DeploySepoliaScript  {
    // // Sepolia Addresses
    // address constant SEPOLIA_WETH = 0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9;
    // address constant SEPOLIA_USDC = 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238; // Example Sepolia USDC
    // address constant SEPOLIA_WBTC = 0xFF82bB6DB46Ad45F017e2Dfb478102C7D9a69397; // Example Sepolia WBTC
    // address constant SEPOLIA_FACTORY_V3 = 0x0227628f3F023bb0B980b67D528571c95c6DaC1c; // Sepolia Uniswap V3 Factory

    // // Fee tiers for init
    // uint24 constant FEE_TIER_3000 = 3000; // 0.3%

    // function run() external {
    //     uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
    //     // Start broadcasting transactions
    //     vm.startBroadcast(deployerPrivateKey);
        
    //     // Deploy UniswapV3 TWAP Oracle
    //     console.log("Deploying Oracle...");
    //     UniTwapOracle oracle = new UniTwapOracle(
    //         SEPOLIA_FACTORY_V3, 
    //         SEPOLIA_WETH, 
    //         SEPOLIA_USDC
    //     );
    //     console.log("Oracle deployed at:", address(oracle));
        
    //     // Deploy Uniswap Adapter
    //     console.log("Deploying UniAdapter...");
    //     UniAdapter adapter = new UniAdapter();
    //     console.log("UniAdapter deployed at:", address(adapter));
        
    //     // Setup tokens for the treasury
    //     console.log("Setting up allowed assets...");
    //     address[] memory allowedAssetAddresses = new address[](3);
    //     allowedAssetAddresses[0] = SEPOLIA_WETH;  // WETH
    //     allowedAssetAddresses[1] = SEPOLIA_WBTC;  // WBTC
    //     allowedAssetAddresses[2] = SEPOLIA_USDC;  // USDC
        
    //     // Deploy empty treasury vault as implementation
    //     console.log("Deploying Treasury Vault implementation...");
    //     WeightedTreasuryVault vaultImpl = new WeightedTreasuryVault(
    //         "IMPL DO NOT USE", 
    //         "IMPL",
    //         SEPOLIA_USDC,
    //         new IERC20[](0),
    //         new uint256[](0),
    //         address(0),
    //         ISwapAdapter(address(0)),
    //         IPriceOracle(address(0)),
    //         0,
    //         address(0),
    //         address(0)
    //     );
    //     console.log("Vault implementation deployed at:", address(vaultImpl));
        
    //     // Set the rewards address to 20% of the fees
    //     address wrkRewards = msg.sender; // For testing, set to deployer
        
    //     // Deploy factory
    //     console.log("Deploying TreasuryFactory...");
    //     TreasuryFactory factory = new TreasuryFactory(
    //         address(vaultImpl),
    //         SEPOLIA_USDC,
    //         allowedAssetAddresses,
    //         adapter,
    //         oracle,
    //         wrkRewards
    //     );
    //     console.log("TreasuryFactory deployed at:", address(factory));
        
    //     // Create initial vault through factory with sample weights
    //     console.log("Creating sample vault...");
    //     uint256[] memory weights = new uint256[](3);
    //     weights[0] = 5000; // 50% WETH
    //     weights[1] = 2000; // 20% WBTC
    //     weights[2] = 3000; // 30% USDC
        
    //     address sampleVault = factory.createVault(
    //         "WhackRock Sample Treasury",
    //         "WRST",
    //         weights,
    //         msg.sender, // manager (deployer)
    //         200, // 2% management fee
    //         msg.sender, // dev wallet (deployer for testing)
    //         "AGENT" // tag
    //     );
    //     console.log("Sample vault created at:", sampleVault);
        
    //     vm.stopBroadcast();
        
    //     // Summary 
    //     console.log("\n=== DEPLOYMENT SUMMARY ===");
    //     console.log("Network: Sepolia");
    //     console.log("Oracle:", address(oracle));
    //     console.log("UniAdapter:", address(adapter));
    //     console.log("Vault Implementation:", address(vaultImpl));
    //     console.log("Treasury Factory:", address(factory));
    //     console.log("Sample Vault:", sampleVault);
    //     console.log("========================");
        
    //     console.log("\nDeployment complete! Next steps:");
    //     console.log("1. Set up the frontend to interact with the factory");
    //     console.log("2. Configure the game-python plugin to manage the sample vault");
    // }
} 