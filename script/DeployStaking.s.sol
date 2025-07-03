// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {WROCKStaking} from "../src/staking/WROCKStaking.sol";
import {PointsRedeemer} from "../src/staking/PointsRedeemer.sol";

contract DeployStaking is Script {
    // Configuration constants
    address constant WROCK_TOKEN = 0x2626664c2603336E57B271c5C0b26F421741e481; // Replace with actual WROCK token address
    
    function run() external {
        // Get private key from environment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("=== WROCK Staking Deployment ===");
        console.log("Deployer Address:", deployer);
        console.log("Chain ID:", block.chainid);
        console.log("WROCK Token Address:", WROCK_TOKEN);
        console.log("");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy WROCKStaking contract
        console.log("Deploying WROCKStaking...");
        WROCKStaking stakingContract = new WROCKStaking(WROCK_TOKEN);
        console.log("WROCKStaking deployed at:", address(stakingContract));
        
        // Deploy PointsRedeemer contract
        console.log("Deploying PointsRedeemer...");
        PointsRedeemer redeemer = new PointsRedeemer(address(stakingContract));
        console.log("PointsRedeemer deployed at:", address(redeemer));
        
        // Set the redeemer in the staking contract
        console.log("Setting redeemer in staking contract...");
        
        // Queue the operation (timelock required)
        stakingContract.queueSetPointsRedeemer(address(redeemer));
        console.log("Queued setPointsRedeemer operation");
        console.log("Operation will be executable after 48 hours");
        
        vm.stopBroadcast();
        
        console.log("");
        console.log("=== Deployment Summary ===");
        console.log("WROCKStaking:", address(stakingContract));
        console.log("PointsRedeemer:", address(redeemer));
        console.log("Redeemer setup queued (48hr timelock)");
        console.log("");
        console.log("=== Next Steps ===");
        console.log("1. Wait 48 hours for timelock");
        console.log("2. Execute the queued operation:");
        console.log("   stakingContract.executeSetPointsRedeemer(redeemerAddress)");
        console.log("3. Configure reward token in PointsRedeemer");
        console.log("4. Enable redemption when ready");
        console.log("");
        console.log("=== Contract Verification ===");
        console.log("WROCKStaking constructor args:");
        console.log("- stakingToken:", WROCK_TOKEN);
        console.log("");
        console.log("PointsRedeemer constructor args:");
        console.log("- stakingContract:", address(stakingContract));
    }
}