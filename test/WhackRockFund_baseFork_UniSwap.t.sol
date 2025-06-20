// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";

// Import our Uniswap V3 contracts
import {WhackRockFund} from "../src/WhackRockFundV6_UniSwap_TWAP.sol";
import {UniswapV3TWAPOracle} from "../src/UniswapV3TWAPOracle.sol";
import {IUniswapV3Router, IUniswapV3Quoter} from "../src/interfaces/IUniswapV3Router.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {IQuoterV2} from "@uniswap/v3-periphery/contracts/interfaces/IQuoterV2.sol";
import {IMulticall} from "@uniswap/v3-periphery/contracts/interfaces/IMulticall.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// --- Base Mainnet Addresses ---
// Uniswap V3 Core Addresses on Base
address constant UNISWAP_V3_FACTORY_BASE = 0x33128a8fC17869897dcE68Ed026d694621f6FDfD;
address constant UNISWAP_V3_ROUTER_BASE = 0x2626664c2603336E57B271c5C0b26F421741e481; // SwapRouter02 (official)
address constant UNIVERSAL_ROUTER_BASE = 0x6fF5693b99212Da76ad316178A184AB56D299b43; // UniversalRouter (preferred)
address constant UNISWAP_V3_QUOTER_BASE = 0x3d4e44Eb1374240CE5F1B871ab261CD16335B76a;

// Token addresses on Base
address constant WETH_ADDRESS_BASE = 0x4200000000000000000000000000000000000006;
address constant USDC_BASE = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
address constant CBBTC_BASE = 0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf;
address constant RETH_BASE = 0xB6fe221Fe9EeF5aBa221c348bA20A1Bf5e73624c;
address constant VIRTUAL_BASE = 0x0b3e328455c4059EEb9e3f84b5543F74E24e7E1b;
address constant DAI_BASE = 0x50c5725949A6F0c72E6C4a641F24049A917DB0Cb;

// Specific Uniswap V3 Pool Addresses on Base
address constant WETH_USDC_POOL = 0xd0b53D9277642d899DF5C87A3966A349A798F224;
address constant WETH_RETH_POOL = 0x9e13996A9f5a9870C105D7e3C311848273740e98;
address constant WETH_CBBTC_POOL = 0x7AeA2E8A3843516afa07293a10Ac8E49906dabD1;
address constant WETH_VIRTUAL_POOL = 0x9c087Eb773291e50CF6c6a90ef0F4500e349B903;

// Test accounts
address constant FUND_OWNER = address(0x1000);
address constant FUND_AGENT = address(0x2000);
address constant DEPOSITOR_1 = address(0x3000);
address constant DEPOSITOR_2 = address(0x4000);
address constant AGENT_FEE_WALLET = address(0x5000);
address constant PROTOCOL_FEE_RECIPIENT = address(0x6000);

// Fund parameters
uint256 constant AGENT_AUM_FEE_BPS = 100; // 1% annual AUM fee
uint256 constant TWAP_PERIOD = 900; // 15 minutes

