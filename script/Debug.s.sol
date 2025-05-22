// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

/*───────────────────────────────────────────────────────────────────────────*\
│  IMPORTS                                                                  │
\*───────────────────────────────────────────────────────────────────────────*/
import "forge-std/Script.sol";
import "forge-std/console.sol";

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IWeightedTreasuryVault} from
        "../src/core/interfaces/IWeightedTreasuryVault.sol"; // ← adjust path

/*───────────────────────────────────────────────────────────────────────────*\
│  SCRIPT                                                                    │
\*───────────────────────────────────────────────────────────────────────────*/
contract Debug is Script {
    /*~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~*/
    /*  CONFIG  – edit or override via CLI flags / env vars                 */
    /*~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~*/

    /// vault you want to poke
    address constant VAULT = 0x90cfB07A46EE4bb20C970Dda18AaD1BA3c9450Ae; // <-- put real address here

    /// USDC (6 decimals) on Base mainnet
    address constant USDC  =
        0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;

    /// who will send the tx (must be unlocked in anvil)
    address constant EOA   = 0x90cfB07A46EE4bb20C970Dda18AaD1BA3c9450Ae;  // <-- same address you unlocked

    /// deposit amount (1 USDC)
    uint256 constant AMOUNT = 1e6;

    /*~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~*/
    /*  ENTRY POINT                                                         */
    /*~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~*/

    function run() external {
        /*----------  load private key (optional) ----------*/
        /*
            If you use `--private-key $PK` on forge script, you don’t need
            vm.envUint.  For a local fork you can just impersonate.
        */
        uint256 pk = vm.envOr("PK", uint256(0));
        if (pk != 0) {
            vm.startBroadcast(pk);
        } else {
            vm.startBroadcast();
            vm.prank(EOA); // if you only unlocked the EOA
        }

        /*----------  set up contracts ----------*/
        IWeightedTreasuryVault vault = IWeightedTreasuryVault(VAULT);
        IERC20 usdc                 = IERC20(USDC);

        // console.log("=== PRE-STATE ===");
        // console.log("vault totalAssets:", vault.totalAssets());
        // console.log("shares totalSupply:", vault.totalSupply());
        // console.log("EOA USDC bal:", usdc.balanceOf(EOA));

        // /*----------  approve & deposit ----------*/
        // // 1. approve
        // usdc.approve(VAULT, AMOUNT);

        // // 2. deposit
        // uint256 shares =
        //     vault.deposit(AMOUNT, EOA);
        // console.log("minted shares:", shares);

        // /*----------  post-state ----------*/
        // console.log("=== POST-STATE ===");
        // console.log("vault totalAssets:", vault.totalAssets());
        // console.log("shares totalSupply:", vault.totalSupply());
        // console.log("EOA share bal:", vault.balanceOf(EOA));

        // vm.stopBroadcast();
    }
}
