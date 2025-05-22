// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";

// Adjust import paths based on your project structure
import {WhackRockFundRegistry, IWhackRockFundRegistry} from "../src/WhackRockFundRegistry.sol";
import {WhackRockFund} from "../src/WhackRockFundV5_ERC4626_Aerodrome_SubGEvents.sol"; // Assuming this is the correct WhackRockFund
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IAerodromeRouter} from "../src/interfaces/IRouter.sol";
import {IWhackRockFund} from "../src/interfaces/IWhackRockFund.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

// --- Mainnet Addresses (BASE MAINNET) ---
address constant AERODROME_ROUTER_ADDRESS_BASE = 0xcF77a3Ba9A5CA399B7c97c74d54e5b1Beb874E43; // Verify this is correct for Base
address constant WETH_ADDRESS_BASE = 0x4200000000000000000000000000000000000006; // Official WETH on Base

// Example ERC20 tokens on Base for testing allowed list
address constant USDC_BASE = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
address constant CBETH_BASE = 0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf; // As per previous successful traces
address constant VIRTU_BASE = 0x0b3e328455c4059EEb9e3f84b5543F74E24e7E1b;
address constant ANOTHER_TOKEN_BASE = 0xd9aAEc86B65D86f6A7B5B1b0c42FFA531710b6CA; // Example: DAI on Base

// Test accounts
address constant REGISTRY_OWNER = address(0x1000);
address constant FUND_CREATOR_1 = address(0x2000);
address constant FUND_CREATOR_2 = address(0x3000);
address constant TEST_AGENT = address(0x4000);
address constant NON_OWNER = address(0x5000);

uint256 constant MAX_INITIAL_TOKENS_FOR_FUND = 5;

