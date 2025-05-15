// test/WeightedTreasuryVault.t.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/core/WeightedTreasuryVault.sol";
import "../src/core/interfaces/ISwapAdapter.sol";
import "../src/core/interfaces/IPriceOracle.sol";
import "./mocks/MockERC20.sol";
import "./mocks/MockSwapAdapter.sol";
import "./mocks/MockPriceOracle.sol";

contract WeightedTreasuryVaultTest is Test {
    WeightedTreasuryVault public vault;
    MockERC20 public usdc;
    MockERC20 public eth;
    MockERC20 public btc;
    MockSwapAdapter public adapter;
    MockPriceOracle public oracle;
    address public manager;
    address public devWallet;
    address public wrkRewards;
    address public user;

    function setUp() public {
        manager = address(this);
        devWallet = address(0xDEAD);
        wrkRewards = address(0xBEEF);
        user = address(0x1);

        // Deploy mock tokens
        usdc = new MockERC20("USDC", "USDC", 6);
        eth = new MockERC20("ETH", "ETH", 18);
        btc = new MockERC20("BTC", "BTC", 8);

        // Deploy mock adapter and oracle
        adapter = new MockSwapAdapter();
        oracle = new MockPriceOracle();

        // Set up test prices
        oracle.setPrice(address(0), 2000 * 10**18); // ETH price = $2000
        oracle.setPrice(address(usdc), 1 * 10**18);  // USDC price = $1
        oracle.setPrice(address(btc), 60000 * 10**18); // BTC price = $60000

        // Create allowed assets array
        IERC20[] memory allowedTokens = new IERC20[](3);
        allowedTokens[0] = IERC20(address(eth));
        allowedTokens[1] = IERC20(address(btc)); 
        allowedTokens[2] = IERC20(address(usdc));

        // Create initial weights array (40% ETH, 30% BTC, 30% USDC)
        uint256[] memory initialWeights = new uint256[](3);
        initialWeights[0] = 4000; // 40%
        initialWeights[1] = 3000; // 30%
        initialWeights[2] = 3000; // 30%

        // Deploy vault
        vault = new WeightedTreasuryVault(
            "WhackRock Treasury",      // name
            "WRTR",                    // symbol
            address(usdc),             // USDC as base asset
            allowedTokens,             // allowed assets
            initialWeights,            // initial weights
            manager,                   // manager
            ISwapAdapter(address(adapter)), // Cast to ISwapAdapter
            IPriceOracle(address(oracle)), // Cast to IPriceOracle
            200,                       // 2% management fee
            devWallet,                 // dev wallet
            wrkRewards                 // WRK rewards
        );

        // Transfer some tokens to user
        usdc.mint(user, 10000 * 10**6);  // 10,000 USDC
        eth.mint(user, 10 * 10**18);     // 10 ETH
        btc.mint(user, 1 * 10**8);       // 1 BTC
        
        // Approve vault to spend user tokens
        vm.startPrank(user);
        usdc.approve(address(vault), type(uint256).max);
        eth.approve(address(vault), type(uint256).max);
        btc.approve(address(vault), type(uint256).max);
        vm.stopPrank();
    }

    function test__Initialization() public {
        assertEq(vault.manager(), manager);
        assertEq(vault.devWallet(), devWallet);
        assertEq(vault.wrkRewards(), wrkRewards);
        assertEq(vault.USDCb(), address(usdc));
        assertEq(vault.mgmtFeeBps(), 200);

        // Check initial weights
        assertEq(vault.targetWeights(0), 4000);
        assertEq(vault.targetWeights(1), 3000);
        assertEq(vault.targetWeights(2), 3000);
    }

    function test__SetWeights() public {
        // Create new weights array (50% ETH, 20% BTC, 30% USDC)
        uint256[] memory newWeights = new uint256[](3);
        newWeights[0] = 5000; // 50%
        newWeights[1] = 2000; // 20%
        newWeights[2] = 3000; // 30%

        vault.setWeights(newWeights);

        // Check updated weights
        assertEq(vault.targetWeights(0), 5000);
        assertEq(vault.targetWeights(1), 2000);
        assertEq(vault.targetWeights(2), 3000);
    }

    function test__Deposit() public {
        uint256 depositAmount = 1000 * 10**6; // 1000 USDC
        
        vm.startPrank(user);
        uint256 shares = vault.deposit(depositAmount, user);
        vm.stopPrank();

        assertGt(shares, 0, "Should receive shares");
        assertEq(usdc.balanceOf(address(vault)), depositAmount, "Vault should have received USDC");
        assertEq(vault.balanceOf(user), shares, "User should have shares");
    }

    function test__DepositWithFee() public {
        uint256 depositAmount = 1000 * 10**6; // 1000 USDC
        
        vm.startPrank(user);
        uint256 shares = vault.deposit(depositAmount, user);
        vm.stopPrank();

        // With 2% fee, user should get 98% of shares
        uint256 feeBps = vault.mgmtFeeBps();
        assertEq(feeBps, 200, "Fee should be 2%");

        // Check dev wallet and rewards received their portions
        uint256 grossShares = shares * 10000 / (10000 - feeBps);
        uint256 feeShares = grossShares - shares;
        uint256 devShares = feeShares * 8000 / 10000; // 80% to dev
        uint256 rewardShares = feeShares - devShares; // 20% to rewards

        assertApproxEqRel(vault.balanceOf(devWallet), devShares, 1e16, "Dev wallet should get 80% of fee"); // 1% tolerance
        assertApproxEqRel(vault.balanceOf(wrkRewards), rewardShares, 1e16, "Rewards should get 20% of fee"); // 1% tolerance
    }

    function test__SetDevWallet() public {
        address newDevWallet = address(0xCAFE);
        
        vault.setDevWallet(newDevWallet);
        
        assertEq(vault.devWallet(), newDevWallet, "Dev wallet should be updated");
    }

    function test_RevertSetWeightsNotManager() public {
        uint256[] memory weights = new uint256[](3);
        weights[0] = 5000;
        weights[1] = 2000;
        weights[2] = 3000;

        vault.setWeights(weights); // Should fail because only manager can set weights
    }
}