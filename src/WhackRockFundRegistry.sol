// SPDX-License-Identifier: BUSL-1.1
// © 2024 WhackRock Labs – All rights reserved.
// WHACKROCK – FUND REGISTRY AND FACTORY UPGRADABLE
pragma solidity ^0.8.20;

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


contract WhackRockFundRegistry is Initializable, UUPSUpgradeable, OwnableUpgradeable, IWhackRockFundRegistry {
    using SafeERC20 for IERC20; // Use standard SafeERC20 with standard IERC20

    IAerodromeRouter public aerodromeRouter; 
    address public WETH_ADDRESS;

    // Fee parameters
    IERC20 public USDC_TOKEN; // Changed to standard IERC20
    address public whackRockRewardsAddress; 
    uint256 public protocolFundCreationFeeUsdcAmount; 
    
    uint256 public totalAumFeeBpsForFunds; 
    address public protocolAumFeeRecipientForFunds; 
    uint256 public maxAgentDepositFeeBps; 

    // Fund tracking
    address[] public deployedFunds;
    mapping(address => address) public fundToCreator;
    uint256 public fundCounter;

    // Registry's own allowed token list management
    address[] public allowedTokensList;
    mapping(address => bool) public isTokenAllowedInRegistry;
    uint256 public maxInitialAllowedTokensLength;
    mapping(string => bool) public isSymbolTaken;

    // Events defined in IWhackRockFundRegistry interface
    // event WhackRockFundCreated(...);
    // event RegistryAllowedTokenAdded(address indexed token);
    // event RegistryAllowedTokenRemoved(address indexed token);
    // event MaxInitialAllowedTokensLengthUpdated(uint256 newLength);
    // event RegistryParamsUpdated(...);


    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

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
        // Assuming IAerodromeRouter's weth() returns an IWETH-like interface whose address is the WETH token
        // and that IWETH is compatible with standard IERC20 for address casting.
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

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function addRegistryAllowedToken(address _token) external override onlyOwner {
        require(_token != address(0), "Registry: Token zero");
        require(_token != WETH_ADDRESS, "Registry: WETH not allowed");
        require(!isTokenAllowedInRegistry[_token], "Registry: Token already allowed");
        allowedTokensList.push(_token);
        isTokenAllowedInRegistry[_token] = true;
        emit RegistryAllowedTokenAdded(_token);
    }

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
    
    function setMaxInitialAllowedTokensLength(uint256 _newMaxLength) external override onlyOwner {
        require(_newMaxLength > 0, "Registry: Max length must be > 0");
        maxInitialAllowedTokensLength = _newMaxLength;
        emit MaxInitialAllowedTokensLengthUpdated(_newMaxLength);
    }

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

        // Collect only the protocol creation fee from creator (msg.sender)
        if (protocolFundCreationFeeUsdcAmount > 0) {
            require(USDC_TOKEN.balanceOf(msg.sender) >= protocolFundCreationFeeUsdcAmount, "Registry: Insufficient USDC balance");
            USDC_TOKEN.safeTransferFrom(msg.sender, whackRockRewardsAddress, protocolFundCreationFeeUsdcAmount);
        }

        // Deploy the fund
        // The WhackRockFund constructor signature must match this call.
        // The imported WhackRockFund is from "./WhackRockFundV5_ERC4626_Aerodrome_SubGEvents.sol"
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
            new bytes(0) // Empty data parameter is still needed for constructor signature
        );
        fundAddress = address(newFund);

        // No USDC seed is transferred to the fund by the registry.
        // The fund will start with 0 NAV and be seeded by its first actual deposit.

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

    function getDeployedFundsCount() external view override returns (uint256) {
        return deployedFunds.length;
    }

    function getFundAddressByIndex(uint256 _index) external view override returns (address) {
        require(_index < deployedFunds.length, "Registry: Index out of bounds");
        return deployedFunds[_index];
    }

    function getRegistryAllowedTokens() external view override returns (address[] memory) {
        return allowedTokensList;
    }
}
