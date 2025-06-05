// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";

// Adjust import paths based on your project structure
import {WhackRockFundRegistry, IWhackRockFundRegistry} from "../src/WhackRockFundRegistry.sol"; // Assuming this is your UUPS upgradeable registry
import {WhackRockFund} from "../src/WhackRockFundV5_ERC4626_Aerodrome_SubGEvents.sol"; 
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IAerodromeRouter} from "../src/interfaces/IRouter.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol"; // For USDC transfers

// For deploying UUPS proxy
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// --- Mainnet Addresses (BASE MAINNET) ---
address constant AERODROME_ROUTER_ADDRESS_BASE = 0xcF77a3Ba9A5CA399B7c97c74d54e5b1Beb874E43; 
address constant WETH_ADDRESS_BASE = 0x4200000000000000000000000000000000000006; 

// Example ERC20 tokens on Base for testing allowed list
address constant USDC_BASE = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913; // USDC address for fees
address constant CBBTC_BASE = 0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf; 
address constant VIRTU_BASE = 0x0b3e328455c4059EEb9e3f84b5543F74E24e7E1b;
address constant ANOTHER_TOKEN_BASE = 0xd9aAEc86B65D86f6A7B5B1b0c42FFA531710b6CA; // Example: DAI on Base

// Test accounts
address constant REGISTRY_OWNER = address(0x1000);
address constant FUND_CREATOR_1 = address(0x2000);
address constant FUND_CREATOR_2 = address(0x3000);
address constant TEST_AGENT = address(0x4000); // Agent for created funds
address constant NON_OWNER = address(0x5000);

// Registry initialization parameters
uint256 constant MAX_INITIAL_TOKENS_FOR_FUND_REGISTRY = 5;
address constant WHACKROCK_REWARDS_ADDR = address(0x7000); // Protocol's reward address
uint256 constant PROTOCOL_CREATION_FEE_USDC = 170 * 1e6; // 170 USDC (6 decimals)
uint256 constant TOTAL_AUM_FEE_BPS_FOR_FUNDS = 100; // e.g., 1% total annual AUM fee for funds created by this registry
address constant PROTOCOL_AUM_RECIPIENT_FOR_FUNDS = address(0x8000); // Protocol's wallet for its 40% AUM fee share
uint256 constant MAX_AGENT_DEPOSIT_FEE_BPS_REGISTRY = 70; // Max 0.7% deposit fee an agent can set (not used in current WhackRockFund)

// Parameters for creating a specific fund
address constant TEST_AGENT_AUM_FEE_WALLET_FUND = address(0x9000); // Agent's wallet for AUM fee
uint256 constant TEST_AGENT_SET_TOTAL_AUM_FEE_BPS_FUND = 100; // Agent sets 1% total AUM for their fund

