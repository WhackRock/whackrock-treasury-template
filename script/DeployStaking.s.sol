// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {WhackRockStaking} from "../src/staking/WhackRockStaking.sol";
import {PointsRedeemer} from "../src/staking/PointsRedeemer.sol";
import {TestToken} from "../src/mocks/TestToken.sol";

contract DeployStaking is Script {
    function run() external {
        // Get private key from environment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("=== WROCK Staking Deployment ===");
        console.log("Deployer Address:", deployer);
        console.log("Chain ID:", block.chainid);
        console.log("");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy TEST token
        console.log("Deploying TEST token...");
        TestToken testToken = new TestToken();
        console.log("TEST token deployed at:", address(testToken));

        // Mint 100000 ETH worth of TEST tokens to deployer
        uint256 mintAmount = 100000 ether;
        console.log("Minting", mintAmount / 1e18, "TEST tokens to deployer...");
        testToken.mint(deployer, mintAmount);
        console.log("Minted successfully!");

        // Deploy WhackRockStaking contract
        console.log("Deploying WhackRockStaking...");
        WhackRockStaking stakingContract = new WhackRockStaking(address(testToken));
        console.log("WhackRockStaking deployed at:", address(stakingContract));

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
        console.log("TEST Token:", address(testToken));
        console.log("WhackRockStaking:", address(stakingContract));
        console.log("PointsRedeemer:", address(redeemer));
        console.log("Redeemer setup queued (48hr timelock)");
        console.log("");
        console.log("=== Token Info ===");
        console.log("TEST tokens minted to deployer:", mintAmount / 1e18);
        console.log("");
        console.log("=== Next Steps ===");
        console.log("1. Wait 48 hours for timelock");
        console.log("2. Execute the queued operation:");
        console.log("   stakingContract.executeSetPointsRedeemer(redeemerAddress)");
        console.log("3. Configure reward token in PointsRedeemer");
        console.log("4. Enable redemption when ready");
        console.log("");
        console.log("=== Contract Verification ===");
        console.log("TestToken: No constructor args");
        console.log("");
        console.log("WhackRockStaking constructor args:");
        console.log("- stakingToken:", address(testToken));
        console.log("");
        console.log("PointsRedeemer constructor args:");
        console.log("- stakingContract:", address(stakingContract));
    }
}
