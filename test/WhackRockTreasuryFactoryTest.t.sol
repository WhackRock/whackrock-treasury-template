// test/WhackRockTreasuryFactoryTest.t.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/core/WhackRockTreasuryFactory.sol";
import "../src/core/WeightedTreasuryVault.sol";
import "../src/core/interfaces/ISwapAdapter.sol";
import "../src/core/interfaces/IPriceOracle.sol";
import "./mocks/MockERC20.sol";
import "./mocks/MockSwapAdapter.sol";
import "./mocks/MockPriceOracle.sol";

contract WhackRockTreasuryFactoryTest is Test {
    WhackRockTreasuryFactory public factory;
    MockERC20 public usdc;
    MockERC20 public eth;
    MockERC20 public btc;
    MockERC20 public link;
    MockSwapAdapter public adapter;
    MockPriceOracle public oracle;
    address public owner;
    address public devWallet;
    address public wrkRewards;
    address public user;

    // Events
    event VaultCreated(
        address vault,
        address manager,
        address[] allowedAssetsSubset,
        uint256[] weights,
        bytes32 tag,
        address creator
    );
    
    
    event AllowedAssetsUpdated(address[] newAssets);
    
    event USDCbUpdated(address indexed oldUSDCb, address indexed newUSDCb);
    
    event AdapterUpdated(address indexed oldAdapter, address indexed newAdapter);
    
    event OracleUpdated(address indexed oldOracle, address indexed newOracle);
    
    event WrkRewardsUpdated(address indexed oldWrkRewards, address indexed newWrkRewards);

    function setUp() public {
        owner = address(this);
        devWallet = address(0xDEAD);
        wrkRewards = address(0xBEEF);
        user = address(0x1);

        // Deploy mock tokens
        usdc = new MockERC20("USDC", "USDC", 6);
        eth = new MockERC20("ETH", "ETH", 18);
        btc = new MockERC20("BTC", "BTC", 8);
        link = new MockERC20("LINK", "LINK", 18);

        // Deploy mock adapter and oracle
        adapter = new MockSwapAdapter();
        oracle = new MockPriceOracle();

        // Set up test prices
        oracle.setPrice(address(0), 2000 * 10**18); // ETH price = $2000
        oracle.setPrice(address(usdc), 1 * 10**18);  // USDC price = $1
        oracle.setPrice(address(btc), 60000 * 10**18); // BTC price = $60000
        oracle.setPrice(address(link), 20 * 10**18); // LINK price = $20

        // Create allowed assets array
        address[] memory allowedAssets = new address[](4);
        allowedAssets[0] = address(eth);
        allowedAssets[1] = address(btc);
        allowedAssets[2] = address(usdc);
        allowedAssets[3] = address(link);

        // Deploy factory
        factory = new WhackRockTreasuryFactory(
            address(usdc),             // USDC as base asset
            allowedAssets,             // allowed assets
            ISwapAdapter(address(adapter)), // adapter
            IPriceOracle(address(oracle)), // oracle
            wrkRewards                 // WRK rewards
        );

        // Transfer some tokens to user for testing
        usdc.mint(user, 10000 * 10**6);  // 10,000 USDC
        eth.mint(user, 10 * 10**18);     // 10 ETH
        btc.mint(user, 1 * 10**8);       // 1 BTC
        link.mint(user, 100 * 10**18);   // 100 LINK
    }

    function test__Initialization() public view {
        assertEq(factory.USDCb(), address(usdc), "USDCb not set correctly");
        assertEq(address(factory.adapter()), address(adapter), "Adapter not set correctly");
        assertEq(address(factory.oracle()), address(oracle), "Oracle not set correctly");
        assertEq(factory.wrkRewards(), wrkRewards, "WRK rewards not set correctly");
        
        // Check allowedAssets
        assertEq(factory.allowedAssets(0), address(eth), "ETH not in allowed assets");
        assertEq(factory.allowedAssets(1), address(btc), "BTC not in allowed assets");
        assertEq(factory.allowedAssets(2), address(usdc), "USDC not in allowed assets");
        assertEq(factory.allowedAssets(3), address(link), "LINK not in allowed assets");
        
        // Check registry state
        assertEq(factory.getTreasuryCount(), 0, "Initial treasury count should be 0");
    }

    function test__CreateVault() public {
        // Create a subset of allowed assets
        address[] memory vaultAssets = new address[](3);
        vaultAssets[0] = address(eth);
        vaultAssets[1] = address(btc);
        vaultAssets[2] = address(usdc);

        // Create weights
        uint256[] memory weights = new uint256[](3);
        weights[0] = 4000; // 40% ETH
        weights[1] = 3000; // 30% BTC
        weights[2] = 3000; // 30% USDC

        string memory vaultName = "Test Vault";
        string memory vaultSymbol = "TSTVLT";
        
        // Create vault - don't check event here since we can't easily predict the vault address
        address payable vault = payable(factory.createWhackRockVault(
            vaultName,
            vaultSymbol,
            vaultAssets,
            weights,
            address(this),    // manager
            200,              // 2% management fee
            devWallet,        // dev wallet
            "AGENT"           // tag
        ));
        
        // Verify vault is created
        assertNotEq(vault, address(0), "Vault should be created");
        
        // Verify registry state
        assertEq(factory.getTreasuryCount(), 1, "Treasury count should be 1");
        assertEq(factory.getAllTreasuries()[0], vault, "Vault should be in treasuries list");
        assertEq(factory.treasuryNames(vaultName), vault, "Vault should be in name mapping");
        assertTrue(factory.isTreasuryNameTaken(vaultName), "Treasury name should be taken");
        
        // Verify vault properties
        WeightedTreasuryVault vaultContract = WeightedTreasuryVault(vault);
        assertEq(vaultContract.USDCb(), address(usdc), "USDCb not set in vault");
        assertEq(vaultContract.manager(), address(this), "Manager not set in vault");
        assertEq(vaultContract.devWallet(), devWallet, "Dev wallet not set in vault");
        assertEq(vaultContract.wrkRewards(), wrkRewards, "WRK rewards not set in vault");
        assertEq(vaultContract.mgmtFeeBps(), 200, "Management fee not set in vault");
        
        // Verify vault weights
        assertEq(vaultContract.targetWeights(0), 4000, "Weights not set correctly in vault");
        assertEq(vaultContract.targetWeights(1), 3000, "Weights not set correctly in vault");
        assertEq(vaultContract.targetWeights(2), 3000, "Weights not set correctly in vault");
    }
    
    function test_RevertCreateVaultWithDuplicateName() public {
        // Create first vault
        address[] memory vaultAssets = new address[](3);
        vaultAssets[0] = address(eth);
        vaultAssets[1] = address(btc);
        vaultAssets[2] = address(usdc);

        uint256[] memory weights = new uint256[](3);
        weights[0] = 4000;
        weights[1] = 3000;
        weights[2] = 3000;

        string memory vaultName = "Duplicate Name";
        
        factory.createWhackRockVault(
            vaultName,
            "TSTVLT",
            vaultAssets,
            weights,
            address(this),
            200,
            devWallet,
            "AGENT"
        );
        
        // Try to create second vault with same name
        vm.expectRevert("Treasury name already taken");
        factory.createWhackRockVault(
            vaultName,
            "TSTVLT2",
            vaultAssets,
            weights,
            address(this),
            200,
            devWallet,
            "AGENT"
        );
    }
    
    function test__CreateMultipleVaults() public {
        // Create first vault
        address[] memory vaultAssets1 = new address[](3);
        vaultAssets1[0] = address(eth);
        vaultAssets1[1] = address(btc);
        vaultAssets1[2] = address(usdc);

        uint256[] memory weights1 = new uint256[](3);
        weights1[0] = 4000;
        weights1[1] = 3000;
        weights1[2] = 3000;
        
        address vault1 = factory.createWhackRockVault(
            "First Vault",
            "FIRST",
            vaultAssets1,
            weights1,
            address(this),
            200,
            devWallet,
            "AGENT"
        );
        
        // Create second vault with different assets
        address[] memory vaultAssets2 = new address[](3);
        vaultAssets2[0] = address(link);
        vaultAssets2[1] = address(btc);
        vaultAssets2[2] = address(usdc);

        uint256[] memory weights2 = new uint256[](3);
        weights2[0] = 2000;
        weights2[1] = 3000;
        weights2[2] = 5000;
        
        address vault2 = factory.createWhackRockVault(
            "Second Vault",
            "SECOND",
            vaultAssets2,
            weights2,
            address(this),
            300,
            devWallet,
            "FUND"
        );
        
        // Verify registry state
        assertEq(factory.getTreasuryCount(), 2, "Treasury count should be 2");
        address[] memory treasuries = factory.getAllTreasuries();
        assertEq(treasuries.length, 2, "Treasuries array should have 2 elements");
        assertEq(treasuries[0], vault1, "First vault should be in treasuries list");
        assertEq(treasuries[1], vault2, "Second vault should be in treasuries list");
        
        // Verify name mapping
        assertEq(factory.treasuryNames("First Vault"), vault1, "First vault not mapped to name");
        assertEq(factory.treasuryNames("Second Vault"), vault2, "Second vault not mapped to name");
        
        // Verify vault access through index
        assertEq(factory.treasuries(0), vault1, "First vault not accessible by index");
        assertEq(factory.treasuries(1), vault2, "Second vault not accessible by index");
    }
    
    function test__SetUSDCb() public {
        // Create a new USDC token
        MockERC20 newUsdc = new MockERC20("USDC.b v2", "USDCb2", 6);
        
        // Expect event
        vm.expectEmit(true, true, false, false);
        emit USDCbUpdated(address(usdc), address(newUsdc));
        
        // Update USDCb
        factory.setUSDCb(address(newUsdc));
        
        // Verify USDCb updated
        assertEq(factory.USDCb(), address(newUsdc), "USDCb not updated");
        
        // Verify USDCb is in allowedAssets
        bool found = false;
        address[] memory assets = factory.getAllowedAssets();
        for (uint i = 0; i < assets.length; i++) {
            if (assets[i] == address(newUsdc)) {
                found = true;
                break;
            }
        }
        assertTrue(found, "New USDCb should be in allowed assets");
    }
    
    function test__SetAdapter() public {
        // Create a new adapter
        MockSwapAdapter newAdapter = new MockSwapAdapter();
        
        // Expect event
        vm.expectEmit(true, true, false, false);
        emit AdapterUpdated(address(adapter), address(newAdapter));
        
        // Update adapter
        factory.setAdapter(ISwapAdapter(address(newAdapter)));
        
        // Verify adapter updated
        assertEq(address(factory.adapter()), address(newAdapter), "Adapter not updated");
    }
    
    function test__SetOracle() public {
        // Create a new oracle
        MockPriceOracle newOracle = new MockPriceOracle();
        
        // Expect event
        vm.expectEmit(true, true, false, false);
        emit OracleUpdated(address(oracle), address(newOracle));
        
        // Update oracle
        factory.setOracle(IPriceOracle(address(newOracle)));
        
        // Verify oracle updated
        assertEq(address(factory.oracle()), address(newOracle), "Oracle not updated");
    }
    
    function test__SetWrkRewards() public {
        address newRewards = address(0xCAFE);
        
        // Expect event
        vm.expectEmit(true, true, false, false);
        emit WrkRewardsUpdated(wrkRewards, newRewards);
        
        // Update rewards
        factory.setWrkRewards(newRewards);
        
        // Verify rewards updated
        assertEq(factory.wrkRewards(), newRewards, "WRK rewards not updated");
    }
    
    function test__SetAllowedAssets() public {
        // Create new allowed assets list
        address[] memory newAssets = new address[](2);
        newAssets[0] = address(eth);
        newAssets[1] = address(usdc);
        
        // Expect event
        vm.expectEmit(true, false, false, false);
        emit AllowedAssetsUpdated(newAssets);
        
        // Update allowed assets
        factory.setAllowedAssets(newAssets);
        
        // Verify allowed assets updated
        address[] memory assets = factory.getAllowedAssets();
        assertEq(assets.length, 2, "Allowed assets length incorrect");
        assertEq(assets[0], address(eth), "ETH not in allowed assets");
        assertEq(assets[1], address(usdc), "USDC not in allowed assets");
    }
    
    function test__AddAllowedAsset() public {
        // Create a new token
        MockERC20 newToken = new MockERC20("New Token", "NEW", 18);
        
        // Get current allowed assets length
        uint256 initialLength = factory.getAllowedAssets().length;
        
        // Add new token to allowed assets
        factory.addAllowedAsset(address(newToken));
        
        // Verify allowed assets updated
        address[] memory assets = factory.getAllowedAssets();
        assertEq(assets.length, initialLength + 1, "Allowed assets length incorrect");
        assertEq(assets[initialLength], address(newToken), "New token not added to allowed assets");
    }
    
    function test__DeleteAllowedAsset() public {
        // Delete link token from allowed assets
        factory.deleteAllowedAsset(address(link));
        
        // Verify allowed assets updated
        address[] memory assets = factory.getAllowedAssets();
        assertEq(assets.length, 3, "Allowed assets length incorrect after deletion");
        
        // Check link is not in the assets anymore
        bool found = false;
        for (uint i = 0; i < assets.length; i++) {
            if (assets[i] == address(link)) {
                found = true;
                break;
            }
        }
        assertFalse(found, "LINK should be removed from allowed assets");
    }
    
    function test_RevertDeleteUSDCb() public {
        // Try to delete USDCb
        vm.expectRevert("cannot remove USDC.b");
        factory.deleteAllowedAsset(address(usdc));
    }
    
    function test_RevertOwnerOperations() public {
        // Create non-owner user
        address nonOwner = address(0x2);
        
        // Try to set USDCb as non-owner
        vm.startPrank(nonOwner);
        
        // For OpenZeppelin 4.x, the revert message format has changed
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", nonOwner));
        factory.setUSDCb(address(0x3));
        
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", nonOwner));
        factory.setAdapter(ISwapAdapter(address(0x3)));
        
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", nonOwner));
        factory.setOracle(IPriceOracle(address(0x3)));
        
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", nonOwner));
        factory.setWrkRewards(address(0x3));
        
        // Try to set/add/delete allowed assets as non-owner
        address[] memory newAssets = new address[](2);
        newAssets[0] = address(eth);
        newAssets[1] = address(usdc);
        
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", nonOwner));
        factory.setAllowedAssets(newAssets);
        
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", nonOwner));
        factory.addAllowedAsset(address(0x3));
        
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", nonOwner));
        factory.deleteAllowedAsset(address(eth));
        
        vm.stopPrank();
    }
    
    function test_RevertCreateVaultWithInvalidAssets() public {
        // Try to create vault with asset that is not in allowed assets
        address[] memory vaultAssets = new address[](3);
        vaultAssets[0] = address(eth);
        vaultAssets[1] = address(0x3); // Invalid asset
        vaultAssets[2] = address(usdc);

        uint256[] memory weights = new uint256[](3);
        weights[0] = 4000;
        weights[1] = 3000;
        weights[2] = 3000;
        
        vm.expectRevert("asset not allowed");
        factory.createWhackRockVault(
            "Invalid Asset Vault",
            "INVALID",
            vaultAssets,
            weights,
            address(this),
            200,
            devWallet,
            "AGENT"
        );
    }
    
    function test_RevertCreateVaultWithInvalidWeights() public {
        // Try to create vault with weights that don't sum to 10000
        address[] memory vaultAssets = new address[](3);
        vaultAssets[0] = address(eth);
        vaultAssets[1] = address(btc);
        vaultAssets[2] = address(usdc);

        uint256[] memory weights = new uint256[](3);
        weights[0] = 4000;
        weights[1] = 3000;
        weights[2] = 2000; // Total: 9000, not 10000
        
        vm.expectRevert("weights");
        factory.createWhackRockVault(
            "Invalid Weights Vault",
            "INVALID",
            vaultAssets,
            weights,
            address(this),
            200,
            devWallet,
            "AGENT"
        );
    }
    
    function test_RevertCreateVaultWithoutUSDCb() public {
        // Try to create vault without USDCb
        address[] memory vaultAssets = new address[](2);
        vaultAssets[0] = address(eth);
        vaultAssets[1] = address(btc);

        uint256[] memory weights = new uint256[](2);
        weights[0] = 5000;
        weights[1] = 5000;
        
        vm.expectRevert("must include USDC.b");
        factory.createWhackRockVault(
            "No USDC Vault",
            "NOUSDC",
            vaultAssets,
            weights,
            address(this),
            200,
            devWallet,
            "AGENT"
        );
    }
} 