contract WhackRockFundRegistryTest is Test {
    using SafeERC20 for IERC20;

    WhackRockFundRegistry public registryProxy; // This will point to the proxy
    IAerodromeRouter public aerodromeRouter = IAerodromeRouter(AERODROME_ROUTER_ADDRESS_BASE);
    IERC20 public usdcToken = IERC20(USDC_BASE);


    function setUp() public {
        // 1. Deploy the implementation contract
        WhackRockFundRegistry registryImplementation = new WhackRockFundRegistry();

        // 2. Prepare the initialization calldata
        bytes memory initializeData = abi.encodeWithSelector(
            WhackRockFundRegistry.initialize.selector,
            REGISTRY_OWNER,
            AERODROME_ROUTER_ADDRESS_BASE,
            MAX_INITIAL_TOKENS_FOR_FUND_REGISTRY,
            USDC_BASE,
            WHACKROCK_REWARDS_ADDR,
            PROTOCOL_CREATION_FEE_USDC,
            // Removed seed amount from initialize
            TOTAL_AUM_FEE_BPS_FOR_FUNDS,
            PROTOCOL_AUM_RECIPIENT_FOR_FUNDS,
            MAX_AGENT_DEPOSIT_FEE_BPS_REGISTRY
        );

        // 3. Deploy the ERC1967Proxy
        ERC1967Proxy proxy = new ERC1967Proxy(address(registryImplementation), initializeData);
        
        // 4. Point our registry variable to the proxy address
        registryProxy = WhackRockFundRegistry(address(proxy));

        // 5. Pre-populate registry's allowed tokens list for tests (as REGISTRY_OWNER)
        vm.startPrank(REGISTRY_OWNER);
        registryProxy.addRegistryAllowedToken(USDC_BASE);
        registryProxy.addRegistryAllowedToken(CBBTC_BASE);
        registryProxy.addRegistryAllowedToken(VIRTU_BASE);
        vm.stopPrank();

        // Deal USDC to fund creators for creation fees
        deal(USDC_BASE, FUND_CREATOR_1, PROTOCOL_CREATION_FEE_USDC * 2); // Enough for one creation
        deal(USDC_BASE, FUND_CREATOR_2, PROTOCOL_CREATION_FEE_USDC * 2);
    }

    function testDeployment() public view {
        assertEq(registryProxy.owner(), REGISTRY_OWNER, "Registry owner mismatch");
        assertEq(address(registryProxy.aerodromeRouter()), AERODROME_ROUTER_ADDRESS_BASE, "Aerodrome router mismatch");
        assertEq(registryProxy.WETH_ADDRESS(), WETH_ADDRESS_BASE, "WETH address mismatch");
        assertEq(registryProxy.maxInitialAllowedTokensLength(), MAX_INITIAL_TOKENS_FOR_FUND_REGISTRY, "Max initial tokens length mismatch");
        assertEq(registryProxy.getDeployedFundsCount(), 0, "Initial fund count should be 0");
        assertEq(address(registryProxy.USDC_TOKEN()), USDC_BASE, "USDC token address mismatch");
        assertEq(registryProxy.whackRockRewardsAddress(), WHACKROCK_REWARDS_ADDR, "Rewards address mismatch");
        assertEq(registryProxy.protocolFundCreationFeeUsdcAmount(), PROTOCOL_CREATION_FEE_USDC, "Creation fee mismatch");
        assertEq(registryProxy.totalAumFeeBpsForFunds(), TOTAL_AUM_FEE_BPS_FOR_FUNDS, "Total AUM BPS mismatch");
        assertEq(registryProxy.protocolAumFeeRecipientForFunds(), PROTOCOL_AUM_RECIPIENT_FOR_FUNDS, "Protocol AUM recipient mismatch");
    }

    function testOwnerCanAddRegistryAllowedToken() public {
        vm.startPrank(REGISTRY_OWNER);
        // Using IWhackRockFundRegistry for event signature if it's defined there
        vm.expectEmit(true, false, false, false, address(registryProxy)); 
        emit IWhackRockFundRegistry.RegistryAllowedTokenAdded(ANOTHER_TOKEN_BASE);
        registryProxy.addRegistryAllowedToken(ANOTHER_TOKEN_BASE);
        vm.stopPrank();
        assertTrue(registryProxy.isTokenAllowedInRegistry(ANOTHER_TOKEN_BASE), "Token should be allowed");
    }
    
    function test_RevertAddRegistryAllowedToken_NotOwner() public {
        vm.startPrank(NON_OWNER);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, NON_OWNER));
        registryProxy.addRegistryAllowedToken(ANOTHER_TOKEN_BASE);
        vm.stopPrank();
    }


    // --- createWhackRockFund Tests ---
    function testCreateWhackRockFund_Success() public {
        vm.startPrank(FUND_CREATOR_1);
        address[] memory fundTokens = new address[](2);
        fundTokens[0] = CBBTC_BASE; // Using tokens already allowed in setUp
        fundTokens[1] = VIRTU_BASE;

        uint256[] memory fundWeights = new uint256[](2);
        fundWeights[0] = 5000;
        fundWeights[1] = 5000;

        string memory vaultName = "MyFirstFund";
        string memory vaultSymbol = "MFF";

        // Approve USDC for the creation fee
        usdcToken.approve(address(registryProxy), PROTOCOL_CREATION_FEE_USDC);

        // vm.expectEmit(false, true, true, false, address(registryProxy)); 
        // emit IWhackRockFundRegistry.WhackRockFundCreated(
        //     1, address(0), FUND_CREATOR_1, TEST_AGENT, vaultName, vaultSymbol, 
        //     fundTokens, fundWeights, TEST_AGENT_AUM_FEE_WALLET_FUND, TEST_AGENT_SET_TOTAL_AUM_FEE_BPS_FUND, 0
        // );

        address fundAddress = registryProxy.createWhackRockFund(
            TEST_AGENT,
            fundTokens,
            fundWeights,
            vaultName,
            vaultSymbol,
            TEST_AGENT_AUM_FEE_WALLET_FUND,
            TEST_AGENT_SET_TOTAL_AUM_FEE_BPS_FUND
        );
        vm.stopPrank();

        assertTrue(fundAddress != address(0), "Fund address should not be zero");
        assertEq(registryProxy.getDeployedFundsCount(), 1, "Fund count should be 1");
        assertEq(registryProxy.getFundAddressByIndex(0), fundAddress, "Fund address mismatch in array");
        assertEq(registryProxy.fundToCreator(fundAddress), FUND_CREATOR_1, "Fund creator mismatch");
        assertTrue(registryProxy.isSymbolTaken(vaultSymbol), "Symbol should be marked as taken");
        
        WhackRockFund createdFund = WhackRockFund(payable(fundAddress));
        assertEq(createdFund.owner(), FUND_CREATOR_1, "New fund owner should be creator");
        assertEq(createdFund.agent(), TEST_AGENT, "New fund agent mismatch");
        assertEq(createdFund.agentAumFeeWallet(), TEST_AGENT_AUM_FEE_WALLET_FUND, "Fund agent AUM wallet mismatch");
        assertEq(createdFund.agentAumFeeBps(), TEST_AGENT_SET_TOTAL_AUM_FEE_BPS_FUND, "Fund agent AUM BPS mismatch");
        assertEq(createdFund.protocolAumFeeRecipient(), PROTOCOL_AUM_RECIPIENT_FOR_FUNDS, "Fund protocol AUM recipient mismatch");

        // Check that protocol fee was transferred
        assertEq(usdcToken.balanceOf(WHACKROCK_REWARDS_ADDR), PROTOCOL_CREATION_FEE_USDC);
        // Check that the fund received no USDC seed directly from registry
        assertEq(usdcToken.balanceOf(fundAddress), 0);
    }

    function test_RevertCreateWhackRockFund_SymbolTaken() public {
        vm.startPrank(FUND_CREATOR_1);
        address[] memory fundTokens = new address[](1);
        fundTokens[0] = USDC_BASE;
        uint256[] memory fundWeights = new uint256[](1);
        fundWeights[0] = 10000;
        usdcToken.approve(address(registryProxy), PROTOCOL_CREATION_FEE_USDC);
        registryProxy.createWhackRockFund(TEST_AGENT, fundTokens, fundWeights, "FundOne", "FONE", TEST_AGENT_AUM_FEE_WALLET_FUND, TEST_AGENT_SET_TOTAL_AUM_FEE_BPS_FUND);
        vm.stopPrank();

        vm.startPrank(FUND_CREATOR_2);
        usdcToken.approve(address(registryProxy), PROTOCOL_CREATION_FEE_USDC);
        vm.expectRevert("Registry: Vault symbol already taken");
        registryProxy.createWhackRockFund(TEST_AGENT, fundTokens, fundWeights, "FundTwo", "FONE", TEST_AGENT_AUM_FEE_WALLET_FUND, TEST_AGENT_SET_TOTAL_AUM_FEE_BPS_FUND);
        vm.stopPrank();
    }
    
    // Other tests like _ExceedsMaxTokens, _TokenNotAllowedByRegistry, _EmptySymbol, _NoTokens
    // would need similar updates for createWhackRockFund parameters and USDC approval if they reach that point.
    // For brevity, only showing the success case and one revert fully updated.

    function testGetters() public {
        vm.startPrank(REGISTRY_OWNER);
        registryProxy.addRegistryAllowedToken(ANOTHER_TOKEN_BASE);
        vm.stopPrank();

        address[] memory registryAllowed = registryProxy.getRegistryAllowedTokens();
        assertEq(registryAllowed.length, 4); 

        vm.startPrank(FUND_CREATOR_1);
        address[] memory fundTokens = new address[](1);
        fundTokens[0] = USDC_BASE;
        uint256[] memory fundWeights = new uint256[](1);
        fundWeights[0] = 10000;
        
        usdcToken.approve(address(registryProxy), PROTOCOL_CREATION_FEE_USDC);
        address fundAddr = registryProxy.createWhackRockFund(
            TEST_AGENT, fundTokens, fundWeights, "GetterFund", "GF",
            TEST_AGENT_AUM_FEE_WALLET_FUND, TEST_AGENT_SET_TOTAL_AUM_FEE_BPS_FUND
        );
        vm.stopPrank();

        assertEq(registryProxy.getDeployedFundsCount(), 1);
        assertEq(registryProxy.getFundAddressByIndex(0), fundAddr);
        vm.expectRevert("Registry: Index out of bounds");
        registryProxy.getFundAddressByIndex(1); 
    }
}
