// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

/*
 *  
 *   oooooo   oooooo     oooo ooooo   ooooo       .o.         .oooooo.   oooo    oooo ooooooooo.     .oooooo.     .oooooo.   oooo    oooo 
 *   `888.    `888.     .8'  `888'   `888'      .888.       d8P'  `Y8b  `888   .8P'  `888   `Y88.  d8P'  `Y8b   d8P'  `Y8b  `888   .8P'  
 *    `888.   .8888.   .8'    888     888      .8"888.     888           888  d8'     888   .d88' 888      888 888           888  d8'    
 *     `888  .8'`888. .8'     888ooooo888     .8' `888.    888           88888[       888ooo88P'  888      888 888           88888[      
 *      `888.8'  `888.8'      888     888    .88ooo8888.   888           888`88b.     888`88b.    888      888 888           888`88b.    
 *       `888'    `888'       888     888   .8'     `888.  `88b    ooo   888  `88b.   888  `88b.  `88b    d88' `88b    ooo   888  `88b.  
 *        `8'      `8'       o888o   o888o o88o     o8888o  `Y8bood8P'  o888o  o888o o888o  o888o  `Y8bood8P'   `Y8bood8P'  o888o  o888o 
 *  
 *    WHACKROCK – FUND REGISTRY AND FACTORY UPGRADABLE   
 *    © 2024 WhackRock Labs – All rights reserved.
 */
 
// OpenZeppelin Upgradeable imports
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

// Standard OpenZeppelin imports
import {IERC20} from '@openzeppelin/contracts/interfaces/IERC20.sol';
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol"; // Added for USDC_TOKEN

import {IAerodromeRouter} from "./interfaces/IRouter.sol"; 
import {IWhackRockFundRegistry} from "./interfaces/IWhackRockFundRegistry.sol";
import {WhackRockFund} from "./WhackRockFundV5_ERC4626_Aerodrome_SubGEvents.sol"; 

/**
 * @title WhackRockFundRegistry
 * @author WhackRock Labs
 * @notice Registry for creating and managing WhackRock investment funds
 * @dev Implements UUPS proxy pattern for upgradability and handles fund creation, token allowlists, and fee configurations
 */
