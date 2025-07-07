// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";

// Contracts to be deployed
import {WhackRockFundRegistry} from "../src/factory/WhackRockFundRegistry.sol";
import {WhackRockFundFactory} from "../src/factory/WhackRockFundFactory.sol";

// For deploying UUPS proxy
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployWhackRockFundRegistry is Script {
    // --- START: Configuration for Base Mainnet ---
    // These values should be reviewed and confirmed before mainnet deployment.
    address constant REGISTRY_OWNER = 0x90cfB07A46EE4bb20C970Dda18AaD1BA3c9450Ae;

    // External Contract Addresses (Base Mainnet) - Uniswap V3
    address constant UNISWAP_V3_ROUTER_BASE = 0x2626664c2603336E57B271c5C0b26F421741e481; // SwapRouter02
    address constant UNISWAP_V3_QUOTER_BASE = 0x3d4e44Eb1374240CE5F1B871ab261CD16335B76a; // QuoterV2
    address constant UNISWAP_V3_FACTORY_BASE = 0x33128a8fC17869897dcE68Ed026d694621f6FDfD; // UniswapV3Factory
    address constant USDC_BASE_FOR_FEE = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913; // USDC for creation fees & allowed token
    address constant WETH_BASE = 0x4200000000000000000000000000000000000006; // WETH for Base
    address constant CBBTC_BASE = 0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf; // cbBTC as an allowed token
    address constant RETH_BASE = 0xB6fe221Fe9EeF5aBa221c348bA20A1Bf5e73624c; // rETH as an allowed token
    address constant VIRTU_BASE = 0x0b3e328455c4059EEb9e3f84b5543F74E24e7E1b; // VIRTUAL as an allowed token
    address constant TOSHI_BASE = 0xAC1Bd2486aAf3B5C0fc3Fd868558b082a531B2B4; // TOSHI as an allowed token
    address constant BRETT_BASE = 0x532f27101965dd16442E59d40670FaF5eBB142E4; // BRETT as an allowed token
    address constant BasedPepe_BASE = 0x52b492a33E447Cdb854c7FC19F1e57E8BfA1777D;
    address constant AIXBT_BASE = 0x4F9Fd6Be4a90f2620860d680c0d4d5Fb53d1A825;

    address[] INITIAL_ALLOWED_TOKENS =
        [USDC_BASE_FOR_FEE, CBBTC_BASE, RETH_BASE, VIRTU_BASE, TOSHI_BASE, BRETT_BASE, BasedPepe_BASE, AIXBT_BASE];

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

        // Deploy the fund factory first
        console.log("Deploying WhackRockFundFactory...");
        WhackRockFundFactory fundFactory = new WhackRockFundFactory();
        console.log("WhackRockFundFactory deployed at:", address(fundFactory));

        console.log("Deploying WhackRockFundRegistry implementation...");
        WhackRockFundRegistry registryImplementation = new WhackRockFundRegistry();
        console.log("WhackRockFundRegistry implementation deployed at:", address(registryImplementation));

        // Prepare the initialization calldata
        // The `initialOwner` during initialize() will be the deployerAddress
        bytes memory initializeData = abi.encodeWithSelector(
            WhackRockFundRegistry.initialize.selector,
            deployerAddress, // initialOwner (deployer becomes temporary owner)
            UNISWAP_V3_ROUTER_BASE, // _uniswapV3RouterAddress
            UNISWAP_V3_QUOTER_BASE, // _uniswapV3QuoterAddress
            UNISWAP_V3_FACTORY_BASE, // _uniswapV3FactoryAddress
            WETH_BASE, // _wethAddress
            address(fundFactory), // _fundFactory
            MAX_INITIAL_TOKENS_FOR_FUND_REGISTRY, // _maxInitialFundTokensLength
            USDC_BASE_FOR_FEE, // _usdcTokenAddress
            WHACKROCK_REWARDS_ADDR, // _whackRockRewardsAddr
            PROTOCOL_CREATION_FEE_USDC, // _protocolCreationFeeUsdc
            TOTAL_AUM_FEE_BPS_FOR_FUNDS, // _totalAumFeeBps
            PROTOCOL_AUM_FEE_RECIPIENT_FOR_FUNDS, // _protocolAumRecipient
            MAX_AGENT_DEPOSIT_FEE_BPS_REGISTRY // _maxAgentDepositFeeBpsAllowed
        );

        console.log("Deploying ERC1967Proxy for WhackRockFundRegistry...");

        // Add a unique salt based on block timestamp to ensure fresh deployment
        bytes32 salt = keccak256(abi.encodePacked(block.timestamp, deployerAddress));

        ERC1967Proxy proxy = new ERC1967Proxy{salt: salt}(address(registryImplementation), initializeData);
        registryProxyAddress = address(proxy); // Assign proxy address for return
        console.log("WhackRockFundRegistry Proxy (UUPS) deployed at:", registryProxyAddress);
        console.log("Proxy initialized. Temporary owner:", deployerAddress);

        // Get an instance of the registry at the proxy address to call functions
        WhackRockFundRegistry registryAtProxy = WhackRockFundRegistry(payable(registryProxyAddress));

        console.log("Adding initial allowed tokens to the registry...");
        registryAtProxy.batchAddRegistryAllowedToken(INITIAL_ALLOWED_TOKENS);

        // --- Create a Dummy WhackRockFund ---

        console.log("Creating a Dummy WhackRockFund...");
        string memory fundName = "BenFan Fund by WhackRock";
        string memory fundSymbol = "BFWRF";
        string memory fundURI = "https://x.com/benjAImin_agent";
        string memory fundDescription =
            "A fan of Ben Cowen, this agent watches his latest videos and decides which assets to hold in the fund.  The ONLY assets allowed are cbBTC, Virtuals and USDC";
        address[] memory initialAllowedTokens = new address[](3);
        initialAllowedTokens[0] = USDC_BASE_FOR_FEE;
        initialAllowedTokens[1] = CBBTC_BASE;
        initialAllowedTokens[2] = VIRTU_BASE;
        uint256[] memory initialTargetWeightsBps = new uint256[](3);
        initialTargetWeightsBps[0] = 4000; // 50%
        initialTargetWeightsBps[1] = 5000; // 50%
        initialTargetWeightsBps[2] = 1000; // 0%

        // Empty pool addresses array - Uniswap V3 TWAP Oracle discovers pools dynamically
        address[] memory poolAddresses = new address[](0);

        address agentAumFeeWalletForFund = deployerAddress;
        uint256 agentSetTotalAumFeeBps = 200;
        address initialAgentForFund = deployerAddress; // Use deployer as the initial agent for the dummy fund

        // Call createWhackRockFund with arguments matching the actual contract signature
        newFundAddress = registryAtProxy.createWhackRockFund(
            initialAgentForFund, // 1. address _initialAgent
            initialAllowedTokens, // 2. address[] memory _fundAllowedTokens
            initialTargetWeightsBps, // 3. uint256[] memory _initialTargetWeights
            poolAddresses, // 4. address[] memory _poolAddresses (NEW for V6)
            fundName, // 5. string memory _vaultName
            fundSymbol, // 6. string memory _vaultSymbol
            fundURI, // 7. string memory _vaultURI
            fundDescription,
            agentAumFeeWalletForFund, // 8. address _agentAumFeeWalletForFund
            agentSetTotalAumFeeBps // 9. uint256 _agentSetTotalAumFeeBps
        );
        console.log("Dummy WhackRockFund created at:", newFundAddress);
        // --- End Dummy Fund Creation ---

        // Transfer ownership to the designated REGISTRY_OWNER
        if (REGISTRY_OWNER != address(0) && REGISTRY_OWNER != deployerAddress) {
            console.log("Transferring ownership of the registry to:", REGISTRY_OWNER);
            registryAtProxy.transferOwnership(REGISTRY_OWNER);
            console.log("Ownership transfer initiated. New owner will be:", REGISTRY_OWNER);
        } else if (REGISTRY_OWNER == deployerAddress) {
            console.log("Deployer is already the REGISTRY_OWNER. No ownership transfer needed.");
        } else {
            console.log("REGISTRY_OWNER is address(0). Ownership not transferred.");
        }

        vm.stopBroadcast();

        console.log("--- Deployment Summary ---");
        console.log("Deployer Address:", deployerAddress);
        console.log("Fund Factory Address:", address(fundFactory));
        console.log("Registry Implementation Address:", address(registryImplementation));
        console.log("Registry Proxy Address:", registryProxyAddress);
        console.log("Dummy Fund Address:", newFundAddress); // Added dummy fund address to summary
        console.log("Final Registry Owner (intended):", REGISTRY_OWNER);
        console.log("--- Review Parameters Used for Initialization ---");
        console.log("Initial Temporary Owner (Deployer):", deployerAddress);
        console.log("Uniswap V3 Router:", UNISWAP_V3_ROUTER_BASE);
        console.log("Uniswap V3 Quoter:", UNISWAP_V3_QUOTER_BASE);
        console.log("Uniswap V3 Factory:", UNISWAP_V3_FACTORY_BASE);
        console.log("WETH Address:", WETH_BASE);
        console.log("Fund Factory Address:", address(fundFactory));
        console.log("Max Initial Tokens Length:", MAX_INITIAL_TOKENS_FOR_FUND_REGISTRY);
        console.log("USDC for Creation Fee:", USDC_BASE_FOR_FEE);
        console.log("WhackRock Rewards Address:", WHACKROCK_REWARDS_ADDR);
        console.log("Protocol Creation Fee (USDC):", PROTOCOL_CREATION_FEE_USDC);
        console.log("Total AUM Fee BPS for Funds:", TOTAL_AUM_FEE_BPS_FOR_FUNDS);
        console.log("Protocol AUM Fee Recipient:", PROTOCOL_AUM_FEE_RECIPIENT_FOR_FUNDS);
        console.log("Max Agent Deposit Fee BPS:", MAX_AGENT_DEPOSIT_FEE_BPS_REGISTRY);
        console.log("--- Initially Allowed Tokens Added ---");
        console.log("USDC:", USDC_BASE_FOR_FEE);
        console.log("cbBTC:", CBBTC_BASE);
        console.log("rETH:", RETH_BASE);
        console.log("VIRTUAL:", VIRTU_BASE);
        console.log("TOSHI:", TOSHI_BASE);
        console.log("BRETT:", BRETT_BASE);
        console.log("--- Note: Pool addresses are discovered dynamically by the Uniswap V3 TWAP Oracle ---");
    }
}
