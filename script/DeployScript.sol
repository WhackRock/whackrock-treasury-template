// script/Deploy.s.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/WeightedTreasuryVault.sol";

contract DeployScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Deploy vault
        WeightedTreasuryVault vault = new WeightedTreasuryVault(
            address(0), // Uniswap factory address
            msg.sender  // Initial owner
        );

        vm.stopBroadcast();
    }
}