contract WhackRockFundRegistry is Initializable, UUPSUpgradeable, OwnableUpgradeable, IWhackRockFundRegistry {
    using SafeERC20 for IERC20; // Use standard SafeERC20 with standard IERC20

    /// @notice Aerodrome DEX router used for fund operations
    IAerodromeRouter public aerodromeRouter; 
    
    /// @notice Wrapped ETH address derived from the Aerodrome router
    address public WETH_ADDRESS;

    // Fee parameters
    /// @notice USDC token used for protocol fees
    IERC20 public USDC_TOKEN; // Changed to standard IERC20
    
    /// @notice Address that receives protocol fees from fund creation
    address public whackRockRewardsAddress; 
    
    /// @notice Fee amount in USDC charged for creating a new fund
    uint256 public protocolFundCreationFeeUsdcAmount; 
    
    /// @notice Maximum total AUM fee in basis points (10000 = 100%) that funds can charge
    uint256 public totalAumFeeBpsForFunds; 
    
    /// @notice Address that receives the protocol's portion of AUM fees from all funds
    address public protocolAumFeeRecipientForFunds; 
    
    /// @notice Maximum deposit fee in basis points that agents can charge
    uint256 public maxAgentDepositFeeBps; 

    // Fund tracking
    /// @notice Array of all deployed fund addresses
    address[] public deployedFunds;
    
    /// @notice Mapping from fund address to its creator address
    mapping(address => address) public fundToCreator;
    
    /// @notice Counter for the total number of funds created
    uint256 public fundCounter;

    // Registry's own allowed token list management
    /// @notice Array of token addresses allowed for fund creation
    address[] public allowedTokensList;
    
    /// @notice Mapping to check if a token is allowed in the registry
    mapping(address => bool) public isTokenAllowedInRegistry;
    
    /// @notice Maximum number of tokens a new fund can be initialized with
    uint256 public maxInitialAllowedTokensLength;
    
    /// @notice Mapping to track if a vault symbol is already in use
    mapping(string => bool) public isSymbolTaken;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the registry with its required parameters
     * @dev This replaces the constructor for upgradeable contracts
     * @param _initialOwner Address of the initial owner
     * @param _aerodromeRouterAddress Address of the Aerodrome router
     * @param _maxInitialFundTokensLength Maximum number of tokens a fund can have at creation
     * @param _usdcTokenAddress Address of the USDC token
     * @param _whackRockRewardsAddr Address that receives protocol fees
     * @param _protocolCreationFeeUsdc Fee amount in USDC for fund creation
     * @param _totalAumFeeBps Maximum total AUM fee in basis points
     * @param _protocolAumRecipient Address that receives protocol's portion of AUM fees
     * @param _maxAgentDepositFeeBpsAllowed Maximum deposit fee that agents can charge
     */
    function initialize(
        address _initialOwner,
        address _aerodromeRouterAddress,
        uint256 _maxInitialFundTokensLength,
        address _usdcTokenAddress,
        address _whackRockRewardsAddr,
        uint256 _protocolCreationFeeUsdc, 
        uint256 _totalAumFeeBps,          
        address _protocolAumRecipient,
        uint256 _maxAgentDepositFeeBpsAllowed 
    ) public initializer {
        __Ownable_init(_initialOwner); 
        __UUPSUpgradeable_init();    

        require(_aerodromeRouterAddress != address(0), "Registry: Aerodrome router zero");
        require(_maxInitialFundTokensLength > 0, "Registry: Max fund tokens must be > 0");
        require(_usdcTokenAddress != address(0), "Registry: USDC address zero");
        require(_whackRockRewardsAddr != address(0), "Registry: Rewards address zero");
        require(_protocolAumRecipient != address(0), "Registry: Protocol AUM recipient zero");

        aerodromeRouter = IAerodromeRouter(_aerodromeRouterAddress);
        WETH_ADDRESS = address(IAerodromeRouter(_aerodromeRouterAddress).weth());
        require(WETH_ADDRESS != address(0), "Registry: Could not derive WETH address");
        
        USDC_TOKEN = IERC20(_usdcTokenAddress); // Use standard IERC20
        whackRockRewardsAddress = _whackRockRewardsAddr;
        protocolFundCreationFeeUsdcAmount = _protocolCreationFeeUsdc;
        totalAumFeeBpsForFunds = _totalAumFeeBps; 
        protocolAumFeeRecipientForFunds = _protocolAumRecipient; 
        maxInitialAllowedTokensLength = _maxInitialFundTokensLength;
        maxAgentDepositFeeBps = _maxAgentDepositFeeBpsAllowed;

        emit RegistryParamsUpdated(
            _usdcTokenAddress,
            _whackRockRewardsAddr,
            _protocolCreationFeeUsdc,
            _totalAumFeeBps,
            _protocolAumRecipient,
            _maxAgentDepositFeeBpsAllowed
        );
    }

    /**
     * @notice Authorizes an upgrade to a new implementation contract
     * @dev Required by UUPSUpgradeable, only callable by owner
     * @param newImplementation Address of the new implementation contract
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /**
     * @notice Adds a token to the registry's global allowlist
     * @dev Only callable by owner, cannot add address(0) or WETH
     * @param _token Address of the token to add
     */
    function addRegistryAllowedToken(address _token) external override onlyOwner {
        require(_token != address(0), "Registry: Token zero");
        require(_token != WETH_ADDRESS, "Registry: WETH not allowed");
        require(!isTokenAllowedInRegistry[_token], "Registry: Token already allowed");
        allowedTokensList.push(_token);
        isTokenAllowedInRegistry[_token] = true;
        emit RegistryAllowedTokenAdded(_token);
    }

    /**
     * @notice Removes a token from the registry's global allowlist
     * @dev Only callable by owner, reorders array by moving last element to removed position
     * @param _token Address of the token to remove
     */
    function removeRegistryAllowedToken(address _token) external override onlyOwner {
        require(isTokenAllowedInRegistry[_token], "Registry: Token not in list");
        isTokenAllowedInRegistry[_token] = false;
        for (uint i = 0; i < allowedTokensList.length; i++) {
            if (allowedTokensList[i] == _token) {
                allowedTokensList[i] = allowedTokensList[allowedTokensList.length - 1];
                allowedTokensList.pop();
                break;
            }
        }
        emit RegistryAllowedTokenRemoved(_token);
    }
    
    /**
     * @notice Sets the maximum number of tokens a fund can have at creation
     * @dev Only callable by owner
     * @param _newMaxLength New maximum number of allowed tokens
     */
    function setMaxInitialAllowedTokensLength(uint256 _newMaxLength) external override onlyOwner {
        require(_newMaxLength > 0, "Registry: Max length must be > 0");
        maxInitialAllowedTokensLength = _newMaxLength;
        emit MaxInitialAllowedTokensLengthUpdated(_newMaxLength);
    }

    /**
     * @notice Updates the registry's parameters
     * @dev Only callable by owner
     * @param _usdcTokenAddress New USDC token address
     * @param _whackRockRewardsAddress New address for protocol fee collection
     * @param _protocolFundCreationFeeUsdc New fund creation fee in USDC
     * @param _totalAumFeeBps New maximum total AUM fee in basis points
     * @param _protocolAumRecipient New recipient for protocol's portion of AUM fees
     * @param _newMaxAgentDepositFeeBps New maximum deposit fee in basis points
     */
    function updateRegistryParameters(
        address _usdcTokenAddress,
        address _whackRockRewardsAddress,
        uint256 _protocolFundCreationFeeUsdc,
        uint256 _totalAumFeeBps, 
        address _protocolAumRecipient,
        uint256 _newMaxAgentDepositFeeBps 
    ) external onlyOwner {
        require(_usdcTokenAddress != address(0), "Registry: USDC address zero");
        require(_whackRockRewardsAddress != address(0), "Registry: Rewards address zero");
        require(_protocolAumRecipient != address(0), "Registry: Protocol AUM recipient zero");

        USDC_TOKEN = IERC20(_usdcTokenAddress); // Use standard IERC20
        whackRockRewardsAddress = _whackRockRewardsAddress;
        protocolFundCreationFeeUsdcAmount = _protocolFundCreationFeeUsdc;
        totalAumFeeBpsForFunds = _totalAumFeeBps;
        protocolAumFeeRecipientForFunds = _protocolAumRecipient;
        maxAgentDepositFeeBps = _newMaxAgentDepositFeeBps; 
        
        emit RegistryParamsUpdated(
            _usdcTokenAddress,
            _whackRockRewardsAddress,
            _protocolFundCreationFeeUsdc,
            _totalAumFeeBps,
            _protocolAumRecipient,
            _newMaxAgentDepositFeeBps
        );
    }

    /**
     * @notice Creates a new WhackRock investment fund
     * @dev Deploys a new fund contract, registers it, and collects creation fee if set
     * @param _initialAgent Address of the initial agent managing the fund
     * @param _fundAllowedTokens Array of allowed token addresses for the fund
     * @param _initialTargetWeights Array of target weights for each allowed token
     * @param _vaultName Name of the fund's ERC20 token
     * @param _vaultSymbol Symbol of the fund's ERC20 token
     * @param _agentAumFeeWalletForFund Address receiving the agent's portion of AUM fees
     * @param _agentSetTotalAumFeeBps Total AUM fee in basis points set by the agent
     * @return fundAddress Address of the newly created fund
     */
    function createWhackRockFund(
        address _initialAgent,
        address[] memory _fundAllowedTokens,
        uint256[] memory _initialTargetWeights,
        string memory _vaultName,
        string memory _vaultSymbol,
        address _agentAumFeeWalletForFund, 
        uint256 _agentSetTotalAumFeeBps 
    ) external override returns (address fundAddress) {
        require(_fundAllowedTokens.length > 0, "Registry: Fund must have at least one token");
        require(_fundAllowedTokens.length <= maxInitialAllowedTokensLength, "Registry: Exceeds max fund tokens");
        require(bytes(_vaultSymbol).length > 0, "Registry: Vault symbol cannot be empty");
        require(!isSymbolTaken[_vaultSymbol], "Registry: Vault symbol already taken");
        require(_agentAumFeeWalletForFund != address(0), "Registry: Agent AUM fee wallet zero");
        require(_agentSetTotalAumFeeBps <= totalAumFeeBpsForFunds, "Registry: Fund AUM fee exceeds protocol max/default");

        for (uint i = 0; i < _fundAllowedTokens.length; i++) {
            require(isTokenAllowedInRegistry[_fundAllowedTokens[i]], "Registry: Fund token not allowed");
        }

        if (protocolFundCreationFeeUsdcAmount > 0) {
            require(USDC_TOKEN.balanceOf(msg.sender) >= protocolFundCreationFeeUsdcAmount, "Registry: Insufficient USDC balance");
            USDC_TOKEN.safeTransferFrom(msg.sender, whackRockRewardsAddress, protocolFundCreationFeeUsdcAmount);
        }

        WhackRockFund newFund = new WhackRockFund(
            msg.sender, 
            _initialAgent,
            address(aerodromeRouter),
            _fundAllowedTokens,
            _initialTargetWeights,
            _vaultName,
            _vaultSymbol,
            _agentAumFeeWalletForFund,     
            _agentSetTotalAumFeeBps,       
            protocolAumFeeRecipientForFunds,
            address(USDC_TOKEN),
            new bytes(0)
        );
        fundAddress = address(newFund);


        deployedFunds.push(fundAddress);
        fundToCreator[fundAddress] = msg.sender;
        isSymbolTaken[_vaultSymbol] = true;
        fundCounter++;

        emit WhackRockFundCreated(
            fundCounter, fundAddress, msg.sender, _initialAgent, _vaultName, _vaultSymbol,
            _fundAllowedTokens, _initialTargetWeights, 
            _agentAumFeeWalletForFund, 
            _agentSetTotalAumFeeBps,    
            block.timestamp
        );
        return fundAddress;
    }

    /**
     * @notice Returns the total number of funds created
     * @return Number of deployed funds
     */
    function getDeployedFundsCount() external view override returns (uint256) {
        return deployedFunds.length;
    }

    /**
     * @notice Gets a fund address by its index in the deployedFunds array
     * @param _index Index in the deployedFunds array
     * @return Address of the fund at the specified index
     */
    function getFundAddressByIndex(uint256 _index) external view override returns (address) {
        require(_index < deployedFunds.length, "Registry: Index out of bounds");
        return deployedFunds[_index];
    }

    /**
     * @notice Returns the full list of allowed tokens
     * @return Array of allowed token addresses
     */
    function getRegistryAllowedTokens() external view override returns (address[] memory) {
        return allowedTokensList;
    }
}
