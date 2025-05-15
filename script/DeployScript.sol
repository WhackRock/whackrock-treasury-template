// script/Deploy.s.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/core/WeightedTreasuryVault.sol";
import "../src/core/interfaces/ISwapAdapter.sol";
import "../src/core/interfaces/IPriceOracle.sol";

contract DeployScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address usdcAddress = vm.envAddress("USDC_ADDRESS");
        address adapterAddress = vm.envAddress("ADAPTER_ADDRESS");
        address oracleAddress = vm.envAddress("ORACLE_ADDRESS");
        address wrkRewardsAddress = vm.envAddress("WRK_REWARDS_ADDRESS");
        uint16 mgmtFeeBps = uint16(vm.envUint("MGMT_FEE_BPS"));
        
        vm.startBroadcast(deployerPrivateKey);

        // Initialize allowed assets and weights 
        // This example uses 2 assets: ETH and USDC
        IERC20[] memory allowedAssets = new IERC20[](2);
        allowedAssets[0] = IERC20(address(0)); // ETH
        allowedAssets[1] = IERC20(usdcAddress); // USDC
        
        uint256[] memory weights = new uint256[](2);
        weights[0] = 5000; // 50% ETH
        weights[1] = 5000; // 50% USDC
        
        // Deploy vault
        WeightedTreasuryVault vault = new WeightedTreasuryVault(
            "WhackRock Treasury", // name
            "WRTR",               // symbol
            usdcAddress,          // USDC.b address
            allowedAssets,        // allowed assets
            weights,              // initial weights
            msg.sender,           // manager
            ISwapAdapter(adapterAddress), // swap adapter
            IPriceOracle(oracleAddress),  // price oracle
            mgmtFeeBps,           // management fee basis points
            msg.sender,           // dev wallet (initially same as manager)
            wrkRewardsAddress     // WRK rewards address
        );

        vm.stopBroadcast();
        
        console.log("Vault deployed at:", address(vault));
    }
}