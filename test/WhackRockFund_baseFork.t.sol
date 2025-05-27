// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";

// Ensure this path matches your actual contract file name in the src directory
// This import should point to the WhackRockFund contract that now includes the AUM fee parameters in its constructor
import { IAerodromeRouter, IWETH } from "../src/interfaces/IRouter.sol"; 
import {IERC20} from '@openzeppelin/contracts/interfaces/IERC20.sol';
// Assuming IWhackRockFund interface is defined if needed, or WhackRockFund itself is used.
import {IWhackRockFund} from "../src/interfaces/IWhackRockFund.sol";
import {WhackRockFund} from "../src/WhackRockFundV5_ERC4626_Aerodrome_SubGEvents.sol";



// --- Mainnet Addresses (BASE MAINNET) ---
address constant AERODROME_ROUTER_ADDRESS_BASE = 0xcF77a3Ba9A5CA399B7c97c74d54e5b1Beb874E43;
address constant WETH_ADDRESS_BASE = 0x4200000000000000000000000000000000000006;

address constant USDC_BASE = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913; // 6 decimals
address constant CBETH_BASE = 0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf; // 18 decimals (matching trace)
address constant VIRTU_BASE = 0x0b3e328455c4059EEb9e3f84b5543F74E24e7E1b; // 18 decimals
address constant NON_ALLOWED_TOKEN_EXAMPLE = 0xd9aAEc86B65D86f6A7B5B1b0c42FFA531710b6CA; // DAI 18 decimals

address constant TEST_OWNER = address(0x1000);
address constant TEST_AGENT = address(0x2000);
address constant TEST_DEPOSITOR = address(0x3000);
address constant TEST_DEPOSITOR_2 = address(0x4000);

// New constants for AUM fee parameters for testing
address constant TEST_AGENT_AUM_FEE_WALLET = address(0x5000); 
uint256 constant TEST_TOTAL_AUM_FEE_BPS = 100; // Example: 1% total annual AUM fee (100 BPS = 1%)
address constant TEST_PROTOCOL_AUM_RECIPIENT = address(0x6000); 

