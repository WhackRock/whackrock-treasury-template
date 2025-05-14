// test/WeightedTreasuryVault.t.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/WeightedTreasuryVault.sol";
import "./mocks/MockERC20.sol";

contract WeightedTreasuryVaultTest is Test {
    WeightedTreasuryVault public vault;
    MockERC20 public usdc;
    MockERC20 public eth;
    address public owner;
    address public user;

    function setUp() public {
        owner = address(this);
        user = address(0x1);

        // Deploy mock tokens
        usdc = new MockERC20("Mock USDC", "mUSDC", 6);
        eth = new MockERC20("Mock ETH", "mETH", 18);

        // Deploy vault
        vault = new WeightedTreasuryVault(
            address(0), // Uniswap factory address (mock for now)
            owner
        );

        // Transfer some tokens to user
        usdc.transfer(user, 1000 * 10**6);
        eth.transfer(user, 10 * 10**18);
    }

    function test_Initialization() public {
        assertEq(vault.owner(), owner);
    }

    function test_SetWeights() public {
        uint256[] memory weights = new uint256[](2);
        weights[0] = 7000; // 70%
        weights[1] = 3000; // 30%

        vault.setWeights(weights);

        uint256[] memory currentWeights = vault.targetWeights();
        assertEq(currentWeights[0], 7000);
        assertEq(currentWeights[1], 3000);
    }

    function test_Rebalance() public {
        // First set weights
        uint256[] memory weights = new uint256[](2);
        weights[0] = 7000;
        weights[1] = 3000;
        vault.setWeights(weights);

        // Prepare rebalance data
        bytes memory rebalanceData = abi.encode(
            address(usdc),
            address(eth),
            1000 * 10**6, // 1000 USDC
            1 * 10**18    // 1 ETH
        );

        // Execute rebalance
        vault.rebalance(rebalanceData);
    }

    function testFail_SetWeightsNotOwner() public {
        uint256[] memory weights = new uint256[](2);
        weights[0] = 7000;
        weights[1] = 3000;

        vm.prank(user);
        vault.setWeights(weights); // Should fail
    }
}