contract WhackRockFundUniswapTest is Test {
    using SafeERC20 for IERC20;

    WhackRockFund public fund;
    UniswapV3TWAPOracle public oracle;
    ISwapRouter public uniswapRouter;
    IUniswapV3Quoter public uniswapQuoter;
    
    IERC20 public weth;
    IERC20 public usdc;
    IERC20 public cbbtc;
    IERC20 public reth;
    IERC20 public virtuals;
    IERC20 public dai;

    // Test fund configuration
    address[] public allowedTokens;
    uint256[] public targetWeights;

    function setUp() public {
        // Initialize token contracts
        weth = IERC20(WETH_ADDRESS_BASE);
        usdc = IERC20(USDC_BASE);
        cbbtc = IERC20(CBBTC_BASE);
        reth = IERC20(RETH_BASE);
        virtuals = IERC20(VIRTUAL_BASE);
        dai = IERC20(DAI_BASE);

        uniswapRouter = ISwapRouter(UNISWAP_V3_ROUTER_BASE);
        uniswapQuoter = IUniswapV3Quoter(UNISWAP_V3_QUOTER_BASE);

        // Setup test fund configuration with tokens that have specific pools
        allowedTokens = new address[](4);
        allowedTokens[0] = USDC_BASE;
        allowedTokens[1] = CBBTC_BASE;
        allowedTokens[2] = RETH_BASE;
        allowedTokens[3] = VIRTUAL_BASE;

        targetWeights = new uint256[](4);
        targetWeights[0] = 4000; // 40% USDC
        targetWeights[1] = 2500; // 25% CBBTC
        targetWeights[2] = 2500; // 25% rETH
        targetWeights[3] = 1000; // 10% VIRTUAL

        // Deploy the fund
        fund = new WhackRockFund(
            FUND_OWNER,
            FUND_AGENT,
            UNISWAP_V3_ROUTER_BASE,
            UNISWAP_V3_QUOTER_BASE,
            UNISWAP_V3_FACTORY_BASE,
            WETH_ADDRESS_BASE,
            allowedTokens,
            targetWeights,
            "Test Uniswap Fund",
            "TUF",
            "https://test.uri",
            AGENT_FEE_WALLET,
            AGENT_AUM_FEE_BPS,
            PROTOCOL_FEE_RECIPIENT,
            USDC_BASE,
            ""
        );

        // Ensure fund starts with 0 WETH (remove any automatic funding)
        deal(WETH_ADDRESS_BASE, address(fund), 0);
        
        // Debug: Check fund balance after deal
        console.log("Fund WETH balance after deal(0):", weth.balanceOf(address(fund)));
        console.log("Fund ETH balance after deal(0):", address(fund).balance);
        
        // Deal tokens to test accounts
        deal(WETH_ADDRESS_BASE, DEPOSITOR_1, 100 ether);
        deal(WETH_ADDRESS_BASE, DEPOSITOR_2, 50 ether);
        deal(USDC_BASE, DEPOSITOR_1, 100000 * 1e6); // 100k USDC
        deal(CBBTC_BASE, DEPOSITOR_1, 10 * 1e8); // 10 CBBTC
        deal(RETH_BASE, DEPOSITOR_1, 100 * 1e18); // 100 rETH
        deal(VIRTUAL_BASE, DEPOSITOR_1, 1000000 * 1e18); // 1M VIRTUAL

        // Approve tokens for depositors
        vm.startPrank(DEPOSITOR_1);
        weth.approve(address(fund), type(uint256).max);
        usdc.approve(address(fund), type(uint256).max);
        cbbtc.approve(address(fund), type(uint256).max);
        reth.approve(address(fund), type(uint256).max);
        virtuals.approve(address(fund), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(DEPOSITOR_2);
        weth.approve(address(fund), type(uint256).max);
        vm.stopPrank();
    }

    function testDeployment() public view {
        assertEq(fund.owner(), FUND_OWNER, "Fund owner should be set correctly");
        assertEq(fund.agent(), FUND_AGENT, "Fund agent should be set correctly");
        assertEq(fund.WETH_ADDRESS(), WETH_ADDRESS_BASE, "WETH address should be hardcoded");
        assertEq(fund.agentAumFeeBps(), AGENT_AUM_FEE_BPS, "AUM fee should be set correctly");
        assertEq(fund.totalSupply(), 0, "Initial total supply should be 0");
        assertEq(fund.totalNAVInAccountingAsset(), 0, "Initial NAV should be 0");
        
        // Debug: Check fund balances
        console.log("Fund WETH balance in testDeployment:", weth.balanceOf(address(fund)));
        console.log("Fund ETH balance in testDeployment:", address(fund).balance);
    }

    function testTWAPOracle_BasicFunctionality() public {
        // Test that the oracle can get prices for known token pairs
        uint256 usdcAmount = 1000 * 1e6; // 1000 USDC
        
        // Test USDC to WETH conversion
        uint256 wethValue = fund.getTokenValueInWETH(USDC_BASE, usdcAmount, 0);
        assertGt(wethValue, 0, "USDC to WETH conversion should return non-zero value");
        
        // Test WETH to USDC conversion
        uint256 wethAmount = 1 ether;
        uint256 usdcValue = fund.getWETHValueInToken(USDC_BASE, wethAmount, 0);
        assertGt(usdcValue, 0, "WETH to USDC conversion should return non-zero value");
        
        console.log("1000 USDC =", wethValue, "WETH");
        console.log("1 WETH =", usdcValue, "USDC");
    }

    function testTWAPOracle_WETHIdentityCheck() public {
        // Test that WETH returns identity for WETH conversions
        uint256 wethAmount = 5 ether;
        
        uint256 result1 = fund.getTokenValueInWETH(WETH_ADDRESS_BASE, wethAmount, 0);
        assertEq(result1, wethAmount, "WETH to WETH should return identity");
        
        uint256 result2 = fund.getWETHValueInToken(WETH_ADDRESS_BASE, wethAmount, 0);
        assertEq(result2, wethAmount, "WETH to WETH should return identity");
    }

    function testTWAPOracle_MultipleFeeTiers() public {
        uint256 testAmount = 1000 * 1e6; // 1000 USDC
        
        // Test different fee tiers
        uint256 price500 = fund.getTWAPPrice(USDC_BASE, WETH_ADDRESS_BASE, testAmount, 500);
        uint256 price3000 = fund.getTWAPPrice(USDC_BASE, WETH_ADDRESS_BASE, testAmount, 3000);
        uint256 price10000 = fund.getTWAPPrice(USDC_BASE, WETH_ADDRESS_BASE, testAmount, 10000);
        
        // All should return reasonable values (might be different due to different pools)
        assertGt(price500, 0, "0.05% fee tier should work");
        assertGt(price3000, 0, "0.3% fee tier should work");
        assertGt(price10000, 0, "1% fee tier should work");
        
        console.log("USDC->WETH prices across fee tiers:");
        console.log("0.05%:", price500);
        console.log("0.3%:", price3000);
        console.log("1%:", price10000);
    }

    function testDeposit_FirstDeposit() public {
        uint256 depositAmount = 1 ether;
        uint256 initialBalance = weth.balanceOf(DEPOSITOR_1);
        
        // Debug: Check fund balance before deposit
        console.log("Fund WETH balance before deposit:", weth.balanceOf(address(fund)));
        console.log("Fund ETH balance before deposit:", address(fund).balance);
        
        vm.startPrank(DEPOSITOR_1);
        uint256 sharesMinted = fund.deposit(depositAmount, DEPOSITOR_1);
        vm.stopPrank();
        
        // Check balances
        assertEq(sharesMinted, depositAmount, "First deposit should mint 1:1 shares");
        assertEq(fund.balanceOf(DEPOSITOR_1), sharesMinted, "Depositor should have correct shares");
        assertEq(weth.balanceOf(DEPOSITOR_1), initialBalance - depositAmount, "WETH should be transferred");
        
        // Fund automatically rebalances, so it won't hold all WETH
        // Instead, check that the total NAV equals the deposit amount
        uint256 totalNAV = fund.totalNAVInAccountingAsset();
        assertApproxEqRel(totalNAV, depositAmount, 0.05e18, "Fund NAV should approximately equal deposit"); // 5% tolerance for swap slippage
        
        assertEq(fund.totalSupply(), sharesMinted, "Total supply should equal shares minted");
    }

    function testDeposit_WithRebalancing() public {
        // Make initial deposit
        vm.startPrank(DEPOSITOR_1);
        uint256 initialDeposit = 1 ether;
        fund.deposit(initialDeposit, DEPOSITOR_1);
        vm.stopPrank();
        
        // Check that rebalancing occurred by verifying tokens were swapped
        uint256 wethBalance = weth.balanceOf(address(fund));
        uint256 usdcBalance = usdc.balanceOf(address(fund));
        uint256 cbbtcBalance = cbbtc.balanceOf(address(fund));
        uint256 rethBalance = reth.balanceOf(address(fund));
        uint256 virtualBalance = virtuals.balanceOf(address(fund));
        
        console.log("After deposit and rebalancing:");
        console.log("WETH balance:", wethBalance);
        console.log("USDC balance:", usdcBalance);
        console.log("CBBTC balance:", cbbtcBalance);
        console.log("rETH balance:", rethBalance);
        console.log("VIRTUAL balance:", virtualBalance);
        
        // Should have some of each target token
        assertGt(usdcBalance, 0, "Should have USDC after rebalancing");
        // Note: Other tokens might be 0 if pools don't have enough liquidity or TWAP fails
        
        // Check NAV is still approximately correct
        uint256 nav = fund.totalNAVInAccountingAsset();
        assertApproxEqRel(nav, initialDeposit, 0.05e18, "NAV should be close to deposit amount"); // 5% tolerance
    }

    function testDeposit_SubsequentDeposit() public {
        // First deposit
        vm.startPrank(DEPOSITOR_1);
        uint256 firstDeposit = 1 ether;
        uint256 firstShares = fund.deposit(firstDeposit, DEPOSITOR_1);
        vm.stopPrank();
        
        // Second deposit from different user
        vm.startPrank(DEPOSITOR_2);
        uint256 secondDeposit = 0.5 ether;
        uint256 navBeforeSecond = fund.totalNAVInAccountingAsset();
        uint256 totalSupplyBeforeSecond = fund.totalSupply();
        
        uint256 secondShares = fund.deposit(secondDeposit, DEPOSITOR_2);
        vm.stopPrank();
        
        // Calculate expected shares
        uint256 expectedShares = (secondDeposit * totalSupplyBeforeSecond) / navBeforeSecond;
        
        assertApproxEqRel(secondShares, expectedShares, 0.01e18, "Second deposit shares should be calculated correctly"); // 1% tolerance
        assertEq(fund.balanceOf(DEPOSITOR_2), secondShares, "Second depositor should have correct shares");
    }

    function testWithdraw_FullWithdrawal() public {
        // Make deposit and let it rebalance
        vm.startPrank(DEPOSITOR_1);
        uint256 depositAmount = 1 ether;
        uint256 shares = fund.deposit(depositAmount, DEPOSITOR_1);
        
        // Record balances before withdrawal
        uint256 wethBefore = weth.balanceOf(DEPOSITOR_1);
        uint256 usdcBefore = usdc.balanceOf(DEPOSITOR_1);
        uint256 cbbtcBefore = cbbtc.balanceOf(DEPOSITOR_1);
        uint256 rethBefore = reth.balanceOf(DEPOSITOR_1);
        uint256 virtualBefore = virtuals.balanceOf(DEPOSITOR_1);
        
        // Withdraw all shares
        fund.withdraw(shares, DEPOSITOR_1, DEPOSITOR_1);
        vm.stopPrank();
        
        // Check that tokens were returned (basket withdrawal)
        // The fund rebalances, so users get a proportional basket of all tokens
        uint256 totalValueReceived = 0;
        
        // Calculate total value received in WETH terms
        if (weth.balanceOf(DEPOSITOR_1) > wethBefore) {
            totalValueReceived += weth.balanceOf(DEPOSITOR_1) - wethBefore;
        }
        if (usdc.balanceOf(DEPOSITOR_1) > usdcBefore) {
            totalValueReceived += fund.getTokenValueInWETH(USDC_BASE, usdc.balanceOf(DEPOSITOR_1) - usdcBefore, 0);
        }
        if (cbbtc.balanceOf(DEPOSITOR_1) > cbbtcBefore) {
            totalValueReceived += fund.getTokenValueInWETH(CBBTC_BASE, cbbtc.balanceOf(DEPOSITOR_1) - cbbtcBefore, 0);
        }
        if (reth.balanceOf(DEPOSITOR_1) > rethBefore) {
            totalValueReceived += fund.getTokenValueInWETH(RETH_BASE, reth.balanceOf(DEPOSITOR_1) - rethBefore, 0);
        }
        if (virtuals.balanceOf(DEPOSITOR_1) > virtualBefore) {
            totalValueReceived += fund.getTokenValueInWETH(VIRTUAL_BASE, virtuals.balanceOf(DEPOSITOR_1) - virtualBefore, 0);
        }
        
        // Total value received should be approximately equal to deposit (minus fees/slippage)
        assertApproxEqRel(totalValueReceived, depositAmount, 0.1e18, "Should receive approximately deposited value");
        
        // Fund should be empty
        assertEq(fund.totalSupply(), 0, "Total supply should be 0");
        assertEq(fund.balanceOf(DEPOSITOR_1), 0, "User should have 0 shares");
    }

    function testWithdraw_PartialWithdrawal() public {
        // Make deposit
        vm.startPrank(DEPOSITOR_1);
        uint256 depositAmount = 2 ether;
        uint256 totalShares = fund.deposit(depositAmount, DEPOSITOR_1);
        
        // Withdraw half
        uint256 withdrawShares = totalShares / 2;
        
        // Track balances before withdrawal
        uint256 wethBefore = weth.balanceOf(DEPOSITOR_1);
        uint256 usdcBefore = usdc.balanceOf(DEPOSITOR_1);
        uint256 cbbtcBefore = cbbtc.balanceOf(DEPOSITOR_1);
        uint256 rethBefore = reth.balanceOf(DEPOSITOR_1);
        uint256 virtualsBefore = virtuals.balanceOf(DEPOSITOR_1);
        
        fund.withdraw(withdrawShares, DEPOSITOR_1, DEPOSITOR_1);
        vm.stopPrank();
        
        // Calculate total value of tokens received
        uint256 wethReceived = weth.balanceOf(DEPOSITOR_1) - wethBefore;
        uint256 usdcReceived = usdc.balanceOf(DEPOSITOR_1) - usdcBefore;
        uint256 cbbtcReceived = cbbtc.balanceOf(DEPOSITOR_1) - cbbtcBefore;
        uint256 rethReceived = reth.balanceOf(DEPOSITOR_1) - rethBefore;
        uint256 virtualsReceived = virtuals.balanceOf(DEPOSITOR_1) - virtualsBefore;
        
        // Convert all received tokens to WETH value using oracle
        uint256 totalValueReceived = wethReceived;
        if (usdcReceived > 0) {
            totalValueReceived += fund.getTokenValueInWETH(USDC_BASE, usdcReceived, 500);
        }
        if (cbbtcReceived > 0) {
            totalValueReceived += fund.getTokenValueInWETH(CBBTC_BASE, cbbtcReceived, 3000);
        }
        if (rethReceived > 0) {
            totalValueReceived += fund.getTokenValueInWETH(RETH_BASE, rethReceived, 500);
        }
        if (virtualsReceived > 0) {
            totalValueReceived += fund.getTokenValueInWETH(VIRTUAL_BASE, virtualsReceived, 10000);
        }
        
        // Check results
        assertEq(fund.balanceOf(DEPOSITOR_1), totalShares - withdrawShares, "Should have remaining shares");
        assertGt(totalValueReceived, 0, "Should receive some value in tokens");
        
        uint256 remainingNAV = fund.totalNAVInAccountingAsset();
        assertApproxEqRel(remainingNAV, depositAmount / 2, 0.1e18, "Remaining NAV should be ~half"); // 10% tolerance
    }

    function testRebalancing_ManualTrigger() public {
        // Make deposit to get some tokens
        vm.startPrank(DEPOSITOR_1);
        fund.deposit(1 ether, DEPOSITOR_1);
        vm.stopPrank();
        
        uint256 navBefore = fund.totalNAVInAccountingAsset();
        
        // Agent triggers manual rebalance
        vm.startPrank(FUND_AGENT);
        fund.triggerRebalance();
        vm.stopPrank();
        
        uint256 navAfter = fund.totalNAVInAccountingAsset();
        
        // NAV should remain approximately the same after rebalancing
        assertApproxEqRel(navAfter, navBefore, 0.05e18, "NAV should remain stable during rebalancing"); // 5% tolerance
    }

    function testSwapping_TokenToWETH() public {
        // First make a deposit to establish fund value
        vm.startPrank(DEPOSITOR_1);
        fund.deposit(1 ether, DEPOSITOR_1);
        vm.stopPrank();
        
        // Now give fund extra USDC directly to create imbalance
        deal(USDC_BASE, address(fund), 2000 * 1e6); // 2000 USDC
        
        uint256 usdcBefore = usdc.balanceOf(address(fund));
        console.log("USDC before rebalance:", usdcBefore);
        
        // Call internal swap function through agent
        vm.startPrank(FUND_AGENT);
        // Force rebalance which should sell excess USDC
        fund.triggerRebalance();
        vm.stopPrank();
        
        uint256 usdcAfter = usdc.balanceOf(address(fund));
        console.log("USDC after rebalance:", usdcAfter);
        
        // Should have swapped some USDC to maintain target weights
        assertLt(usdcAfter, usdcBefore, "Should have sold some USDC during rebalancing");
    }

    function testGetCurrentComposition() public {
        // Make deposit to get initial composition
        vm.startPrank(DEPOSITOR_1);
        fund.deposit(1 ether, DEPOSITOR_1);
        vm.stopPrank();
        
        (uint256[] memory currentWeights, address[] memory tokens) = fund.getCurrentCompositionBPS();
        
        assertEq(tokens.length, 4, "Should return 4 tokens");
        assertEq(currentWeights.length, 4, "Should return 4 weights");
        
        // Weights should sum to approximately 10000 (100%)
        uint256 totalWeight = 0;
        for (uint256 i = 0; i < currentWeights.length; i++) {
            totalWeight += currentWeights[i];
        }
        assertApproxEqAbs(totalWeight, 10000, 100, "Total weights should sum to ~10000"); // Allow 1% tolerance
        
        console.log("Current composition:");
        for (uint256 i = 0; i < tokens.length; i++) {
            console.log("Token:", tokens[i], "Weight:", currentWeights[i]);
        }
    }

    function testGetTargetComposition() public view {
        (uint256[] memory targetWeightsBPS, address[] memory tokens) = fund.getTargetCompositionBPS();
        
        assertEq(tokens.length, 4, "Should return 4 tokens");
        assertEq(targetWeightsBPS.length, 4, "Should return 4 weights");
        assertEq(targetWeightsBPS[0], 4000, "USDC target should be 40%");
        assertEq(targetWeightsBPS[1], 2500, "CBBTC target should be 25%");
        assertEq(targetWeightsBPS[2], 2500, "rETH target should be 25%");
        assertEq(targetWeightsBPS[3], 1000, "VIRTUAL target should be 10%");
    }

    function testAUMFeeCollection() public {
        // Make deposit
        vm.startPrank(DEPOSITOR_1);
        fund.deposit(1 ether, DEPOSITOR_1);
        vm.stopPrank();
        
        // Fast forward time (1 year)
        vm.warp(block.timestamp + 365 days);
        
        uint256 agentBalanceBefore = fund.balanceOf(AGENT_FEE_WALLET);
        uint256 protocolBalanceBefore = fund.balanceOf(PROTOCOL_FEE_RECIPIENT);
        
        // Collect AUM fee
        fund.collectAgentManagementFee();
        
        uint256 agentBalanceAfter = fund.balanceOf(AGENT_FEE_WALLET);
        uint256 protocolBalanceAfter = fund.balanceOf(PROTOCOL_FEE_RECIPIENT);
        
        // Agent and protocol should receive fee shares
        assertGt(agentBalanceAfter, agentBalanceBefore, "Agent should receive AUM fee shares");
        assertGt(protocolBalanceAfter, protocolBalanceBefore, "Protocol should receive AUM fee shares");
        
        console.log("Agent fee shares:", agentBalanceAfter - agentBalanceBefore);
        console.log("Protocol fee shares:", protocolBalanceAfter - protocolBalanceBefore);
    }

    function testUpdateTargetWeights() public {
        uint256[] memory newWeights = new uint256[](4);
        newWeights[0] = 3000; // 30% USDC
        newWeights[1] = 3000; // 30% CBBTC
        newWeights[2] = 3000; // 30% rETH
        newWeights[3] = 1000; // 10% VIRTUAL
        
        vm.startPrank(FUND_AGENT);
        fund.setTargetWeights(newWeights);
        vm.stopPrank();
        
        (uint256[] memory updatedWeights, ) = fund.getTargetCompositionBPS();
        assertEq(updatedWeights[0], 3000, "USDC weight should be updated");
        assertEq(updatedWeights[1], 3000, "CBBTC weight should be updated");
        assertEq(updatedWeights[2], 3000, "rETH weight should be updated");
        assertEq(updatedWeights[3], 1000, "VIRTUAL weight should remain same");
    }

    function testUSDCNAVCalculation() public {
        // Make deposit
        vm.startPrank(DEPOSITOR_1);
        fund.deposit(1 ether, DEPOSITOR_1);
        vm.stopPrank();
        
        uint256 navWETH = fund.totalNAVInAccountingAsset();
        uint256 navUSDC = fund.totalNAVInUSDC();
        
        assertGt(navWETH, 0, "WETH NAV should be positive");
        assertGt(navUSDC, 0, "USDC NAV should be positive");
        
        console.log("NAV in WETH:", navWETH);
        console.log("NAV in USDC:", navUSDC);
        
        // Rough sanity check: 1 ETH should be worth more than 1000 USDC in most market conditions
        assertGt(navUSDC, 1000 * 1e6, "1 ETH should be worth more than 1000 USDC");
    }

    function testRevertConditions() public {
        // Test deposit below minimum
        vm.startPrank(DEPOSITOR_1);
        vm.expectRevert(); // Should revert due to minimum deposit requirement
        fund.deposit(0.001 ether, DEPOSITOR_1); // Below 0.01 ETH minimum
        vm.stopPrank();
        
        // Test unauthorized agent functions
        vm.startPrank(DEPOSITOR_1);
        uint256[] memory weights = new uint256[](4);
        weights[0] = 2500;
        weights[1] = 2500;
        weights[2] = 2500;
        weights[3] = 2500;
        
        vm.expectRevert(); // Should revert - not agent
        fund.setTargetWeights(weights);
        vm.stopPrank();
        
        // Test zero address deposit
        vm.startPrank(DEPOSITOR_1);
        vm.expectRevert(); // Should revert - zero address
        fund.deposit(1 ether, address(0));
        vm.stopPrank();
    }

    function testEdgeCases_ZeroBalances() public {
        // Test behavior with zero token balances
        uint256 zeroValue = fund.getTokenValueInWETH(USDC_BASE, 0, 0);
        assertEq(zeroValue, 0, "Zero amount should return zero value");
        
        uint256 zeroWethValue = fund.getWETHValueInToken(USDC_BASE, 0, 0);
        assertEq(zeroWethValue, 0, "Zero WETH should return zero token value");
    }

    function testOracleFallbackMechanism() public {
        // This tests the fallback through different fee tiers
        // Even if one fee tier fails, it should try others
        uint256 testAmount = 100 * 1e6; // 100 USDC
        
        // Should work with some fee tier
        uint256 result = fund.getTokenValueInWETH(USDC_BASE, testAmount, 0);
        assertGt(result, 0, "Should get a result from fallback mechanism");
    }

    function testMostLiquidPoolSelection() public {
        // Test the automatic selection of most liquid pools
        (uint24 fee, address poolAddr) = fund.getMostLiquidPool(USDC_BASE, WETH_ADDRESS_BASE);
        
        assertGt(fee, 0, "Should return a valid fee tier");
        assertTrue(fee == 500 || fee == 3000 || fee == 10000, "Fee should be a valid tier");
        assertNotEq(poolAddr, address(0), "Pool address should not be zero");
        
        console.log("Most liquid USDC/WETH pool:");
        console.log("Fee tier:", fee);
        console.log("Pool address:", poolAddr);
    }

    function testContractExistence() public view {
        // Check if contracts exist
        console.log("Router address:", UNISWAP_V3_ROUTER_BASE);
        console.log("Router code size:", UNISWAP_V3_ROUTER_BASE.code.length);
        
        console.log("Quoter address:", UNISWAP_V3_QUOTER_BASE);
        console.log("Quoter code size:", UNISWAP_V3_QUOTER_BASE.code.length);
        
        console.log("Factory address:", UNISWAP_V3_FACTORY_BASE);
        console.log("Factory code size:", UNISWAP_V3_FACTORY_BASE.code.length);
    }

    function testBasicUniswapSwap() public {
        // Test our working direct pool swap implementation
        address pool = IUniswapV3Factory(UNISWAP_V3_FACTORY_BASE).getPool(WETH_ADDRESS_BASE, USDC_BASE, 500);
        console.log("Pool address:", pool);
        require(pool != address(0), "Pool doesn't exist");
        
        // Give our test contract some WETH
        deal(WETH_ADDRESS_BASE, address(this), 0.01 ether);
        
        uint256 wethBefore = weth.balanceOf(address(this));
        uint256 usdcBefore = usdc.balanceOf(address(this));
        
        console.log("WETH before:", wethBefore);
        console.log("USDC before:", usdcBefore);
        
        bool zeroForOne = WETH_ADDRESS_BASE < USDC_BASE;
        bytes memory data = abi.encode(WETH_ADDRESS_BASE, USDC_BASE, uint24(500));
        
        // Execute our working direct pool swap
        IUniswapV3Pool(pool).swap(
            address(this), // recipient
            zeroForOne,
            int256(0.01 ether),
            zeroForOne ? uint160(4295128740) : uint160(1461446703485210103287273052203988822378723970340),
            data
        );
        
        uint256 wethAfter = weth.balanceOf(address(this));
        uint256 usdcAfter = usdc.balanceOf(address(this));
        
        console.log("WETH after:", wethAfter);
        console.log("USDC after:", usdcAfter);
        
        // Verify the swap worked
        assertEq(wethAfter, 0, "Should have swapped all WETH");
        assertGt(usdcAfter, usdcBefore, "Should have received USDC");
        return;
    }
    
    function xtestOldSwap() public {
        // Moved old test code here, disabled
        require(UNISWAP_V3_ROUTER_BASE.code.length > 0, "Router contract doesn't exist");
        require(UNISWAP_V3_QUOTER_BASE.code.length > 0, "Quoter contract doesn't exist");
        
        // Check if the WETH/USDC pool exists and has liquidity
        address poolAddress = IUniswapV3Factory(UNISWAP_V3_FACTORY_BASE).getPool(WETH_ADDRESS_BASE, USDC_BASE, 500);
        console.log("Pool address:", poolAddress);
        require(poolAddress != address(0), "Pool doesn't exist");
        require(poolAddress.code.length > 0, "Pool has no code");
        
        console.log("Router address:", UNISWAP_V3_ROUTER_BASE);
        console.log("Using official ISwapRouter interface");
        
        // Test quoter first to see if we can get a quote
        uint256 wethAmount = 0.4 ether;
        console.log("Testing quoter for", wethAmount, "WETH -> USDC");
        
        // Use direct QuoterV2 interface
        IQuoterV2 quoter = IQuoterV2(UNISWAP_V3_QUOTER_BASE);
        
        try quoter.quoteExactInputSingle(
            IQuoterV2.QuoteExactInputSingleParams({
                tokenIn: WETH_ADDRESS_BASE,
                tokenOut: USDC_BASE,
                amountIn: wethAmount,
                fee: 500,
                sqrtPriceLimitX96: 0
            })
        ) returns (uint256 quotedAmount, uint160, uint32, uint256) {
            console.log("Quoter returned:", quotedAmount);
        } catch (bytes memory reason) {
            console.log("Quoter failed:");
            console.logBytes(reason);
            revert("Quoter failed");
        }
        
        deal(WETH_ADDRESS_BASE, address(this), wethAmount);
        
        // Check balances before
        console.log("WETH balance:", IERC20(WETH_ADDRESS_BASE).balanceOf(address(this)));
        
        // The issue might be that the router addresses are for Ethereum, not Base
        // Let's check if the current router actually exists
        console.log("V2 Router code length:", UNISWAP_V3_ROUTER_BASE.code.length);
        require(UNISWAP_V3_ROUTER_BASE.code.length > 0, "V2 Router doesn't exist on Base");
        
        // Try using the SwapRouter02 that's already defined
        console.log("Using SwapRouter02 on Base:", UNISWAP_V3_ROUTER_BASE);
        
        // Approve WETH for the router
        IERC20(WETH_ADDRESS_BASE).approve(UNISWAP_V3_ROUTER_BASE, wethAmount);
        
        // Check allowance
        uint256 allowance = IERC20(WETH_ADDRESS_BASE).allowance(address(this), UNISWAP_V3_ROUTER_BASE);
        console.log("Allowance:", allowance);
        
        // Try the same swap that's failing in the fund
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: WETH_ADDRESS_BASE,
            tokenOut: USDC_BASE,
            fee: 500,
            recipient: address(this),
            deadline: block.timestamp + 300,
            amountIn: wethAmount,
            amountOutMinimum: 0, // No slippage protection for this test
            sqrtPriceLimitX96: 0
        });
        
        uint256 usdcBefore = IERC20(USDC_BASE).balanceOf(address(this));
        console.log("USDC before swap:", usdcBefore);
        
        // The issue might be with the fee tier. Let's test different fee tiers
        uint24[3] memory feeTiers = [uint24(500), uint24(3000), uint24(10000)]; // 0.05%, 0.3%, 1%
        
        for (uint i = 0; i < feeTiers.length; i++) {
            uint24 fee = feeTiers[i];
            console.log("Testing fee tier:", fee);
            
            // Check if pool exists for this fee tier
            address testPool = IUniswapV3Factory(UNISWAP_V3_FACTORY_BASE).getPool(WETH_ADDRESS_BASE, USDC_BASE, fee);
            console.log("Pool address for fee tier:", testPool);
            
            if (testPool != address(0) && testPool.code.length > 0) {
                // Test quoter for this fee tier
                try uniswapQuoter.quoteExactInputSingle(
                    IQuoterV2.QuoteExactInputSingleParams({
                        tokenIn: WETH_ADDRESS_BASE,
                        tokenOut: USDC_BASE,
                        amountIn: 0.01 ether, // Use smaller amount
                        fee: fee,
                        sqrtPriceLimitX96: 0
                    })
                ) returns (uint256 quotedAmount, uint160, uint32, uint256) {
                    console.log("Quote for fee tier:", quotedAmount);
                    
                    if (quotedAmount > 0) {
                        // Try swap with this fee tier
                        params.fee = fee;
                        params.amountIn = 0.01 ether;
                        params.amountOutMinimum = quotedAmount * 95 / 100; // 5% slippage
                        
                        try ISwapRouter(UNISWAP_V3_ROUTER_BASE).exactInputSingle(params) returns (uint256 amountOut) {
                            console.log("Swap succeeded with fee tier, got USDC:", amountOut);
                            assertGt(amountOut, 0, "Should receive USDC");
                            return; // Success! Exit the function
                        } catch (bytes memory reason) {
                            console.log("Swap failed with this fee tier:");
                            console.logBytes(reason);
                        }
                    }
                } catch (bytes memory quoteReason) {
                    console.log("Quote failed for fee tier:");
                    console.logBytes(quoteReason);
                }
            }
        }
    }

    function testDirectPoolSwap() public {
        // Test direct pool interaction to see if our callback works
        address pool = IUniswapV3Factory(UNISWAP_V3_FACTORY_BASE).getPool(WETH_ADDRESS_BASE, USDC_BASE, 500);
        console.log("Pool address:", pool);
        require(pool != address(0), "Pool doesn't exist");
        
        // Give our test contract some WETH
        deal(WETH_ADDRESS_BASE, address(this), 0.01 ether);
        
        uint256 wethBefore = weth.balanceOf(address(this));
        uint256 usdcBefore = usdc.balanceOf(address(this));
        
        console.log("WETH before:", wethBefore);
        console.log("USDC before:", usdcBefore);
        
        bool zeroForOne = WETH_ADDRESS_BASE < USDC_BASE;
        console.log("zeroForOne:", zeroForOne);
        
        bytes memory data = abi.encode(WETH_ADDRESS_BASE, USDC_BASE, uint24(500));
        
        // Try direct pool swap
        try IUniswapV3Pool(pool).swap(
            address(this), // recipient
            zeroForOne,
            int256(0.01 ether),
            zeroForOne ? uint160(4295128740) : uint160(1461446703485210103287273052203988822378723970340), // Price limits
            data
        ) returns (int256 amount0, int256 amount1) {
            console.log("Swap succeeded");
            console.log("amount0:", uint256(amount0 >= 0 ? amount0 : -amount0));
            console.log("amount1:", uint256(amount1 >= 0 ? amount1 : -amount1));
            
            uint256 wethAfter = weth.balanceOf(address(this));
            uint256 usdcAfter = usdc.balanceOf(address(this));
            
            console.log("WETH after:", wethAfter);
            console.log("USDC after:", usdcAfter);
        } catch (bytes memory reason) {
            console.log("Direct pool swap failed:");
            console.logBytes(reason);
            revert("Direct pool swap failed");
        }
    }
    
    // Callback implementation for test contract
    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata data
    ) external {
        console.log("Callback called");
        console.log("amount0Delta:", uint256(amount0Delta >= 0 ? amount0Delta : -amount0Delta));
        console.log("amount1Delta:", uint256(amount1Delta >= 0 ? amount1Delta : -amount1Delta));
        
        // Decode the data
        (address tokenIn, address tokenOut, uint24 fee) = abi.decode(data, (address, address, uint24));
        
        // Verify callback is from correct pool
        address expectedPool = IUniswapV3Factory(UNISWAP_V3_FACTORY_BASE).getPool(tokenIn, tokenOut, fee);
        require(msg.sender == expectedPool, "Invalid callback sender");
        
        // Pay the required amount
        if (amount0Delta > 0) {
            address token = tokenIn < tokenOut ? tokenIn : tokenOut;
            IERC20(token).transfer(msg.sender, uint256(amount0Delta));
        } else if (amount1Delta > 0) {
            address token = tokenIn < tokenOut ? tokenOut : tokenIn;
            IERC20(token).transfer(msg.sender, uint256(amount1Delta));
        }
    }

    function testSpecificPoolPricing() public {
        // Test pricing using the specific pools provided
        uint256 testAmount = 1000 * 1e6; // 1000 USDC
        
        // Test WETH/USDC pool
        uint256 usdcToWeth = fund.getTWAPPrice(USDC_BASE, WETH_ADDRESS_BASE, testAmount, 3000);
        assertGt(usdcToWeth, 0, "USDC to WETH via specific pool should work");
        
        // Test WETH/rETH pricing
        uint256 rethAmount = 1 * 1e18; // 1 rETH
        uint256 rethToWeth = fund.getTWAPPrice(RETH_BASE, WETH_ADDRESS_BASE, rethAmount, 3000);
        assertGt(rethToWeth, 0, "rETH to WETH via specific pool should work");
        
        // Test WETH/cbBTC pricing
        uint256 cbbtcAmount = 1 * 1e8; // 1 cbBTC (8 decimals)
        uint256 cbbtcToWeth = fund.getTWAPPrice(CBBTC_BASE, WETH_ADDRESS_BASE, cbbtcAmount, 3000);
        assertGt(cbbtcToWeth, 0, "cbBTC to WETH via specific pool should work");
        
        // Test WETH/VIRTUAL pricing
        uint256 virtualAmount = 1000 * 1e18; // 1000 VIRTUAL
        uint256 virtualToWeth = fund.getTWAPPrice(VIRTUAL_BASE, WETH_ADDRESS_BASE, virtualAmount, 3000);
        assertGt(virtualToWeth, 0, "VIRTUAL to WETH via specific pool should work");
        
        console.log("Specific pool pricing results:");
        console.log("1000 USDC =", usdcToWeth, "WETH");
        console.log("1 rETH =", rethToWeth, "WETH");
        console.log("1 cbBTC =", cbbtcToWeth, "WETH");
        console.log("1000 VIRTUAL =", virtualToWeth, "WETH");
    }

    function testPoolAddressValidation() public view {
        // Verify the specific pool addresses are accessible
        // Note: In a real test environment, you might want to verify these pools exist
        // and have sufficient liquidity for TWAP calculations
        
        console.log("Using specific pool addresses:");
        console.log("WETH/USDC Pool:", WETH_USDC_POOL);
        console.log("WETH/rETH Pool:", WETH_RETH_POOL);
        console.log("WETH/cbBTC Pool:", WETH_CBBTC_POOL);
        console.log("WETH/VIRTUAL Pool:", WETH_VIRTUAL_POOL);
    }

    function testPoolValidityCheck() public {
        // Test pool validity checker
        bool isValid = fund.isPoolValidForTWAP(USDC_BASE, WETH_ADDRESS_BASE, 3000, 2);
        assertTrue(isValid, "USDC/WETH 0.3% pool should be valid for TWAP");
        
        console.log("USDC/WETH 0.3% pool TWAP validity:", isValid);
    }

    function testRebalanceDeviation() public {
        // Test rebalance deviation calculation
        vm.startPrank(DEPOSITOR_1);
        fund.deposit(1 ether, DEPOSITOR_1);
        vm.stopPrank();
        
        // Manually check if rebalance is needed
        // This would be done internally by the contract, but we can't easily access private functions
        uint256 navBefore = fund.totalNAVInAccountingAsset();
        assertGt(navBefore, 0, "NAV should be positive before testing deviation");
    }

    function testLargeDeposit() public {
        // Test handling of larger deposits
        vm.startPrank(DEPOSITOR_1);
        uint256 largeDeposit = 10 ether;
        uint256 sharesMinted = fund.deposit(largeDeposit, DEPOSITOR_1);
        vm.stopPrank();
        
        assertGt(sharesMinted, 0, "Should mint shares for large deposit");
        assertEq(fund.balanceOf(DEPOSITOR_1), sharesMinted, "Should have correct share balance");
        
        uint256 nav = fund.totalNAVInAccountingAsset();
        assertApproxEqRel(nav, largeDeposit, 0.1e18, "NAV should be close to deposit amount"); // 10% tolerance
        
        console.log("Large deposit NAV:", nav);
        console.log("Shares minted:", sharesMinted);
    }

    function testMultipleDepositors() public {
        // Test multiple depositors and proper share calculation
        vm.startPrank(DEPOSITOR_1);
        uint256 firstDeposit = 1 ether;
        uint256 firstShares = fund.deposit(firstDeposit, DEPOSITOR_1);
        vm.stopPrank();
        
        vm.startPrank(DEPOSITOR_2);
        uint256 secondDeposit = 2 ether;
        uint256 secondShares = fund.deposit(secondDeposit, DEPOSITOR_2);
        vm.stopPrank();
        
        // Third depositor
        address depositor3 = address(0x7000);
        deal(WETH_ADDRESS_BASE, depositor3, 5 ether);
        vm.startPrank(depositor3);
        weth.approve(address(fund), type(uint256).max);
        uint256 thirdDeposit = 1.5 ether;
        uint256 thirdShares = fund.deposit(thirdDeposit, depositor3);
        vm.stopPrank();
        
        // Verify total shares and individual balances
        uint256 totalShares = fund.totalSupply();
        assertEq(totalShares, firstShares + secondShares + thirdShares, "Total shares should sum correctly");
        
        console.log("Multiple depositors test:");
        console.log("Depositor 1 shares:", firstShares);
        console.log("Depositor 2 shares:", secondShares);
        console.log("Depositor 3 shares:", thirdShares);
        console.log("Total shares:", totalShares);
    }

    function testWithdrawAllowances() public {
        // Test withdrawal with allowances (not owner)
        vm.startPrank(DEPOSITOR_1);
        uint256 depositAmount = 1 ether;
        uint256 shares = fund.deposit(depositAmount, DEPOSITOR_1);
        
        // Approve DEPOSITOR_2 to withdraw on behalf of DEPOSITOR_1
        fund.approve(DEPOSITOR_2, shares / 2);
        vm.stopPrank();
        
        // DEPOSITOR_2 withdraws on behalf of DEPOSITOR_1
        vm.startPrank(DEPOSITOR_2);
        uint256 withdrawShares = shares / 2;
        fund.withdraw(withdrawShares, DEPOSITOR_2, DEPOSITOR_1);
        vm.stopPrank();
        
        // Check results
        assertEq(fund.balanceOf(DEPOSITOR_1), shares - withdrawShares, "DEPOSITOR_1 should have remaining shares");
        assertGt(weth.balanceOf(DEPOSITOR_2), 0, "DEPOSITOR_2 should have received tokens");
    }

    function testExtremePriceScenarios() public {
        // Test with very small amounts to check precision
        uint256 smallAmount = 1; // 1 wei of USDC (very small)
        
        // This might return 0 due to rounding, which is acceptable
        uint256 smallResult = fund.getTokenValueInWETH(USDC_BASE, smallAmount, 0);
        // Don't assert > 0 as it might legitimately be 0 due to precision
        console.log("1 wei USDC in WETH:", smallResult);
        
        // Test with very large amount
        uint256 largeAmount = 1000000 * 1e6; // 1M USDC
        uint256 largeResult = fund.getTokenValueInWETH(USDC_BASE, largeAmount, 0);
        assertGt(largeResult, 0, "Large amount conversion should work");
        
        console.log("1M USDC in WETH:", largeResult);
    }

    function testWorkingSwapImplementation() public {
        // Test that our fixed swap implementation works in the fund
        vm.startPrank(DEPOSITOR_1);
        
        uint256 depositAmount = 1 ether;
        uint256 shares = fund.deposit(depositAmount, DEPOSITOR_1);
        
        vm.stopPrank();
        
        assertGt(shares, 0, "Should mint shares");
        console.log("Shares minted:", shares);
        
        // Check that rebalancing worked (fund should have various tokens)
        uint256 usdcBalance = usdc.balanceOf(address(fund));
        uint256 cbbtcBalance = cbbtc.balanceOf(address(fund));
        
        console.log("Fund USDC balance:", usdcBalance);  
        console.log("Fund cbBTC balance:", cbbtcBalance);
        
        // At least one of these should be > 0 if rebalancing worked
        assertTrue(usdcBalance > 0 || cbbtcBalance > 0, "Rebalancing should have acquired some tokens");
    }

    function testContractUpgradeability() public view {
        // Test that contract state is properly set and immutable where expected
        assertEq(fund.WETH_ADDRESS(), WETH_ADDRESS_BASE, "WETH should be immutable");
        assertEq(fund.USDC_ADDRESS(), USDC_BASE, "USDC should be immutable");
        assertEq(fund.defaultTWAPPeriod(), TWAP_PERIOD, "TWAP period should be set correctly");
        assertEq(fund.WETH(), WETH_ADDRESS_BASE, "Oracle WETH should match fund WETH");
    }

    function testGasUsage() public {
        // Test gas usage for common operations
        vm.startPrank(DEPOSITOR_1);
        
        uint256 gasBefore = gasleft();
        fund.deposit(1 ether, DEPOSITOR_1);
        uint256 gasUsedDeposit = gasBefore - gasleft();
        
        gasBefore = gasleft();
        fund.totalNAVInAccountingAsset();
        uint256 gasUsedNAV = gasBefore - gasleft();
        
        gasBefore = gasleft();
        fund.getCurrentCompositionBPS();
        uint256 gasUsedComposition = gasBefore - gasleft();
        
        vm.stopPrank();
        
        console.log("Gas usage:");
        console.log("Deposit:", gasUsedDeposit);
        console.log("NAV calculation:", gasUsedNAV);
        console.log("Get composition:", gasUsedComposition);
        
        // Basic sanity checks (these are rough estimates)
        assertLt(gasUsedDeposit, 2000000, "Deposit should use reasonable gas");
        assertLt(gasUsedNAV, 1000000, "NAV calculation should use reasonable gas");
        assertLt(gasUsedComposition, 500000, "Composition should use reasonable gas");
    }

    function testTokenApprovals() public view {
        // Verify that fund has proper approvals for Uniswap router
        for (uint256 i = 0; i < allowedTokens.length; i++) {
            uint256 allowance = IERC20(allowedTokens[i]).allowance(address(fund), address(uniswapRouter));
            assertEq(allowance, type(uint256).max, "Fund should have max approval for each token");
        }
        
        // Check WETH approval
        uint256 wethAllowance = weth.allowance(address(fund), address(uniswapRouter));
        assertEq(wethAllowance, type(uint256).max, "Fund should have max WETH approval");
    }

    function testEventEmissions() public {
        // Test that events are emitted correctly
        vm.startPrank(DEPOSITOR_1);
        
        // This would test event emissions, but requires expectEmit calls
        // For now, just verify operations complete successfully
        uint256 shares = fund.deposit(1 ether, DEPOSITOR_1);
        
        vm.stopPrank(); // Stop DEPOSITOR_1 prank
        
        vm.startPrank(FUND_AGENT);
        fund.triggerRebalance();
        vm.stopPrank();
        
        vm.startPrank(DEPOSITOR_1);
        fund.withdraw(shares, DEPOSITOR_1, DEPOSITOR_1);
        vm.stopPrank();
        
        // If we reach here, all operations completed successfully
        assertTrue(true, "All operations with events completed successfully");
    }
}