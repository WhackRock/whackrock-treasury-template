// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {WhackRockFundRegistry} from "../src/factory/WhackRockFundRegistry.sol";

contract UpdateProtocolCreationFee is Script {
    
    // Registry proxy address on Base (update this with your deployed registry address)
    address constant REGISTRY_PROXY_ADDRESS = 0x0000000000000000000000000000000000000000; // REPLACE WITH ACTUAL ADDRESS
    
    // New protocol creation fee: 170 USDC (assuming 6 decimals for USDC)
    uint256 constant NEW_PROTOCOL_CREATION_FEE_USDC = 170 * 1e6; // 170 USDC
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);
        
        console.log("Deployer Address:", deployerAddress);
        console.log("Registry Proxy Address:", REGISTRY_PROXY_ADDRESS);
        
        // Get the registry instance
        WhackRockFundRegistry registry = WhackRockFundRegistry(payable(REGISTRY_PROXY_ADDRESS));
        
        // Get current parameters before update
        console.log("--- Current Registry Parameters ---");
        console.log("Current Protocol Creation Fee:", registry.protocolFundCreationFeeUsdcAmount());
        console.log("USDC Token Address:", address(registry.USDC_TOKEN()));
        console.log("WhackRock Rewards Address:", registry.whackRockRewardsAddress());
        console.log("Total AUM Fee BPS:", registry.totalAumFeeBpsForFunds());
        console.log("Protocol AUM Fee Recipient:", registry.protocolAumFeeRecipientForFunds());
        console.log("Max Agent Deposit Fee BPS:", registry.maxAgentDepositFeeBps());
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Update the registry parameters, only changing the protocol creation fee
        registry.updateRegistryParameters(
            address(registry.USDC_TOKEN()),                    // Keep current USDC address
            registry.whackRockRewardsAddress(),               // Keep current rewards address
            NEW_PROTOCOL_CREATION_FEE_USDC,                   // NEW: Set to 170 USDC
            registry.totalAumFeeBpsForFunds(),                // Keep current AUM fee BPS
            registry.protocolAumFeeRecipientForFunds(),       // Keep current AUM recipient
            registry.maxAgentDepositFeeBps()                  // Keep current max agent deposit fee
        );
        
        vm.stopBroadcast();
        
        console.log("--- Updated Registry Parameters ---");
        console.log("New Protocol Creation Fee:", registry.protocolFundCreationFeeUsdcAmount());
        console.log("Protocol Creation Fee Update: SUCCESS");
        console.log("New fee amount: 170 USDC");
    }
}