// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";

// Contract to be deployed
import {WhackRockFundRegistry} from "../src/WhackRockFundRegistry.sol";

// For deploying UUPS proxy
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployWhackRockFundRegistry is Script {

    // --- START: Configuration for Base Mainnet ---
    // These values should be reviewed and confirmed before mainnet deployment.
    address constant REGISTRY_OWNER = 0x90cfB07A46EE4bb20C970Dda18AaD1BA3c9450Ae; 

    // External Contract Addresses (Base Mainnet)
    address constant AERODROME_ROUTER_ADDRESS_BASE = 0xcF77a3Ba9A5CA399B7c97c74d54e5b1Beb874E43; 
    address constant USDC_BASE_FOR_FEE = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913; // USDC for creation fees & allowed token
    address constant WETH_BASE = 0x4200000000000000000000000000000000000006; // WETH for Base
    address constant CBETH_BASE = 0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf; // cbETH as an allowed token
    address constant VIRTU_BASE = 0x0b3e328455c4059EEb9e3f84b5543F74E24e7E1b; // VIRTU as an allowed token

    // Registry Initialization Parameters (Customize as needed)
    // initialOwner will be msg.sender (the deployer) during initialization
    uint256 constant MAX_INITIAL_TOKENS_FOR_FUND_REGISTRY = 5;
    address constant WHACKROCK_REWARDS_ADDR = address(0x90cfB07A46EE4bb20C970Dda18AaD1BA3c9450Ae); 
    // uint256 constant PROTOCOL_CREATION_FEE_USDC = 170 * 1e6; // 170 USDC (assuming 6 decimals for USDC_BASE_FOR_FEE)
    uint256 constant PROTOCOL_CREATION_FEE_USDC = 0; // 170 USDC (assuming 6 decimals for USDC_BASE_FOR_FEE)
    uint256 constant TOTAL_AUM_FEE_BPS_FOR_FUNDS = 200; // e.g., 1% total annual AUM fee
    address constant PROTOCOL_AUM_FEE_RECIPIENT_FOR_FUNDS = address(0x90cfB07A46EE4bb20C970Dda18AaD1BA3c9450Ae); 
    uint256 constant MAX_AGENT_DEPOSIT_FEE_BPS_REGISTRY = 170; // Max 1.7% deposit fee (not used in current WhackRockFundV5)
    
    // Note: WETH_ADDRESS_BASE is not directly passed to WhackRockFundRegistry initialize, 
    // but it's used by Aerodrome. Ensure your registry logic (if it needs WETH explicitly) gets it correctly.
    // The registry schema expects `wethAddress` to be set, likely via `try_wethAddress()` call.

    // --- END: Configuration ---

    function run() external returns (address registryProxyAddress, address newFundAddress) {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        console.log("Deploying WhackRockFundRegistry implementation...");
        WhackRockFundRegistry registryImplementation = new WhackRockFundRegistry();
        console.log("WhackRockFundRegistry implementation deployed at:", address(registryImplementation));

        // Prepare the initialization calldata
        // The `initialOwner` during initialize() will be the deployerAddress
        bytes memory initializeData = abi.encodeWithSelector(
            WhackRockFundRegistry.initialize.selector,
            deployerAddress, // initialOwner (deployer becomes temporary owner)
            AERODROME_ROUTER_ADDRESS_BASE,
            MAX_INITIAL_TOKENS_FOR_FUND_REGISTRY,
            USDC_BASE_FOR_FEE,
            WHACKROCK_REWARDS_ADDR,
            PROTOCOL_CREATION_FEE_USDC,
            TOTAL_AUM_FEE_BPS_FOR_FUNDS,
            PROTOCOL_AUM_FEE_RECIPIENT_FOR_FUNDS,
            MAX_AGENT_DEPOSIT_FEE_BPS_REGISTRY
        );

        // address _initialOwner,
        // address _aerodromeRouterAddress,
        // uint256 _maxInitialFundTokensLength,
        // address _usdcTokenAddress,
        // address _whackRockRewardsAddr,
        // uint256 _protocolCreationFeeUsdc, 
        // uint256 _totalAumFeeBps,          
        // address _protocolAumRecipient,
        // uint256 _maxAgentDepositFeeBpsAllowed 

        console.log("Deploying ERC1967Proxy for WhackRockFundRegistry...");
        
        // Add a unique salt based on block timestamp to ensure fresh deployment
        bytes32 salt = keccak256(abi.encodePacked(block.timestamp, deployerAddress));
        
        ERC1967Proxy proxy = new ERC1967Proxy{salt: salt}(
            address(registryImplementation),
            initializeData
        );
        registryProxyAddress = address(proxy); // Assign proxy address for return
        console.log("WhackRockFundRegistry Proxy (UUPS) deployed at:", registryProxyAddress);
        console.log("Proxy initialized. Temporary owner:", deployerAddress);

        // Get an instance of the registry at the proxy address to call functions
        WhackRockFundRegistry registryAtProxy = WhackRockFundRegistry(payable(registryProxyAddress));

        console.log("Adding initial allowed tokens to the registry...");
        registryAtProxy.addRegistryAllowedToken(USDC_BASE_FOR_FEE);
        console.log("Added USDC as allowed token:", USDC_BASE_FOR_FEE);
        registryAtProxy.addRegistryAllowedToken(CBETH_BASE);
        console.log("Added CBETH as allowed token:", CBETH_BASE);
        registryAtProxy.addRegistryAllowedToken(VIRTU_BASE);
        console.log("Added VIRTU as allowed token:", VIRTU_BASE);
        console.log("Initial allowed tokens added successfully.");

        // --- Create a Dummy WhackRockFund ---
        console.log("Creating a Dummy WhackRockFund...");
        string memory fundName = "Dummy WhackRock Fund";
        string memory fundSymbol = "DWRF";
        address[] memory initialAllowedTokens = new address[](2);
        initialAllowedTokens[0] = USDC_BASE_FOR_FEE;
        initialAllowedTokens[1] = CBETH_BASE;
        uint256[] memory initialTargetWeightsBps = new uint256[](2);
        initialTargetWeightsBps[0] = 5000; // 50%
        initialTargetWeightsBps[1] = 5000; // 50%
        
        address agentAumFeeWalletForFund = deployerAddress; 
        uint256 agentSetTotalAumFeeBps = 50; 
        address initialAgentForFund = deployerAddress; // Use deployer as the initial agent for the dummy fund

        // Call createWhackRockFund with arguments matching the actual contract signature
        newFundAddress = registryAtProxy.createWhackRockFund(
            initialAgentForFund,        // 1. address _initialAgent
            initialAllowedTokens,     // 2. address[] memory _fundAllowedTokens
            initialTargetWeightsBps,  // 3. uint256[] memory _initialTargetWeights
            fundName,                 // 4. string memory _vaultName
            fundSymbol,               // 5. string memory _vaultSymbol
            agentAumFeeWalletForFund, // 6. address _agentAumFeeWalletForFund
            agentSetTotalAumFeeBps    // 7. uint256 _agentSetTotalAumFeeBps
        );
        console.log("Dummy WhackRockFund created at:", newFundAddress);
        // --- End Dummy Fund Creation ---

        // Transfer ownership to the designated REGISTRY_OWNER
        if (REGISTRY_OWNER != address(0) && REGISTRY_OWNER != deployerAddress) {
            console.log("Transferring ownership of the registry to:", REGISTRY_OWNER);
            registryAtProxy.transferOwnership(REGISTRY_OWNER);
            console.log("Ownership transfer initiated. New owner will be:", REGISTRY_OWNER);
            // Note: OpenZeppelin's Ownable typically has a two-step transfer (proposeOwner, acceptOwnership) 
            // if using Ownable2Step. However, OwnableUpgradeable's transferOwnership is direct.
            // Confirming the WhackRockFundRegistry's inherited Ownable version.
            // Assuming standard OwnableUpgradeable's direct transferOwnership.
        } else if (REGISTRY_OWNER == deployerAddress) {
            console.log("Deployer is already the REGISTRY_OWNER. No ownership transfer needed.");
        } else {
            console.log("REGISTRY_OWNER is address(0). Ownership not transferred.");
        }

        vm.stopBroadcast();

        console.log("--- Deployment Summary ---");
        console.log("Deployer Address:", deployerAddress);
        console.log("Registry Implementation Address:", address(registryImplementation));
        console.log("Registry Proxy Address:", registryProxyAddress);
        console.log("Dummy Fund Address:", newFundAddress); // Added dummy fund address to summary
        console.log("Final Registry Owner (intended):", REGISTRY_OWNER);
        console.log("--- Review Parameters Used for Initialization ---");
        console.log("Initial Temporary Owner (Deployer):", deployerAddress);
        console.log("Aerodrome Router:", AERODROME_ROUTER_ADDRESS_BASE);
        console.log("Max Initial Tokens Length:", MAX_INITIAL_TOKENS_FOR_FUND_REGISTRY);
        console.log("USDC for Creation Fee:", USDC_BASE_FOR_FEE);
        console.log("WhackRock Rewards Address:", WHACKROCK_REWARDS_ADDR);
        console.log("Protocol Creation Fee (USDC):", PROTOCOL_CREATION_FEE_USDC);
        console.log("Total AUM Fee BPS for Funds:", TOTAL_AUM_FEE_BPS_FOR_FUNDS);
        console.log("Protocol AUM Fee Recipient:", PROTOCOL_AUM_FEE_RECIPIENT_FOR_FUNDS);
        console.log("Max Agent Deposit Fee BPS:", MAX_AGENT_DEPOSIT_FEE_BPS_REGISTRY);
        console.log("--- Initially Allowed Tokens Added ---");
        console.log("USDC:", USDC_BASE_FOR_FEE);
        console.log("CBETH:", CBETH_BASE);
        console.log("VIRTU:", VIRTU_BASE);
    }
} 