contract WhackRockFundRegistryTest is Test {
    WhackRockFundRegistry public registry;
    IAerodromeRouter public aerodromeRouter = IAerodromeRouter(AERODROME_ROUTER_ADDRESS_BASE);

    function setUp() public {
        vm.startPrank(REGISTRY_OWNER);
        registry = new WhackRockFundRegistry(
            REGISTRY_OWNER,
            AERODROME_ROUTER_ADDRESS_BASE,
            MAX_INITIAL_TOKENS_FOR_FUND
        );
        // Pre-populate registry's allowed tokens list for tests
        registry.addRegistryAllowedToken(USDC_BASE);
        registry.addRegistryAllowedToken(CBETH_BASE);
        registry.addRegistryAllowedToken(VIRTU_BASE);
        vm.stopPrank();
    }

    function testDeployment() public view {
        assertEq(registry.owner(), REGISTRY_OWNER, "Registry owner mismatch");
        assertEq(address(registry.aerodromeRouter()), AERODROME_ROUTER_ADDRESS_BASE, "Aerodrome router mismatch");
        assertEq(registry.WETH_ADDRESS(), WETH_ADDRESS_BASE, "WETH address mismatch");
        assertEq(registry.maxInitialAllowedTokensLength(), MAX_INITIAL_TOKENS_FOR_FUND, "Max initial tokens length mismatch");
        assertEq(registry.getDeployedFundsCount(), 0, "Initial fund count should be 0");
    }

    // --- Owner Functions Tests ---

    function testOwnerCanAddRegistryAllowedToken() public {
        vm.startPrank(REGISTRY_OWNER);
        vm.expectEmit(true, false, false, false, address(registry)); // Check token address
        emit IWhackRockFundRegistry.RegistryAllowedTokenAdded(ANOTHER_TOKEN_BASE);
        registry.addRegistryAllowedToken(ANOTHER_TOKEN_BASE);
        vm.stopPrank();
        assertTrue(registry.isTokenAllowedInRegistry(ANOTHER_TOKEN_BASE), "Token should be allowed");
        address[] memory allowedList = registry.getRegistryAllowedTokens();
        bool found = false;
        for (uint i = 0; i < allowedList.length; i++) {
            if (allowedList[i] == ANOTHER_TOKEN_BASE) {
                found = true;
                break;
            }
        }
        assertTrue(found, "Token not found in getRegistryAllowedTokens array");
    }

    function test_RevertAddRegistryAllowedToken_NotOwner() public {
        vm.startPrank(NON_OWNER);
        vm.expectRevert();
        registry.addRegistryAllowedToken(ANOTHER_TOKEN_BASE);
        vm.stopPrank();
    }

    function test_RevertAddRegistryAllowedToken_ZeroAddress() public {
        vm.startPrank(REGISTRY_OWNER);
        vm.expectRevert("Registry: Token cannot be zero address");
        registry.addRegistryAllowedToken(address(0));
        vm.stopPrank();
    }

    function test_RevertAddRegistryAllowedToken_WETH() public {
        vm.startPrank(REGISTRY_OWNER);
        vm.expectRevert("Registry: WETH cannot be an allowed token");
        registry.addRegistryAllowedToken(WETH_ADDRESS_BASE);
        vm.stopPrank();
    }

    function test_RevertAddRegistryAllowedToken_AlreadyAllowed() public {
        vm.startPrank(REGISTRY_OWNER);
        // USDC_BASE was added in setUp
        vm.expectRevert("Registry: Token already allowed");
        registry.addRegistryAllowedToken(USDC_BASE);
        vm.stopPrank();
    }

    function testOwnerCanRemoveRegistryAllowedToken() public {
        vm.startPrank(REGISTRY_OWNER);
        // USDC_BASE was added in setUp
        assertTrue(registry.isTokenAllowedInRegistry(USDC_BASE), "USDC should be allowed initially");
        vm.expectEmit(true, false, false, false, address(registry));
        emit IWhackRockFundRegistry.RegistryAllowedTokenRemoved(USDC_BASE);
        registry.removeRegistryAllowedToken(USDC_BASE);
        vm.stopPrank();
        assertFalse(registry.isTokenAllowedInRegistry(USDC_BASE), "Token should be removed");
    }

    function test_RevertRemoveRegistryAllowedToken_NotOwner() public {
        vm.startPrank(NON_OWNER);
        vm.expectRevert();
        registry.removeRegistryAllowedToken(USDC_BASE);
        vm.stopPrank();
    }

    function test_RevertRemoveRegistryAllowedToken_NotInList() public {
        vm.startPrank(REGISTRY_OWNER);
        vm.expectRevert("Registry: Token not in allowed list");
        registry.removeRegistryAllowedToken(ANOTHER_TOKEN_BASE); // Not added yet in this specific test flow
        vm.stopPrank();
    }
    
    function testOwnerCanSetMaxInitialAllowedTokensLength() public {
        uint256 newLength = 10;
        vm.startPrank(REGISTRY_OWNER);
        vm.expectEmit(false, false, false, true, address(registry)); // Check newLength
        emit IWhackRockFundRegistry.MaxInitialAllowedTokensLengthUpdated(newLength);
        registry.setMaxInitialAllowedTokensLength(newLength);
        vm.stopPrank();
        assertEq(registry.maxInitialAllowedTokensLength(), newLength, "Max length not updated");
    }

    function test_RevertSetMaxInitialAllowedTokensLength_NotOwner() public {
        vm.startPrank(NON_OWNER);
        vm.expectRevert();
        registry.setMaxInitialAllowedTokensLength(10);
        vm.stopPrank();
    }

     function test_RevertSetMaxInitialAllowedTokensLength_Zero() public {
        vm.startPrank(REGISTRY_OWNER);
        vm.expectRevert("Registry: Max length must be > 0");
        registry.setMaxInitialAllowedTokensLength(0);
        vm.stopPrank();
    }

    // --- createWhackRockFund Tests ---

    function testCreateWhackRockFund_Success() public {
        vm.startPrank(FUND_CREATOR_1);
        address[] memory fundTokens = new address[](2);
        fundTokens[0] = USDC_BASE;
        fundTokens[1] = CBETH_BASE;

        uint256[] memory fundWeights = new uint256[](2);
        fundWeights[0] = 5000;
        fundWeights[1] = 5000;

        string memory vaultName = "MyFirstFund";
        string memory vaultSymbol = "MFF";

        // // Expect WhackRockFundCreated event
        // // We can check indexed fields: fundId, fundAddress, creator
        // // Data fields are harder to match exactly without knowing fundAddress beforehand for fundId.
        // // Let's check creator and that an event is emitted.
        // vm.expectEmit(false, true, true, false, address(registry)); // check fundAddress, creator
        // emit IWhackRockFundRegistry.WhackRockFundCreated(0, address(0), FUND_CREATOR_1, TEST_AGENT, vaultName, vaultSymbol, fundTokens, fundWeights, 0);

        address fundAddress = registry.createWhackRockFund(
            TEST_AGENT,
            fundTokens,
            fundWeights,
            vaultName,
            vaultSymbol
        );
        vm.stopPrank();

        assertTrue(fundAddress != address(0), "Fund address should not be zero");
        assertEq(registry.getDeployedFundsCount(), 1, "Fund count should be 1");
        assertEq(registry.getFundAddressByIndex(0), fundAddress, "Fund address mismatch in array");
        assertEq(registry.fundToCreator(fundAddress), FUND_CREATOR_1, "Fund creator mismatch");
        assertTrue(registry.isSymbolTaken(vaultSymbol), "Symbol should be marked as taken");
        assertEq(registry.fundCounter(), 1, "Fund counter mismatch");

        // Interact with the created fund to check owner and agent
        WhackRockFund createdFund = WhackRockFund(payable(fundAddress));
        assertEq(createdFund.owner(), FUND_CREATOR_1, "New fund owner should be creator");
        assertEq(createdFund.agent(), TEST_AGENT, "New fund agent mismatch");
    }

    function test_RevertCreateWhackRockFund_SymbolTaken() public {
        // First fund
        vm.startPrank(FUND_CREATOR_1);
        address[] memory fundTokens = new address[](1);
        fundTokens[0] = USDC_BASE;
        uint256[] memory fundWeights = new uint256[](1);
        fundWeights[0] = 10000;
        registry.createWhackRockFund(TEST_AGENT, fundTokens, fundWeights, "FundOne", "FONE");
        vm.stopPrank();

        // Attempt to create another fund with the same symbol
        vm.startPrank(FUND_CREATOR_2);
        vm.expectRevert("Registry: Vault symbol already taken");
        registry.createWhackRockFund(TEST_AGENT, fundTokens, fundWeights, "FundTwo", "FONE");
        vm.stopPrank();
    }

    function test_RevertCreateWhackRockFund_ExceedsMaxTokens() public {
        vm.startPrank(REGISTRY_OWNER);
        registry.setMaxInitialAllowedTokensLength(1); // Set max to 1 for this test
        vm.stopPrank();

        vm.startPrank(FUND_CREATOR_1);
        address[] memory fundTokens = new address[](2); // Attempting to use 2 tokens
        fundTokens[0] = USDC_BASE;
        fundTokens[1] = CBETH_BASE;
        uint256[] memory fundWeights = new uint256[](2);
        fundWeights[0] = 5000;
        fundWeights[1] = 5000;

        vm.expectRevert("Registry: Exceeds max allowed tokens for a fund");
        registry.createWhackRockFund(TEST_AGENT, fundTokens, fundWeights, "FundX", "FX");
        vm.stopPrank();
    }

    function test_RevertCreateWhackRockFund_TokenNotAllowedByRegistry() public {
        vm.startPrank(FUND_CREATOR_1);
        address[] memory fundTokens = new address[](1);
        fundTokens[0] = ANOTHER_TOKEN_BASE; // This token is not in registry's allowedTokensList by default
        uint256[] memory fundWeights = new uint256[](1);
        fundWeights[0] = 10000;

        vm.expectRevert("Registry: Fund token not allowed by registry");
        registry.createWhackRockFund(TEST_AGENT, fundTokens, fundWeights, "FundY", "FY");
        vm.stopPrank();
    }
    
    function test_RevertCreateWhackRockFund_EmptySymbol() public {
        vm.startPrank(FUND_CREATOR_1);
        address[] memory fundTokens = new address[](1);
        fundTokens[0] = USDC_BASE;
        uint256[] memory fundWeights = new uint256[](1);
        fundWeights[0] = 10000;

        vm.expectRevert("Registry: Vault symbol cannot be empty");
        registry.createWhackRockFund(TEST_AGENT, fundTokens, fundWeights, "FundZ", "");
        vm.stopPrank();
    }

    function test_RevertCreateWhackRockFund_NoTokens() public {
        vm.startPrank(FUND_CREATOR_1);
        address[] memory fundTokens = new address[](0);
        uint256[] memory fundWeights = new uint256[](0);

        vm.expectRevert("Registry: Fund must have at least one token");
        registry.createWhackRockFund(TEST_AGENT, fundTokens, fundWeights, "FundEmpty", "FEMP");
        vm.stopPrank();
    }


    // --- Getter Functions ---
    function testGetters() public {
        // Add some registry allowed tokens
        vm.startPrank(REGISTRY_OWNER);
        registry.addRegistryAllowedToken(ANOTHER_TOKEN_BASE);
        vm.stopPrank();

        address[] memory registryAllowed = registry.getRegistryAllowedTokens();
        // Initial 3 from setUp + 1 added here
        assertEq(registryAllowed.length, 4, "Registry allowed tokens count mismatch"); 

        // Create a fund to test fund-related getters
        vm.startPrank(FUND_CREATOR_1);
        address[] memory fundTokens = new address[](1);
        fundTokens[0] = USDC_BASE;
        uint256[] memory fundWeights = new uint256[](1);
        fundWeights[0] = 10000;
        address fundAddr = registry.createWhackRockFund(TEST_AGENT, fundTokens, fundWeights, "GetterFund", "GF");
        vm.stopPrank();

        assertEq(registry.getDeployedFundsCount(), 1, "Deployed fund count after creation mismatch");
        assertEq(registry.getFundAddressByIndex(0), fundAddr, "getFundAddressByIndex mismatch");
        vm.expectRevert("Registry: Index out of bounds");
        registry.getFundAddressByIndex(1); // Test out of bounds
    }
}