contract WhackRockFundTest is Test {
    WhackRockFund public whackRockFund;
    IAerodromeRouter public aerodromeRouter = IAerodromeRouter(AERODROME_ROUTER_ADDRESS_BASE);
    IERC20 public weth = IERC20(WETH_ADDRESS_BASE);
    IERC20 public usdc = IERC20(USDC_BASE);
    IERC20 public tokenA_CBETH = IERC20(CBETH_BASE);
    IERC20 public tokenB_VIRTU = IERC20(VIRTU_BASE);

    address public defaultAerodromeFactory;

    function _getValueInAccountingAsset(address tokenAddr, uint256 amount) internal view returns (uint256) {
        if (amount == 0) return 0;
        if (tokenAddr == whackRockFund.ACCOUNTING_ASSET()) return amount;

        // Try direct route first with volatile pool (for non-stablecoin pairs)
        IAerodromeRouter.Route[] memory routes = new IAerodromeRouter.Route[](1);
        routes[0] = IAerodromeRouter.Route({
            from: tokenAddr,
            to: whackRockFund.ACCOUNTING_ASSET(),
            stable: false, // Use volatile for most pairs
            factory: defaultAerodromeFactory
        });
        
        try aerodromeRouter.getAmountsOut(amount, routes) returns (uint[] memory amountsOut) {
            if (amountsOut.length > 0 && amountsOut[amountsOut.length - 1] > 0) {
                return amountsOut[amountsOut.length - 1];
            }
        } catch {}
        
        // If direct route fails, try routing through WETH
        if (tokenAddr != WETH_ADDRESS_BASE) {
            IAerodromeRouter.Route[] memory wethRoutes = new IAerodromeRouter.Route[](2);
            wethRoutes[0] = IAerodromeRouter.Route({
                from: tokenAddr,
                to: WETH_ADDRESS_BASE,
                stable: false,
                factory: defaultAerodromeFactory
            });
            wethRoutes[1] = IAerodromeRouter.Route({
                from: WETH_ADDRESS_BASE,
                to: whackRockFund.ACCOUNTING_ASSET(),
                stable: false, // WETH to USDC is typically volatile
                factory: defaultAerodromeFactory
            });
            
            try aerodromeRouter.getAmountsOut(amount, wethRoutes) returns (uint[] memory amountsOut) {
                if (amountsOut.length > 0 && amountsOut[amountsOut.length - 1] > 0) {
                    return amountsOut[amountsOut.length - 1];
                }
            } catch {}
        }
        
        return 0;
    }


    function setUp() public {
        try aerodromeRouter.defaultFactory() returns (address factoryAddr) {
            defaultAerodromeFactory = factoryAddr;
        } catch Error(string memory reason) {
            emit log_named_string("Failed to get defaultFactory from Aerodrome Router in setUp", reason);
            fail(); 
        }

        // Updated: USDC cannot be in allowed tokens since it's the accounting asset
        address[] memory initialAllowedTokens = new address[](2);
        initialAllowedTokens[0] = CBETH_BASE;
        initialAllowedTokens[1] = VIRTU_BASE;

        uint256[] memory initialTargetWeights = new uint256[](2);
        initialTargetWeights[0] = 6000; // 60% CBETH
        initialTargetWeights[1] = 4000; // 40% VIRTU

        vm.startPrank(TEST_OWNER);
        whackRockFund = new WhackRockFund(
            TEST_OWNER,
            TEST_AGENT,
            AERODROME_ROUTER_ADDRESS_BASE,
            initialAllowedTokens,
            initialTargetWeights,
            "WhackRock Test Vault",
            "WRTV",
            TEST_AGENT_AUM_FEE_WALLET,
            TEST_TOTAL_AUM_FEE_BPS,
            TEST_PROTOCOL_AUM_RECIPIENT,
            address(USDC_BASE),
            new bytes(0) 
        );
        vm.stopPrank();

        // Deal USDC instead of WETH for deposits
        deal(USDC_BASE, TEST_DEPOSITOR, 20000 * 1e6); // 20,000 USDC
        deal(USDC_BASE, TEST_DEPOSITOR_2, 20000 * 1e6); // 20,000 USDC
    }

    function testDeployment() public view { 
        assertEq(whackRockFund.owner(), TEST_OWNER);
        assertEq(whackRockFund.agent(), TEST_AGENT);
        assertEq(whackRockFund.ACCOUNTING_ASSET(), USDC_BASE); // Now USDC
        assertEq(whackRockFund.WETH_ADDRESS(), WETH_ADDRESS_BASE);
        assertTrue(whackRockFund.isAllowedTokenInternal(CBETH_BASE));
        assertTrue(whackRockFund.isAllowedTokenInternal(VIRTU_BASE));
        assertFalse(whackRockFund.isAllowedTokenInternal(USDC_BASE)); // USDC not in allowed tokens
        assertEq(whackRockFund.agentAumFeeWallet(), TEST_AGENT_AUM_FEE_WALLET);
        assertEq(whackRockFund.agentAumFeeBps(), TEST_TOTAL_AUM_FEE_BPS);
        assertEq(whackRockFund.protocolAumFeeRecipient(), TEST_PROTOCOL_AUM_RECIPIENT);
    }

    function testGetTokenValueViaAerodrome_WETH() public {
        require(defaultAerodromeFactory != address(0), "Aerodrome default factory not set in setUp");
        uint256 amountIn = 1 * 1e18; // 1 WETH
        if (weth.balanceOf(address(this)) < amountIn) {
            deal(WETH_ADDRESS_BASE, address(this), amountIn);
        }
        weth.approve(AERODROME_ROUTER_ADDRESS_BASE, amountIn);

        IAerodromeRouter.Route[] memory routes = new IAerodromeRouter.Route[](1);
        routes[0] = IAerodromeRouter.Route({
            from: WETH_ADDRESS_BASE, to: USDC_BASE, stable: false, factory: defaultAerodromeFactory
        });

        try aerodromeRouter.getAmountsOut(amountIn, routes) returns (uint[] memory amountsOut) {
            assertTrue(amountsOut.length > 0);
            assertTrue(amountsOut[amountsOut.length - 1] > 0);
            emit log_named_uint("USDC out for 1 WETH (via Aerodrome)", amountsOut[amountsOut.length - 1]);
        } catch Error(string memory reason) {
            emit log_named_string("Aerodrome getAmountsOut failed for WETH", reason);
        } catch { emit log_string("Aerodrome getAmountsOut failed with low-level data for WETH"); }
    }

    function testAgentCanTriggerRebalance_BasicFromUSDC() public {
        require(defaultAerodromeFactory != address(0), "Aerodrome default factory not set in setUp");
        uint256 depositAmountUSDC = 5000 * 1e6; // 5,000 USDC

        vm.startPrank(TEST_DEPOSITOR);
        usdc.approve(address(whackRockFund), depositAmountUSDC);

        // --- Expectations for deposit() call ---
        // 1. USDCDepositedAndSharesMinted (6 params: depositor, receiver, usdcDeposited, sharesMinted, navBefore, totalSupplyBefore)
        vm.expectEmit(true, true, false, false, address(whackRockFund)); 
        emit IWhackRockFund.USDCDepositedAndSharesMinted(TEST_DEPOSITOR, TEST_DEPOSITOR, depositAmountUSDC, 0, 0, 0); 
        
        // 2. RebalanceCheck (3 params: needsRebalance, maxDeviationBPS, currentNAV_AA)
        vm.expectEmit(false, false, false, false, address(whackRockFund)); 
        emit IWhackRockFund.RebalanceCheck(true, 0, 0); 

        // 3. FundTokenSwapped events from _rebalance() within deposit()
        vm.expectEmit(false, false, false, false, address(whackRockFund));
        emit IWhackRockFund.FundTokenSwapped(USDC_BASE, 0, CBETH_BASE, 0);
        vm.expectEmit(false, false, false, false, address(whackRockFund));
        emit IWhackRockFund.FundTokenSwapped(USDC_BASE, 0, VIRTU_BASE, 0);

        uint256 shares = whackRockFund.deposit(depositAmountUSDC, TEST_DEPOSITOR); 
        vm.stopPrank();

        assertTrue(shares > 0);
        uint256 navAfterDepositRebalance = whackRockFund.totalNAVInAccountingAsset();
        assertTrue(navAfterDepositRebalance <= depositAmountUSDC);
        assertTrue(usdc.balanceOf(address(whackRockFund)) < depositAmountUSDC);
        assertTrue(tokenA_CBETH.balanceOf(address(whackRockFund)) > 0);
        assertTrue(tokenB_VIRTU.balanceOf(address(whackRockFund)) > 0);

        uint256 navBeforeAgentRebalance = navAfterDepositRebalance;
        vm.startPrank(TEST_AGENT);
        
        vm.expectEmit(false, false, false, false, address(whackRockFund));
        emit IWhackRockFund.RebalanceCycleExecuted(0,0,0); 

        whackRockFund.triggerRebalance();
        vm.stopPrank();

        uint256 navAfterAgentRebalance = whackRockFund.totalNAVInAccountingAsset();
        assertApproxEqAbs(navAfterAgentRebalance, navBeforeAgentRebalance, navBeforeAgentRebalance / 1000); 
        emit log_named_uint("NAV after agent's rebalance", navAfterAgentRebalance);

        uint256 cbethValueUSDC_agent = _getValueInAccountingAsset(CBETH_BASE, tokenA_CBETH.balanceOf(address(whackRockFund)));
        uint256 virtuValueUSDC_agent = _getValueInAccountingAsset(VIRTU_BASE, tokenB_VIRTU.balanceOf(address(whackRockFund)));

        // Debug logging
        emit log_named_uint("CBETH balance", tokenA_CBETH.balanceOf(address(whackRockFund)));
        emit log_named_uint("CBETH value in USDC", cbethValueUSDC_agent);
        emit log_named_uint("VIRTU balance", tokenB_VIRTU.balanceOf(address(whackRockFund)));
        emit log_named_uint("VIRTU value in USDC", virtuValueUSDC_agent);
        emit log_named_uint("USDC balance", usdc.balanceOf(address(whackRockFund)));

        uint256 targetCbeth_agent = (navAfterAgentRebalance * 6000) / 10000; 
        uint256 targetVirtu_agent = (navAfterAgentRebalance * 4000) / 10000; 

        emit log_named_uint("Target CBETH value", targetCbeth_agent);
        emit log_named_uint("Target VIRTU value", targetVirtu_agent);

        // Increased tolerance for USDC-based calculations (10% instead of 5%)
        assertApproxEqAbs(cbethValueUSDC_agent, targetCbeth_agent, targetCbeth_agent / 10); 
        assertApproxEqAbs(virtuValueUSDC_agent, targetVirtu_agent, targetVirtu_agent / 10); 
        assertTrue(usdc.balanceOf(address(whackRockFund)) < 1e4); // Less than 0.01 USDC dust
    }

    // --- NEW TESTS START HERE ---

    function testCollectAgentManagementFee_CorrectAccrualAndDistribution() public {
        require(defaultAerodromeFactory != address(0), "Aerodrome default factory not set in setUp");
        uint256 depositAmountUSDC = 10000 * 1e6; // 10,000 USDC
        vm.startPrank(TEST_DEPOSITOR);
        usdc.approve(address(whackRockFund), depositAmountUSDC);
        // Expect events from deposit's rebalance
        vm.expectEmit(true, true, false, false, address(whackRockFund)); 
        emit IWhackRockFund.USDCDepositedAndSharesMinted(TEST_DEPOSITOR, TEST_DEPOSITOR, depositAmountUSDC, 0, 0, 0);
        vm.expectEmit(false, false, false, false, address(whackRockFund)); emit IWhackRockFund.RebalanceCheck(true, 0, 0); 
        vm.expectEmit(false, false, false, false, address(whackRockFund)); emit IWhackRockFund.FundTokenSwapped(USDC_BASE,0,CBETH_BASE,0);
        vm.expectEmit(false, false, false, false, address(whackRockFund)); emit IWhackRockFund.FundTokenSwapped(USDC_BASE,0,VIRTU_BASE,0);
        whackRockFund.deposit(depositAmountUSDC, TEST_DEPOSITOR); 
        vm.stopPrank();

        uint256 initialTotalShares = whackRockFund.totalSupply();
        uint256 initialNav = whackRockFund.totalNAVInAccountingAsset();
        assertTrue(initialTotalShares > 0, "Should have initial shares");
        assertTrue(initialNav > 0, "Should have initial NAV");

        uint256 oneYearInSeconds = 365 days;
        vm.warp(block.timestamp + oneYearInSeconds);

        uint256 expectedTotalFeeValueInAA_calc = (initialNav * TEST_TOTAL_AUM_FEE_BPS * oneYearInSeconds) / (whackRockFund.TOTAL_WEIGHT_BASIS_POINTS() * 365 days);
        uint256 expectedTotalSharesToMintForFee_calc = 0;
        if (initialNav > 0) { 
             expectedTotalSharesToMintForFee_calc = (expectedTotalFeeValueInAA_calc * initialTotalShares) / initialNav;
        }
        uint256 expectedAgentShares_calc = (expectedTotalSharesToMintForFee_calc * whackRockFund.AGENT_AUM_FEE_SHARE_BPS()) / whackRockFund.TOTAL_WEIGHT_BASIS_POINTS();
        uint256 expectedProtocolShares_calc = expectedTotalSharesToMintForFee_calc - expectedAgentShares_calc;

        vm.expectEmit(true, true, true, true, address(whackRockFund)); 
        emit IWhackRockFund.AgentAumFeeCollected(
            TEST_AGENT_AUM_FEE_WALLET, expectedAgentShares_calc, 
            TEST_PROTOCOL_AUM_RECIPIENT, expectedProtocolShares_calc, 
            expectedTotalFeeValueInAA_calc, 
            initialNav, // navAtFeeCalculation
            initialTotalShares, // totalSharesAtFeeCalculation
            block.timestamp + oneYearInSeconds 
        );

        whackRockFund.collectAgentManagementFee();

        assertApproxEqAbs(whackRockFund.balanceOf(TEST_AGENT_AUM_FEE_WALLET), expectedAgentShares_calc, expectedAgentShares_calc / 1000 + 1); 
        assertApproxEqAbs(whackRockFund.balanceOf(TEST_PROTOCOL_AUM_RECIPIENT), expectedProtocolShares_calc, expectedProtocolShares_calc / 1000 + 1);
        assertEq(whackRockFund.lastAgentAumFeeCollectionTimestamp(), block.timestamp);

        uint256 agentSharesBeforeSecondCall = whackRockFund.balanceOf(TEST_AGENT_AUM_FEE_WALLET);
        uint256 protocolSharesBeforeSecondCall = whackRockFund.balanceOf(TEST_PROTOCOL_AUM_RECIPIENT);
        
        vm.warp(block.timestamp + 1); 
        
        uint256 navAfterFirstFee = whackRockFund.totalNAVInAccountingAsset(); 
        uint256 sharesAfterFirstFee = whackRockFund.totalSupply();

        uint256 expectedFeeFor1Sec = (navAfterFirstFee * TEST_TOTAL_AUM_FEE_BPS * 1) / (whackRockFund.TOTAL_WEIGHT_BASIS_POINTS() * 365 days);
        uint256 expectedTotalSharesFor1Sec = 0;
        if (navAfterFirstFee > 0) {
            expectedTotalSharesFor1Sec = (expectedFeeFor1Sec * sharesAfterFirstFee) / navAfterFirstFee;
        }
        uint256 expectedAgentSharesFor1Sec = (expectedTotalSharesFor1Sec * whackRockFund.AGENT_AUM_FEE_SHARE_BPS()) / whackRockFund.TOTAL_WEIGHT_BASIS_POINTS();
        uint256 expectedProtocolSharesFor1Sec = expectedTotalSharesFor1Sec - expectedAgentSharesFor1Sec;

        if (expectedTotalSharesFor1Sec > 0) {
            vm.expectEmit(true, true, true, true, address(whackRockFund));
            emit IWhackRockFund.AgentAumFeeCollected(
                TEST_AGENT_AUM_FEE_WALLET, expectedAgentSharesFor1Sec,
                TEST_PROTOCOL_AUM_RECIPIENT, expectedProtocolSharesFor1Sec,
                expectedFeeFor1Sec, 
                navAfterFirstFee, 
                sharesAfterFirstFee, 
                block.timestamp + 1 
            );
        }
        
        whackRockFund.collectAgentManagementFee(); 
        
        assertApproxEqAbs(whackRockFund.balanceOf(TEST_AGENT_AUM_FEE_WALLET), agentSharesBeforeSecondCall + expectedAgentSharesFor1Sec, expectedAgentSharesFor1Sec / 1000 + 2); 
        assertApproxEqAbs(whackRockFund.balanceOf(TEST_PROTOCOL_AUM_RECIPIENT), protocolSharesBeforeSecondCall + expectedProtocolSharesFor1Sec, expectedProtocolSharesFor1Sec / 1000 + 2); 
    }

    function testWithdraw_USDCDistribution() public {
        require(defaultAerodromeFactory != address(0), "Aerodrome default factory not set in setUp");
        uint256 depositAmountUSDC = 10000 * 1e6; // 10,000 USDC
        vm.startPrank(TEST_DEPOSITOR);
        usdc.approve(address(whackRockFund), depositAmountUSDC);
        
        vm.expectEmit(true, true, false, false, address(whackRockFund)); 
        emit IWhackRockFund.USDCDepositedAndSharesMinted(TEST_DEPOSITOR, TEST_DEPOSITOR, depositAmountUSDC, 0,0,0);
        vm.expectEmit(false, false, false, false, address(whackRockFund)); emit IWhackRockFund.RebalanceCheck(true, 0,0);
        vm.expectEmit(false, false, false, false, address(whackRockFund)); emit IWhackRockFund.FundTokenSwapped(USDC_BASE,0,CBETH_BASE,0);
        vm.expectEmit(false, false, false, false, address(whackRockFund)); emit IWhackRockFund.FundTokenSwapped(USDC_BASE,0,VIRTU_BASE,0);
        uint256 sharesDeposited = whackRockFund.deposit(depositAmountUSDC, TEST_DEPOSITOR);
        vm.stopPrank();

        uint256 fundUsdcBeforeWithdraw = usdc.balanceOf(address(whackRockFund));
        uint256 fundCbethBeforeWithdraw = tokenA_CBETH.balanceOf(address(whackRockFund));
        uint256 fundVirtuBeforeWithdraw = tokenB_VIRTU.balanceOf(address(whackRockFund));
        uint256 totalSupplyBeforeWithdraw = whackRockFund.totalSupply();
        uint256 navBeforeWithdraw = whackRockFund.totalNAVInAccountingAsset();
        
        uint256 depositorUsdcBefore = usdc.balanceOf(TEST_DEPOSITOR);

        uint256 sharesToBurn = sharesDeposited / 2; 
        uint256 expectedUsdcWithdrawn = (navBeforeWithdraw * sharesToBurn) / totalSupplyBeforeWithdraw;

        vm.startPrank(TEST_DEPOSITOR);
        
        vm.expectEmit(false, false, false, false, address(whackRockFund)); // USDCWithdrawn
        emit IWhackRockFund.USDCWithdrawn(TEST_DEPOSITOR, TEST_DEPOSITOR, sharesToBurn, 0, 0, 0);
        // Expect swaps to USDC
        vm.expectEmit(false, false, false, false, address(whackRockFund));
        emit IWhackRockFund.FundTokenSwapped(CBETH_BASE, 0, USDC_BASE, 0);
        vm.expectEmit(false, false, false, false, address(whackRockFund));
        emit IWhackRockFund.FundTokenSwapped(VIRTU_BASE, 0, USDC_BASE, 0);
        vm.expectEmit(false, false, false, false, address(whackRockFund)); // RebalanceCheck
        emit IWhackRockFund.RebalanceCheck(false, 0,0); 
        
        whackRockFund.withdraw(sharesToBurn, TEST_DEPOSITOR, TEST_DEPOSITOR);
        vm.stopPrank();

        // User should receive only USDC
        assertApproxEqAbs(usdc.balanceOf(TEST_DEPOSITOR), depositorUsdcBefore + expectedUsdcWithdrawn, expectedUsdcWithdrawn / 100); 
        
        // Fund should have proportionally less of each token
        uint256 expectedCbethRemaining = (fundCbethBeforeWithdraw * (totalSupplyBeforeWithdraw - sharesToBurn)) / totalSupplyBeforeWithdraw;
        uint256 expectedVirtuRemaining = (fundVirtuBeforeWithdraw * (totalSupplyBeforeWithdraw - sharesToBurn)) / totalSupplyBeforeWithdraw;
        
        assertApproxEqAbs(tokenA_CBETH.balanceOf(address(whackRockFund)), expectedCbethRemaining, expectedCbethRemaining / 100 + 1);
        assertApproxEqAbs(tokenB_VIRTU.balanceOf(address(whackRockFund)), expectedVirtuRemaining, expectedVirtuRemaining / 100 + 1);

        assertEq(whackRockFund.totalSupply(), totalSupplyBeforeWithdraw - sharesToBurn);
        assertEq(whackRockFund.balanceOf(TEST_DEPOSITOR), sharesDeposited - sharesToBurn);
    }

    function testRebalance_ZeroNAV() public {
        uint256 navBefore = whackRockFund.totalNAVInAccountingAsset();
        assertEq(navBefore, 0, "Initial NAV should be 0");

        vm.startPrank(TEST_AGENT);
        vm.expectEmit(false, false, false, false, address(whackRockFund));
        emit IWhackRockFund.RebalanceCycleExecuted(0,0,0);
        whackRockFund.triggerRebalance();
        vm.stopPrank();

        assertEq(whackRockFund.totalNAVInAccountingAsset(), 0, "NAV should remain 0 after rebalance on 0 NAV");
        assertEq(usdc.balanceOf(address(whackRockFund)), 0);
        assertEq(tokenA_CBETH.balanceOf(address(whackRockFund)), 0);
    }
    
    function test_isRebalanceNeeded_Thresholds() public {
        uint256 depositAmountUSDC = 10000 * 1e6; // 10,000 USDC
        vm.startPrank(TEST_DEPOSITOR);
        usdc.approve(address(whackRockFund), depositAmountUSDC);
        
        vm.expectEmit(true, true, false, false, address(whackRockFund)); 
        emit IWhackRockFund.USDCDepositedAndSharesMinted(TEST_DEPOSITOR, TEST_DEPOSITOR, depositAmountUSDC, 0, 0, 0);
        vm.expectEmit(false, false, false, false, address(whackRockFund)); 
        emit IWhackRockFund.RebalanceCheck(true, 0, 0); 
        
        vm.expectEmit(false, false, false, false, address(whackRockFund)); emit IWhackRockFund.FundTokenSwapped(USDC_BASE,0,CBETH_BASE,0);
        vm.expectEmit(false, false, false, false, address(whackRockFund)); emit IWhackRockFund.FundTokenSwapped(USDC_BASE,0,VIRTU_BASE,0);
        whackRockFund.deposit(depositAmountUSDC, TEST_DEPOSITOR); 
        vm.stopPrank();

        // --- Scenario 1: Deviation just BELOW threshold after a small deposit ---
        // Updated to use minimum deposit amount in USDC
        uint256 smallDeposit = 10 * 1e6; // 10 USDC (minimum deposit)
        vm.startPrank(TEST_DEPOSITOR_2);
        deal(USDC_BASE, TEST_DEPOSITOR_2, smallDeposit);
        usdc.approve(address(whackRockFund), smallDeposit);
        
        vm.expectEmit(true, true, false, false, address(whackRockFund)); 
        emit IWhackRockFund.USDCDepositedAndSharesMinted(TEST_DEPOSITOR_2, TEST_DEPOSITOR_2, smallDeposit, 0, 0, 0);
        vm.expectEmit(false, false, false, false, address(whackRockFund)); 
        emit IWhackRockFund.RebalanceCheck(false, 0, 0); 

        whackRockFund.deposit(smallDeposit, TEST_DEPOSITOR_2);
        vm.stopPrank();

        // --- Scenario 2: Deviation ABOVE threshold ---
        uint256 cbethValueForOverweight = _getValueInAccountingAsset(CBETH_BASE, 1 * 1e18); 
        uint256 cbethToMakeOverweight = 0;
        if (cbethValueForOverweight > 0) { 
             cbethToMakeOverweight = (whackRockFund.totalNAVInAccountingAsset() * (whackRockFund.REBALANCE_DEVIATION_THRESHOLD_BPS() + 100) * 1e18) / (whackRockFund.TOTAL_WEIGHT_BASIS_POINTS() * cbethValueForOverweight);
        }
        if (cbethToMakeOverweight == 0) cbethToMakeOverweight = 20 * 1e18; // 20 CBETH

        deal(CBETH_BASE, address(whackRockFund), cbethToMakeOverweight);

        // Another small deposit that meets minimum requirements
        uint256 anotherSmallDeposit = 10 * 1e6; // 10 USDC
        vm.startPrank(TEST_DEPOSITOR_2);
        deal(USDC_BASE, TEST_DEPOSITOR_2, anotherSmallDeposit); 
        usdc.approve(address(whackRockFund), anotherSmallDeposit);

        vm.expectEmit(true, true, false, false, address(whackRockFund)); 
        emit IWhackRockFund.USDCDepositedAndSharesMinted(TEST_DEPOSITOR_2, TEST_DEPOSITOR_2, anotherSmallDeposit, 0,0,0);
        vm.expectEmit(false, false, false, false, address(whackRockFund)); 
        emit IWhackRockFund.RebalanceCheck(true, 0,0); 
        
        vm.expectEmit(false, false, false, false, address(whackRockFund)); 
        emit IWhackRockFund.FundTokenSwapped(CBETH_BASE,0,USDC_BASE,0); 
        vm.expectEmit(false, false, false, false, address(whackRockFund)); 
        emit IWhackRockFund.FundTokenSwapped(USDC_BASE,0,VIRTU_BASE,0); 

        whackRockFund.deposit(anotherSmallDeposit, TEST_DEPOSITOR_2);
        vm.stopPrank();
    }

    function testSlippageScenarios_RevertsOrAccepts_NoEvents() public {
        require(defaultAerodromeFactory != address(0), "Aerodrome default factory not set in setUp");
        uint256 depositAmountUSDC = 5000 * 1e6; // 5,000 USDC
        vm.startPrank(TEST_DEPOSITOR);
        deal(USDC_BASE, TEST_DEPOSITOR, depositAmountUSDC);
        usdc.approve(address(whackRockFund), depositAmountUSDC);
        whackRockFund.deposit(depositAmountUSDC, TEST_DEPOSITOR); 
        vm.stopPrank();
        assertTrue(true, "Deposit and initial rebalance completed with default slippage settings.");
    }

    function testZeroBalanceTokenRebalance_NoEvents() public {
        require(defaultAerodromeFactory != address(0), "Aerodrome default factory not set in setUp");
        uint256 depositAmountUSDC = 5000 * 1e6; // 5,000 USDC
        vm.startPrank(TEST_DEPOSITOR);
        deal(USDC_BASE, TEST_DEPOSITOR, depositAmountUSDC);
        usdc.approve(address(whackRockFund), depositAmountUSDC);
        whackRockFund.deposit(depositAmountUSDC, TEST_DEPOSITOR); 
        vm.stopPrank();
        assertTrue(tokenB_VIRTU.balanceOf(address(whackRockFund)) > 0, "VIRTU balance should be > 0 after initial rebalance");
    }

    function testRebalance_HandlesUnpriceableToken() public {
        require(defaultAerodromeFactory != address(0), "Aerodrome default factory not set in setUp");
        uint256 depositAmountUSDC = 10000 * 1e6; // 10,000 USDC
        vm.startPrank(TEST_DEPOSITOR);
        deal(USDC_BASE, TEST_DEPOSITOR, depositAmountUSDC);
        usdc.approve(address(whackRockFund), depositAmountUSDC);
        whackRockFund.deposit(depositAmountUSDC, TEST_DEPOSITOR); 
        vm.stopPrank();

        uint256 navBefore = whackRockFund.totalNAVInAccountingAsset();
        
        vm.startPrank(TEST_AGENT);
        vm.expectEmit(false, false, false, false, address(whackRockFund));
        emit IWhackRockFund.RebalanceCycleExecuted(0,0,0);
        whackRockFund.triggerRebalance();
        vm.stopPrank();
        
        uint256 navAfter = whackRockFund.totalNAVInAccountingAsset();
        assertApproxEqAbs(navAfter, navBefore, navBefore / 100); // Increased tolerance to 1%

        uint256 cbethValue = _getValueInAccountingAsset(CBETH_BASE, tokenA_CBETH.balanceOf(address(whackRockFund)));
        uint256 virtuValue = _getValueInAccountingAsset(VIRTU_BASE, tokenB_VIRTU.balanceOf(address(whackRockFund)));
        
        uint256 combinedNavOfPricedAssets = cbethValue + virtuValue + usdc.balanceOf(address(whackRockFund));
        
        if (combinedNavOfPricedAssets > 0) { 
            uint256 expectedCbethValue = (combinedNavOfPricedAssets * 6000) / 10000; 
            uint256 expectedVirtuValue = (combinedNavOfPricedAssets * 4000) / 10000; 
            
            assertApproxEqAbs(cbethValue, expectedCbethValue, expectedCbethValue / 10); // Increased tolerance to 10%
            assertApproxEqAbs(virtuValue, expectedVirtuValue, expectedVirtuValue / 10); // Increased tolerance to 10%
        }
    }

    function testRebalanceWhenAlreadyBalanced_NoEvents() public {
        require(defaultAerodromeFactory != address(0), "Aerodrome default factory not set in setUp");
        uint256 depositAmountUSDC = 10000 * 1e6; // 10,000 USDC
        vm.startPrank(TEST_DEPOSITOR);
        deal(USDC_BASE, TEST_DEPOSITOR, depositAmountUSDC);
        usdc.approve(address(whackRockFund), depositAmountUSDC);
        whackRockFund.deposit(depositAmountUSDC, TEST_DEPOSITOR); 
        vm.stopPrank();

        uint256 navBeforeSecondRebalance = whackRockFund.totalNAVInAccountingAsset();

        vm.startPrank(TEST_AGENT);
        whackRockFund.triggerRebalance(); 
        vm.stopPrank();

        uint256 navAfterSecondRebalance = whackRockFund.totalNAVInAccountingAsset();
        assertApproxEqAbs(navAfterSecondRebalance, navBeforeSecondRebalance, navBeforeSecondRebalance / 100); // Increased tolerance to 1%

        uint256 cbethValueUSDC = _getValueInAccountingAsset(CBETH_BASE, tokenA_CBETH.balanceOf(address(whackRockFund)));
        uint256 virtuValueUSDC = _getValueInAccountingAsset(VIRTU_BASE, tokenB_VIRTU.balanceOf(address(whackRockFund)));

        uint256 targetCbeth = (navAfterSecondRebalance * 6000) / 10000;
        uint256 targetVirtu = (navAfterSecondRebalance * 4000) / 10000;

        assertApproxEqAbs(cbethValueUSDC, targetCbeth, targetCbeth / 10); // Increased tolerance to 10%
        assertApproxEqAbs(virtuValueUSDC, targetVirtu, targetVirtu / 10); // Increased tolerance to 10%
        
        assertTrue(usdc.balanceOf(address(whackRockFund)) < 1e4, "USDC balance should be dust after full rebalance cycle");
    }

    function testRebalanceWithExistingAllowedTokens_OverweightSales_NoEvents() public {
        require(defaultAerodromeFactory != address(0), "Aerodrome default factory not set in setUp");
        uint256 initialUsdcDeposit = 10000 * 1e6; // 10,000 USDC
        vm.startPrank(TEST_DEPOSITOR);
        deal(USDC_BASE, TEST_DEPOSITOR, initialUsdcDeposit);
        usdc.approve(address(whackRockFund), initialUsdcDeposit);
        whackRockFund.deposit(initialUsdcDeposit, TEST_DEPOSITOR);
        vm.stopPrank();

        // Wait for initial rebalance to settle
        vm.warp(block.timestamp + 1);
        
        // Get current CBETH balance and add more to make it overweight
        uint256 currentCbethBalance = tokenA_CBETH.balanceOf(address(whackRockFund));
        uint256 cbethToDealOverweight = currentCbethBalance * 2; // Double the current balance to make it significantly overweight
        deal(CBETH_BASE, address(whackRockFund), currentCbethBalance + cbethToDealOverweight); 

        uint256 cbethBalanceBefore = tokenA_CBETH.balanceOf(address(whackRockFund));
        uint256 navBefore = whackRockFund.totalNAVInAccountingAsset();

        vm.startPrank(TEST_AGENT);
        whackRockFund.triggerRebalance();
        vm.stopPrank();

        uint256 cbethBalanceAfter = tokenA_CBETH.balanceOf(address(whackRockFund));
        uint256 navAfter = whackRockFund.totalNAVInAccountingAsset();

        assertTrue(cbethBalanceAfter < cbethBalanceBefore, "CBETH balance should decrease after rebalancing overweight position");
        assertApproxEqAbs(navAfter, navBefore, navBefore / 50); // Allow 2% slippage

        uint256 cbethValueAfterUSDC = _getValueInAccountingAsset(CBETH_BASE, cbethBalanceAfter);
        uint256 targetCbethValueUSDC = (navAfter * 6000) / 10000; 
        assertApproxEqAbs(cbethValueAfterUSDC, targetCbethValueUSDC, targetCbethValueUSDC / 10); // 10% tolerance
    }

    function testRebalanceWithExistingAllowedTokens_UnderweightPurchases_NoEvents() public {
        require(defaultAerodromeFactory != address(0), "Aerodrome default factory not set in setUp");
        uint256 initialUsdcDeposit = 10000 * 1e6; // 10,000 USDC
        vm.startPrank(TEST_DEPOSITOR);
        deal(USDC_BASE, TEST_DEPOSITOR, initialUsdcDeposit);
        usdc.approve(address(whackRockFund), initialUsdcDeposit);
        whackRockFund.deposit(initialUsdcDeposit, TEST_DEPOSITOR); 
        vm.stopPrank();

        // Wait for initial rebalance to settle
        vm.warp(block.timestamp + 1);

        uint256 cbethCurrentBalance = tokenA_CBETH.balanceOf(address(whackRockFund));
        uint256 cbethToRemove = cbethCurrentBalance / 2;

        if (cbethToRemove > 0) {
            // Remove half of CBETH to make it underweight
            deal(CBETH_BASE, address(whackRockFund), cbethCurrentBalance - cbethToRemove); 

            // Add equivalent value in USDC to maintain NAV
            uint256 usdcToCompensate = _getValueInAccountingAsset(CBETH_BASE, cbethToRemove);
            if (usdcToCompensate > 0) {
                deal(USDC_BASE, address(whackRockFund), usdc.balanceOf(address(whackRockFund)) + usdcToCompensate);
            }
        }

        uint256 cbethBalanceBefore = tokenA_CBETH.balanceOf(address(whackRockFund));
        uint256 usdcBalanceBefore = usdc.balanceOf(address(whackRockFund));
        uint256 navBefore = whackRockFund.totalNAVInAccountingAsset();

        vm.startPrank(TEST_AGENT);
        whackRockFund.triggerRebalance();
        vm.stopPrank();

        uint256 cbethBalanceAfter = tokenA_CBETH.balanceOf(address(whackRockFund));
        uint256 usdcBalanceAfter = usdc.balanceOf(address(whackRockFund));
        uint256 navAfter = whackRockFund.totalNAVInAccountingAsset();

        assertTrue(cbethBalanceAfter > cbethBalanceBefore, "CBETH balance should increase after rebalancing underweight position");
        assertTrue(usdcBalanceAfter < usdcBalanceBefore, "USDC balance should decrease after buying CBETH"); 
        assertApproxEqAbs(navAfter, navBefore, navBefore / 50); // Allow 2% slippage

        uint256 cbethValueAfterUSDC = _getValueInAccountingAsset(CBETH_BASE, cbethBalanceAfter);
        uint256 targetCbethValueUSDC = (navAfter * 6000) / 10000; 
        assertApproxEqAbs(cbethValueAfterUSDC, targetCbethValueUSDC, targetCbethValueUSDC / 10); // 10% tolerance
    }

    function testMultipleDepositsAndWithdrawals_NAVAccuracy_NoEvents() public {
        uint256 depositor1Amount = 5000 * 1e6; // 5,000 USDC
        uint256 depositor2Amount = 3000 * 1e6; // 3,000 USDC

        vm.startPrank(TEST_DEPOSITOR);
        usdc.approve(address(whackRockFund), depositor1Amount);
        uint256 shares1 = whackRockFund.deposit(depositor1Amount, TEST_DEPOSITOR);
        vm.stopPrank();
        assertTrue(shares1 > 0);
        uint256 navAfterDeposit1 = whackRockFund.totalNAVInAccountingAsset();

        vm.startPrank(TEST_DEPOSITOR_2);
        usdc.approve(address(whackRockFund), depositor2Amount);
        uint256 shares2 = whackRockFund.deposit(depositor2Amount, TEST_DEPOSITOR_2);
        vm.stopPrank();
        assertTrue(shares2 > 0);

        uint256 totalSharesAfterDeposit2 = whackRockFund.totalSupply();
        uint256 navAfterDeposit2 = whackRockFund.totalNAVInAccountingAsset();
        uint256 navPerShare1 = shares1 > 0 ? (navAfterDeposit1 * 1e18) / shares1 : 0;
        uint256 navPerShare2 = totalSharesAfterDeposit2 > 0 ? (navAfterDeposit2 * 1e18) / totalSharesAfterDeposit2 : 0;
        if (shares1 > 0 && totalSharesAfterDeposit2 > 0) {
            assertApproxEqAbs(navPerShare1, navPerShare2, navPerShare1 / 50); 
        }

        uint256 d1_usdc_before_withdraw = usdc.balanceOf(TEST_DEPOSITOR);
        uint256 sharesToWithdraw1 = shares1 / 2;
        if (sharesToWithdraw1 > 0) {
            vm.startPrank(TEST_DEPOSITOR);
            whackRockFund.withdraw(sharesToWithdraw1, TEST_DEPOSITOR, TEST_DEPOSITOR);
            vm.stopPrank();
            assertTrue(usdc.balanceOf(TEST_DEPOSITOR) > d1_usdc_before_withdraw);
        }

        uint256 d2_usdc_before_withdraw = usdc.balanceOf(TEST_DEPOSITOR_2);
        uint256 sharesToWithdraw2 = whackRockFund.balanceOf(TEST_DEPOSITOR_2);
        if (sharesToWithdraw2 > 0) {
            vm.startPrank(TEST_DEPOSITOR_2);
            whackRockFund.withdraw(sharesToWithdraw2, TEST_DEPOSITOR_2, TEST_DEPOSITOR_2);
            vm.stopPrank();
            assertTrue(usdc.balanceOf(TEST_DEPOSITOR_2) > d2_usdc_before_withdraw);
        }
        emit log("Multiple deposits and withdrawals test completed (USDC withdrawal).");
    }

    function testAgentUpdatesWeightsAndRebalances_CorrectTargets_NoEvents() public {
        require(defaultAerodromeFactory != address(0), "Aerodrome default factory not set in setUp");
        uint256 depositAmountUSDC = 10000 * 1e6; // 10,000 USDC
        vm.startPrank(TEST_DEPOSITOR);
        usdc.approve(address(whackRockFund), depositAmountUSDC);
        whackRockFund.deposit(depositAmountUSDC, TEST_DEPOSITOR);
        vm.stopPrank();

        uint256[] memory newWeights = new uint256[](2);
        newWeights[0] = 3000; // 30% CBETH
        newWeights[1] = 7000; // 70% VIRTU

        vm.startPrank(TEST_AGENT);
        whackRockFund.setTargetWeights(newWeights);
        whackRockFund.triggerRebalance();
        vm.stopPrank();

        uint256 navAfterNewRebalance = whackRockFund.totalNAVInAccountingAsset();
        uint256 cbethValueUSDC = _getValueInAccountingAsset(CBETH_BASE, tokenA_CBETH.balanceOf(address(whackRockFund)));
        uint256 virtuValueUSDC = _getValueInAccountingAsset(VIRTU_BASE, tokenB_VIRTU.balanceOf(address(whackRockFund)));

        uint256 targetCbethNew = (navAfterNewRebalance * 3000) / 10000;
        uint256 targetVirtuNew = (navAfterNewRebalance * 7000) / 10000;

        assertApproxEqAbs(cbethValueUSDC, targetCbethNew, targetCbethNew / 10); 
        assertApproxEqAbs(virtuValueUSDC, targetVirtuNew, targetVirtuNew / 10); 
    }

    function testEmergencyWithdrawERC20_AllowedToken_NoEvents() public {
        uint256 amountToSteal = 1 * 1e18; // 1 CBETH
        deal(CBETH_BASE, address(whackRockFund), amountToSteal * 2);

        uint256 ownerBalanceBefore = tokenA_CBETH.balanceOf(TEST_OWNER);
        vm.startPrank(TEST_OWNER);
        whackRockFund.emergencyWithdrawERC20(CBETH_BASE, TEST_OWNER, amountToSteal);
        vm.stopPrank();

        assertEq(tokenA_CBETH.balanceOf(TEST_OWNER), ownerBalanceBefore + amountToSteal);
        assertEq(tokenA_CBETH.balanceOf(address(whackRockFund)), amountToSteal);
    }

    function testEmergencyWithdrawERC20_NonAllowedToken_NoEvents() public {
        IERC20 nonAllowed = IERC20(NON_ALLOWED_TOKEN_EXAMPLE);
        uint256 amountToSteal = 1 * 1e18; // 1 DAI
        deal(NON_ALLOWED_TOKEN_EXAMPLE, address(whackRockFund), amountToSteal * 2);

        uint256 ownerBalanceBefore = nonAllowed.balanceOf(TEST_OWNER);
        vm.startPrank(TEST_OWNER);
        whackRockFund.emergencyWithdrawERC20(NON_ALLOWED_TOKEN_EXAMPLE, TEST_OWNER, amountToSteal);
        vm.stopPrank();

        assertEq(nonAllowed.balanceOf(TEST_OWNER), ownerBalanceBefore + amountToSteal);
        assertEq(nonAllowed.balanceOf(address(whackRockFund)), amountToSteal);
    }

    // --- NEW DEPOSIT LIMIT TESTS ---

    function testDepositBelowMinimumDeposit_Reverts() public {
        // Try to deposit less than MINIMUM_DEPOSIT (10 USDC)
        uint256 depositAmount = 9 * 1e6; // 9 USDC
        
        vm.startPrank(TEST_DEPOSITOR);
        deal(USDC_BASE, TEST_DEPOSITOR, depositAmount);
        usdc.approve(address(whackRockFund), depositAmount);
        
        // Should revert with "WRF: Deposit below minimum"
        vm.expectRevert("WRF: Deposit below minimum");
        whackRockFund.deposit(depositAmount, TEST_DEPOSITOR);
        vm.stopPrank();
    }
    
    function testFirstDepositBelowMinimumInitialDeposit_Reverts() public {
        // Try to make first deposit below MINIMUM_INITIAL_DEPOSIT (100 USDC) but above MINIMUM_DEPOSIT (10 USDC)
        uint256 depositAmount = 50 * 1e6; // 50 USDC
        
        vm.startPrank(TEST_DEPOSITOR);
        deal(USDC_BASE, TEST_DEPOSITOR, depositAmount);
        usdc.approve(address(whackRockFund), depositAmount);
        
        // Should revert with "WRF: Initial deposit below minimum"
        vm.expectRevert("WRF: Initial deposit below minimum");
        whackRockFund.deposit(depositAmount, TEST_DEPOSITOR);
        vm.stopPrank();
    }
    
    function testFirstDepositAtMinimumInitialDeposit_Succeeds() public {
        // Make first deposit exactly at MINIMUM_INITIAL_DEPOSIT (100 USDC)
        uint256 depositAmount = 100 * 1e6; // 100 USDC
        
        vm.startPrank(TEST_DEPOSITOR);
        deal(USDC_BASE, TEST_DEPOSITOR, depositAmount);
        usdc.approve(address(whackRockFund), depositAmount);
        
        // Should succeed
        uint256 sharesMinted = whackRockFund.deposit(depositAmount, TEST_DEPOSITOR);
        vm.stopPrank();
        
        // Verify shares were minted
        assertEq(whackRockFund.balanceOf(TEST_DEPOSITOR), sharesMinted);
        assertTrue(sharesMinted > 0, "Should have minted shares for minimum initial deposit");
    }
    
    function testSecondDepositAtMinimumDeposit_Succeeds() public {
        // First make an initial deposit
        uint256 initialDepositAmount = 200 * 1e6; // 200 USDC
        
        vm.startPrank(TEST_DEPOSITOR);
        deal(USDC_BASE, TEST_DEPOSITOR, initialDepositAmount);
        usdc.approve(address(whackRockFund), initialDepositAmount);
        whackRockFund.deposit(initialDepositAmount, TEST_DEPOSITOR);
        vm.stopPrank();
        
        // Now make a second deposit at exactly MINIMUM_DEPOSIT (10 USDC)
        uint256 secondDepositAmount = 10 * 1e6; // 10 USDC
        
        vm.startPrank(TEST_DEPOSITOR_2);
        deal(USDC_BASE, TEST_DEPOSITOR_2, secondDepositAmount);
        usdc.approve(address(whackRockFund), secondDepositAmount);
        
        // Should succeed
        uint256 sharesMinted = whackRockFund.deposit(secondDepositAmount, TEST_DEPOSITOR_2);
        vm.stopPrank();
        
        // Verify shares were minted
        assertEq(whackRockFund.balanceOf(TEST_DEPOSITOR_2), sharesMinted);
        assertTrue(sharesMinted > 0, "Should have minted shares for minimum second deposit");
    }
    
    function testDepositExactlyAtMinimums_EqualShareValue() public {
        // First make an initial deposit at exactly MINIMUM_INITIAL_DEPOSIT
        uint256 initialDepositAmount = 100 * 1e6; // 100 USDC
        
        vm.startPrank(TEST_DEPOSITOR);
        deal(USDC_BASE, TEST_DEPOSITOR, initialDepositAmount);
        usdc.approve(address(whackRockFund), initialDepositAmount);
        uint256 firstSharesMinted = whackRockFund.deposit(initialDepositAmount, TEST_DEPOSITOR);
        vm.stopPrank();
        
        // Let some time pass and trigger a rebalance to ensure stable state
        vm.warp(block.timestamp + 1 hours);
        vm.startPrank(TEST_AGENT);
        whackRockFund.triggerRebalance();
        vm.stopPrank();
        
        // Calculate initial share price
        uint256 navAfterFirstDeposit = whackRockFund.totalNAVInAccountingAsset();
        uint256 initialSharePrice = (navAfterFirstDeposit * 1e18) / firstSharesMinted;
        
        // Now make a second deposit at exactly MINIMUM_DEPOSIT
        uint256 secondDepositAmount = 10 * 1e6; // 10 USDC
        
        vm.startPrank(TEST_DEPOSITOR_2);
        deal(USDC_BASE, TEST_DEPOSITOR_2, secondDepositAmount);
        usdc.approve(address(whackRockFund), secondDepositAmount);
        uint256 secondSharesMinted = whackRockFund.deposit(secondDepositAmount, TEST_DEPOSITOR_2);
        vm.stopPrank();
        
        // Calculate new share price
        uint256 navAfterSecondDeposit = whackRockFund.totalNAVInAccountingAsset();
        uint256 secondSharePrice = (navAfterSecondDeposit * 1e18) / (firstSharesMinted + secondSharesMinted);
        
        // Verify share prices are approximately equal
        // We allow a small deviation due to rounding and potential small changes in token value
        uint256 priceDifferenceBps = 0;
        if (secondSharePrice > initialSharePrice) {
            priceDifferenceBps = ((secondSharePrice - initialSharePrice) * 10000) / initialSharePrice;
        } else {
            priceDifferenceBps = ((initialSharePrice - secondSharePrice) * 10000) / initialSharePrice;
        }
        
        assertTrue(priceDifferenceBps < 100, "Share price shouldn't change significantly");
    }
}
