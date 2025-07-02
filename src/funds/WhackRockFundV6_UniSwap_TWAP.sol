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
 *    AGENT‑MANAGED WEIGHTED FUND   
 *    © 2024 WhackRock Labs – All rights reserved.
 */

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import {IUniswapV3Router, IUniswapV3Quoter} from "./interfaces/IUniswapV3Router.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {IUniswapV3SwapCallback} from "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3SwapCallback.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IAerodromeRouter} from "./interfaces/IRouter.sol";
import {IWhackRockFund} from "./interfaces/IWhackRockFund.sol";
import {UniswapV3TWAPOracle} from "./UniswapV3TWAPOracle.sol"; 

/**
 * @title WhackRockFund
 * @author WhackRock Labs
 * @notice An agent-managed investment fund with custom ERC20 shares, WETH deposits, and basket withdrawals
 * @dev Implements an automated portfolio management system with:
 *      - ERC20 tokenized shares
 *      - Dynamic asset allocation through target weights
 *      - Automatic rebalancing after deposits and withdrawals
 *      - Agent and protocol fee collection through share minting
 *      - DEX integration for asset swaps
 */
contract WhackRockFund is IWhackRockFund, ERC20, Ownable, UniswapV3TWAPOracle, IUniswapV3SwapCallback {
    using SafeERC20 for IERC20;

    // Error codes to reduce bytecode size
    error E1(); // Zero address
    error E2(); // Invalid amount/length
    error E3(); // Insufficient balance
    error E4(); // Unauthorized
    error E5(); // Invalid state
    error E6(); // Swap failed

    /**
     * @dev Structure used during rebalancing to track token information
     * @param token Token address
     * @param currentBalance Current token balance held by the fund
     * @param currentValueInAccountingAsset Current value of balance in WETH
     * @param targetValueInAccountingAsset Target value based on weights in WETH
     * @param deltaValueInAccountingAsset Difference between target and current value
     */
    struct TokenRebalanceInfo {
        address token;
        uint256 currentBalance;
        uint256 currentValueInAccountingAsset;
        uint256 targetValueInAccountingAsset;
        int256 deltaValueInAccountingAsset;
    }

    /// @notice Address of the agent managing the fund's investments
    address public agent;
    
    /// @notice Uniswap V3 router used for swapping tokens during rebalancing
    IUniswapV3Router public immutable uniswapV3Router;
    
    /// @notice Uniswap V3 quoter for getting swap quotes
    IUniswapV3Quoter public immutable uniswapV3Quoter;
    
    /// @notice Address of WETH, used as the accounting asset for NAV calculations (hardcoded)
    address public immutable WETH_ADDRESS;
    
    /// @notice Address of USDC token used for USD-denominated calculations
    address public immutable USDC_ADDRESS; // USDC token address

    /// @notice Base URL for fund URIs
    string public baseURI;

    /// @notice Array of token addresses allowed in the fund
    address[] public allowedTokens;
    
    /// @notice Mapping of token address to its target weight in basis points
    mapping(address => uint256) public targetWeights;
    
    /// @notice Mapping to check if a token is allowed in the fund
    mapping(address => bool) public isAllowedTokenInternal;

    // Agent and Protocol AUM Fee parameters
    /// @notice Address receiving the agent's portion of AUM fees
    address public immutable agentAumFeeWallet;
    
    /// @notice Annual AUM fee rate in basis points
    uint256 public immutable agentAumFeeBps;
    
    /// @notice Address receiving the protocol's portion of AUM fees
    address public immutable protocolAumFeeRecipient;
    
    /// @notice Timestamp of the last AUM fee collection
    uint256 public lastAgentAumFeeCollectionTimestamp;

    /// @notice Total basis points representing 100% (10000)
    uint256 public constant TOTAL_WEIGHT_BASIS_POINTS = 10000;

    /// @notice Maximum fee rate allowed (10%)
    uint256 public constant MAX_FEE_BASIS_POINTS = 1000;
    
    /// @notice Percentage of AUM fee allocated to the agent (60%)
    uint256 public constant AGENT_AUM_FEE_SHARE_BPS = 6000;
    
    /// @notice Percentage of AUM fee allocated to the protocol (40%)
    uint256 public constant PROTOCOL_AUM_FEE_SHARE_BPS = 4000;

    /// @notice Default slippage tolerance for swaps (0.5%)
    uint256 public constant DEFAULT_SLIPPAGE_BPS = 50;
    
    /// @notice Time buffer added to swap deadlines
    uint256 public constant SWAP_DEADLINE_OFFSET = 15 minutes;
    
    /// @notice Default fee tier for Uniswap V3 pools (0.3%)
    uint24 public constant DEFAULT_POOL_FEE = 3000;
    
    /// @notice Default pool stability setting (false for Uniswap V3)
    bool public constant DEFAULT_POOL_STABILITY = false;
    
    /// @notice Minimum liquidity required for first deposit in WETH units
    uint256 private constant MINIMUM_SHARES_LIQUIDITY = 1000;
    
    /// @notice Minimum initial deposit amount required to create a new fund (0.1 WETH)
    /// @dev Protects against dust attacks on first deposit that could manipulate share price
    uint256 public constant MINIMUM_INITIAL_DEPOSIT = 0.01 ether;
    
    /// @notice Minimum deposit amount required for all deposits (0.01 WETH)
    /// @dev Prevents dust deposits that could be used for inflation attacks
    uint256 public constant MINIMUM_DEPOSIT = 0.01 ether;
    
    /// @notice Threshold for triggering rebalancing (1% deviation)
    uint256 public constant REBALANCE_DEVIATION_THRESHOLD_BPS = 100;

    /**
     * @notice Restricts function access to the current agent
     */
    modifier onlyAgent() {
        if (msg.sender != agent) revert E4();
        _;
    }

    /**
     * @notice Creates a new WhackRockFund
     * @param _initialOwner Address of the fund owner
     * @param _initialAgent Address of the initial agent managing the fund
     * @param _uniswapV3RouterAddress Address of the Uniswap V3 router
     * @param _uniswapV3QuoterAddress Address of the Uniswap V3 quoter
     * @param _uniswapV3FactoryAddress Address of the Uniswap V3 factory
     * @param _wethAddress Address of WETH token (accounting asset)
     * @param _initialAllowedTokens Array of initially allowed token addresses
     * @param _initialTargetWeights Array of target weights for each allowed token
     * @param _vaultName Name of the fund's ERC20 token
     * @param _vaultSymbol Symbol of the fund's ERC20 token
     * @param _agentAumFeeWallet Address receiving the agent's portion of AUM fees
     * @param _totalAgentAumFeeBpsRate Total AUM fee rate in basis points
     * @param _protocolAumFeeRecipientAddress Address receiving the protocol's portion of AUM fees
     * @param _usdcAddress Address of USDC token
     */
    constructor(
        address _initialOwner,
        address _initialAgent,
        address _uniswapV3RouterAddress,
        address _uniswapV3QuoterAddress,
        address _uniswapV3FactoryAddress,
        address _wethAddress,
        address[] memory _initialAllowedTokens,
        uint256[] memory _initialTargetWeights,
        string memory _vaultName,
        string memory _vaultSymbol,
        string memory _vaultURI,
        address _agentAumFeeWallet,
        uint256 _totalAgentAumFeeBpsRate,
        address _protocolAumFeeRecipientAddress,
        address _usdcAddress,
        bytes memory /* data */ // Unused again
    ) ERC20(_vaultName, _vaultSymbol) Ownable(_initialOwner) UniswapV3TWAPOracle(_uniswapV3FactoryAddress, 900, _wethAddress) {
        if (_initialAgent == address(0)) revert E1();
        if (_uniswapV3RouterAddress == address(0)) revert E1();
        if (_uniswapV3QuoterAddress == address(0)) revert E1();
        if (_uniswapV3FactoryAddress == address(0)) revert E1();
        if (_wethAddress == address(0)) revert E1();
        if (_agentAumFeeWallet == address(0)) revert E1();
        if (_protocolAumFeeRecipientAddress == address(0)) revert E1();
        if (_usdcAddress == address(0)) revert E1();

        // Hardcode WETH as the accounting asset
        WETH_ADDRESS = _wethAddress;
        
        // Use directly provided USDC address
        USDC_ADDRESS = _usdcAddress;

        if (_initialAllowedTokens.length == 0) revert E2();
        if (_initialAllowedTokens.length != _initialTargetWeights.length) revert E2();

        agent = _initialAgent;
        uniswapV3Router = IUniswapV3Router(_uniswapV3RouterAddress);
        uniswapV3Quoter = IUniswapV3Quoter(_uniswapV3QuoterAddress);
        allowedTokens = _initialAllowedTokens;
        agentAumFeeWallet = _agentAumFeeWallet;
        require(_totalAgentAumFeeBpsRate <= MAX_FEE_BASIS_POINTS, "Invalid AUM fee rate"); // Ensure fee rate is valid
        agentAumFeeBps = _totalAgentAumFeeBpsRate;
        protocolAumFeeRecipient = _protocolAumFeeRecipientAddress;
        lastAgentAumFeeCollectionTimestamp = block.timestamp;
        baseURI = _vaultURI;

        uint256 currentTotalWeight = 0;
        for (uint256 i = 0; i < _initialAllowedTokens.length; i++) {
            address currentToken = _initialAllowedTokens[i];
            if (currentToken == address(0)) revert E1();
            if (currentToken == WETH_ADDRESS) revert E5();
            if (_initialTargetWeights[i] == 0) revert E2();

            currentTotalWeight += _initialTargetWeights[i];
            targetWeights[currentToken] = _initialTargetWeights[i];
            isAllowedTokenInternal[currentToken] = true;
            _approveTokenIfNeeded(IERC20(currentToken), address(uniswapV3Router), type(uint256).max);
        }
        if (currentTotalWeight != TOTAL_WEIGHT_BASIS_POINTS) revert E2();
        _approveTokenIfNeeded(IERC20(WETH_ADDRESS), address(uniswapV3Router), type(uint256).max);
        
        // Approve USDC for router if needed
        _approveTokenIfNeeded(IERC20(USDC_ADDRESS), address(uniswapV3Router), type(uint256).max);

        emit AgentUpdated(address(0), _initialAgent);
        emit TargetWeightsUpdated(msg.sender, _initialAllowedTokens, _initialTargetWeights, block.timestamp); // Added agent and timestamp
    }

    /**
     * @notice Calculates the total net asset value of the fund in accounting asset (WETH) units
     * @dev Sums up the WETH value of all tokens in the fund, including WETH itself
     * @return totalManagedAssets Total NAV in WETH
     */
    function totalNAVInAccountingAsset() public view returns (uint256 totalManagedAssets) {
        totalManagedAssets = 0;
        for (uint256 i = 0; i < allowedTokens.length; i++) {
            address currentToken = allowedTokens[i];
            uint256 balance = IERC20(currentToken).balanceOf(address(this));
            if (balance > 0) {
                totalManagedAssets += _getTokenValueInAccountingAsset(currentToken, balance);
            }
        }
        totalManagedAssets += IERC20(WETH_ADDRESS).balanceOf(address(this));
        return totalManagedAssets;
    }
    
    /**
     * @notice Calculates the total net asset value of the fund in USDC units
     * @dev Converts the WETH NAV to USDC value using DEX quote
     * @return totalManagedAssetsInUSDC Total NAV in USDC
     */
    function totalNAVInUSDC() public view returns (uint256 totalManagedAssetsInUSDC) {
        uint256 navInWETH = totalNAVInAccountingAsset();
        if (navInWETH == 0) return 0;
        
        // Convert WETH value to USDC value using DEX router
        uint256 usdcValue = _getWETHValueInUSDC(navInWETH);
        
        // If we couldn't get USDC value (e.g. no liquidity), return 0
        if (usdcValue == 0) {
            return 0;
        }
        
        return usdcValue;
    }
    

    /**
     * @notice Deposits WETH into the fund and mints shares
     * @dev Handles first deposit specially, sets initial share price 1:1 with WETH
     *      May trigger rebalancing if asset weights deviate from targets
     * @param amountWETHToDeposit Amount of WETH to deposit
     * @param receiver Address to receive the minted shares
     * @return sharesMinted Number of shares minted
     */
    function deposit(uint256 amountWETHToDeposit, address receiver) external returns (uint256 sharesMinted) {
        // Enforce minimum deposit amount for all deposits
        if (amountWETHToDeposit < MINIMUM_DEPOSIT) revert E2();
        if (receiver == address(0)) revert E1();

        uint256 navBeforeDeposit = totalNAVInAccountingAsset(); 
        uint256 totalSupplyBeforeDeposit = totalSupply();

        if (totalSupplyBeforeDeposit == 0) { // Handles first deposit
            // Require a higher minimum deposit for first deposit to prevent share price manipulation
            if (amountWETHToDeposit < MINIMUM_INITIAL_DEPOSIT) revert E2();
            
            // Initial share price 1:1 with WETH
            sharesMinted = amountWETHToDeposit;
            
            // With minimum initial deposit requirement, we can consider removing this
            // but keeping it as an additional safeguard
            if (sharesMinted < MINIMUM_SHARES_LIQUIDITY && amountWETHToDeposit > 0) {
                sharesMinted = MINIMUM_SHARES_LIQUIDITY;
            }
        } else {
            if (navBeforeDeposit == 0) revert E5();
            sharesMinted = (amountWETHToDeposit * totalSupplyBeforeDeposit) / navBeforeDeposit;
        }
        if (sharesMinted == 0) revert E5();

        IERC20(WETH_ADDRESS).safeTransferFrom(msg.sender, address(this), amountWETHToDeposit);
        _mint(receiver, sharesMinted);

        uint256 wethValueInUSDC = _getWETHValueInUSDC(1 ether);

        emit WETHDepositedAndSharesMinted(msg.sender, receiver, amountWETHToDeposit, sharesMinted, navBeforeDeposit, totalSupplyBeforeDeposit, wethValueInUSDC);

        (bool needsRebalance, uint256 maxDeviationBPS) = _isRebalanceNeeded();
        emit RebalanceCheck(needsRebalance, maxDeviationBPS, totalNAVInAccountingAsset()); // Pass current NAV
        if (needsRebalance || (totalSupplyBeforeDeposit == 0 && totalSupply() > 0) ) { 
            _rebalance();
        }
        return sharesMinted;
    }
    
    /**
     * @notice Withdraws assets from the fund by burning shares
     * @dev Burns shares and transfers a proportional amount of all fund assets to the receiver
     *      May trigger rebalancing if asset weights deviate from targets after withdrawal
     * @param sharesToBurn Number of shares to burn
     * @param receiver Address to receive the withdrawn assets
     * @param owner Address that owns the shares
     */
    function withdraw(uint256 sharesToBurn, address receiver, address owner) external {
        if (sharesToBurn == 0) revert E2();
        if (receiver == address(0)) revert E1();
        if (owner == address(0)) revert E1();

        if (owner != msg.sender && allowance(owner, msg.sender) < sharesToBurn) {
            revert ERC20InsufficientAllowance(msg.sender, allowance(owner, msg.sender), sharesToBurn);
        }
        if (owner != msg.sender) {
            _spendAllowance(owner, msg.sender, sharesToBurn);
        }

        uint256 totalSupplyBeforeWithdrawal = totalSupply(); // Before burning
        if (totalSupplyBeforeWithdrawal < sharesToBurn) revert E3();
        if (balanceOf(owner) < sharesToBurn) revert E3();

        uint256 navBeforeWithdrawal = totalNAVInAccountingAsset(); // NAV before assets are removed

        uint256 numAssetsToWithdraw = allowedTokens.length + 1;
        address[] memory tokensWithdrawn = new address[](numAssetsToWithdraw);
        uint256[] memory amountsWithdrawn = new uint256[](numAssetsToWithdraw);
        uint256 eventIdx = 0;
        uint256 totalWETHValueOfWithdrawal = 0;

        _burn(owner, sharesToBurn);

        uint256 wethBalance = IERC20(WETH_ADDRESS).balanceOf(address(this));
        if (wethBalance > 0 && totalSupplyBeforeWithdrawal > 0) {
            uint256 wethToWithdraw = (wethBalance * sharesToBurn) / totalSupplyBeforeWithdrawal;
            if (wethToWithdraw > 0) {
                IERC20(WETH_ADDRESS).safeTransfer(receiver, wethToWithdraw);
                tokensWithdrawn[eventIdx] = WETH_ADDRESS;
                amountsWithdrawn[eventIdx] = wethToWithdraw;
                totalWETHValueOfWithdrawal += wethToWithdraw; // Already in WETH
                eventIdx++;
            }
        }

        for (uint256 i = 0; i < allowedTokens.length; i++) {
            address currentToken = allowedTokens[i];
            uint256 tokenBalance = IERC20(currentToken).balanceOf(address(this));
            if (tokenBalance > 0 && totalSupplyBeforeWithdrawal > 0) {
                uint256 tokenAmountToWithdraw = (tokenBalance * sharesToBurn) / totalSupplyBeforeWithdrawal;
                if (tokenAmountToWithdraw > 0) {
                    IERC20(currentToken).safeTransfer(receiver, tokenAmountToWithdraw);
                    tokensWithdrawn[eventIdx] = currentToken;
                    amountsWithdrawn[eventIdx] = tokenAmountToWithdraw;
                    totalWETHValueOfWithdrawal += _getTokenValueInAccountingAsset(currentToken, tokenAmountToWithdraw);
                    eventIdx++;
                }
            }
        }

        

        address[] memory finalTokensWithdrawn = new address[](eventIdx);
        uint256[] memory finalAmountsWithdrawn = new uint256[](eventIdx);
        for (uint256 k = 0; k < eventIdx; k++) {
            finalTokensWithdrawn[k] = tokensWithdrawn[k];
            finalAmountsWithdrawn[k] = amountsWithdrawn[k];
        }
        
        uint256 wethValueInUSDC = _getWETHValueInUSDC(1 ether);
        emit BasketAssetsWithdrawn(
            owner, receiver, sharesToBurn, finalTokensWithdrawn, finalAmountsWithdrawn,
            navBeforeWithdrawal, totalSupplyBeforeWithdrawal, totalWETHValueOfWithdrawal, wethValueInUSDC
        );

        (bool needsRebalance, uint256 maxDeviationBPS) = _isRebalanceNeeded();
        emit RebalanceCheck(needsRebalance, maxDeviationBPS, totalNAVInAccountingAsset()); // Pass current NAV
        if (needsRebalance && totalSupply() > 0) {
            _rebalance();
        }
    }

    /**
     * @notice Collects the AUM fee by minting new shares
     * @dev Calculates fee based on time elapsed since last collection
     *      Mints new shares and distributes them between agent and protocol
     *      according to AGENT_AUM_FEE_SHARE_BPS and PROTOCOL_AUM_FEE_SHARE_BPS
     */
    function collectAgentManagementFee() external onlyOwner {

        if (agentAumFeeBps == 0) revert E5();
        if (block.timestamp <= lastAgentAumFeeCollectionTimestamp) revert E5();

        uint256 navAtFeeCalc = totalNAVInAccountingAsset(); // NAV at the point of fee calculation
        uint256 sharesAtFeeCalc = totalSupply(); // Total shares at the point of fee calculation

        if (navAtFeeCalc == 0 || sharesAtFeeCalc == 0) {
            lastAgentAumFeeCollectionTimestamp = block.timestamp;
            return;
        }

        uint256 timeElapsed = block.timestamp - lastAgentAumFeeCollectionTimestamp;
        uint256 totalFeeValueInAA = (navAtFeeCalc * agentAumFeeBps * timeElapsed) / (TOTAL_WEIGHT_BASIS_POINTS * 365 days);
        
        if (totalFeeValueInAA > 0) {
            uint256 totalSharesToMintForFee = (totalFeeValueInAA * sharesAtFeeCalc) / navAtFeeCalc;
            
            if (totalSharesToMintForFee > 0) {
                uint256 agentShares = (totalSharesToMintForFee * AGENT_AUM_FEE_SHARE_BPS) / TOTAL_WEIGHT_BASIS_POINTS;
                uint256 protocolShares = totalSharesToMintForFee - agentShares;

                if (agentShares > 0) {
                    _mint(agentAumFeeWallet, agentShares);
                }
                if (protocolShares > 0) {
                    _mint(protocolAumFeeRecipient, protocolShares);
                }

                
                emit AgentAumFeeCollected(
                    agentAumFeeWallet, agentShares,
                    protocolAumFeeRecipient, protocolShares,
                    totalFeeValueInAA, 
                    navAtFeeCalc,
                    sharesAtFeeCalc,
                    block.timestamp
                );
            }
        }
        lastAgentAumFeeCollectionTimestamp = block.timestamp;
    }

    /**
     * @notice Updates the fund's agent address
     * @dev Only callable by fund owner
     * @param _newAgent Address of the new agent
     */
    function setAgent(address _newAgent) external onlyOwner {
        if (_newAgent == address(0)) revert E1();
        address oldAgent = agent;
        agent = _newAgent;
        emit AgentUpdated(oldAgent, _newAgent);
    }

    /**
     * @notice Sets new target weights for the fund's assets
     * @dev Only callable by the current agent
     *      Weights must sum to TOTAL_WEIGHT_BASIS_POINTS (10000)
     * @param _weights Array of new target weights in basis points
     */
    function setTargetWeights(uint256[] calldata _weights) external onlyAgent {
        _setTargetWeights(_weights);
    }

    /**
     * @notice Sets new target weights for the fund's assets and rebalances if needed
     * @dev Only callable by the current agent
     *      Weights must sum to TOTAL_WEIGHT_BASIS_POINTS (10000)
     * @param _weights Array of new target weights in basis points
     */
    function setTargetWeightsAndRebalanceIfNeeded(uint256[] calldata _weights) external onlyAgent {
        _setTargetWeights(_weights);
        (bool needsRebalance, uint256 maxDeviationBPS) = _isRebalanceNeeded();
        emit RebalanceCheck(needsRebalance, maxDeviationBPS, totalNAVInAccountingAsset()); // Pass current NAV
        if (needsRebalance && totalSupply() > 0) {
            _rebalance();
        }
    }

    /**
     * @notice Sets new target weights for the fund's assets
     * @dev Only callable by the current agent
     *      Weights must sum to TOTAL_WEIGHT_BASIS_POINTS (10000)
     * @param _weights Array of new target weights in basis points
     */
    function _setTargetWeights(uint256[] calldata _weights) internal {
        if (_weights.length != allowedTokens.length) revert E2();
        uint256 currentTotalWeight = 0;
        for (uint256 i = 0; i < _weights.length; i++) {
            if (_weights[i] == 0) revert E2();
            currentTotalWeight += _weights[i];
        }
        if (currentTotalWeight != TOTAL_WEIGHT_BASIS_POINTS) revert E2();

        address[] memory tokensForEvent = new address[](allowedTokens.length);
        for (uint256 i = 0; i < allowedTokens.length; i++) {
            targetWeights[allowedTokens[i]] = _weights[i];
            tokensForEvent[i] = allowedTokens[i];
        }
        emit TargetWeightsUpdated(msg.sender, tokensForEvent, _weights, block.timestamp); // Added agent and timestamp
    }

    /**
     * @notice Manually triggers a rebalance of the fund's assets
     * @dev Only callable by the agent
     *      RebalanceCycleExecuted event is emitted by _rebalance() function
     */
    function triggerRebalance() external onlyAgent {
        _rebalance();
    }

    
    /**
     * @notice Gets the current composition of the fund's assets.
     * @dev Returns arrays for current weights (BPS) and token addresses.
     * The order in all arrays corresponds to the order of tokens in the `allowedTokens` array.
     * @return currentComposition_ An array of current weights in basis points.
     * @return tokenAddresses_ An array of the addresses of the allowed tokens.
     */
    function getCurrentCompositionBPS()
        external
        override
        view
        returns (
            uint256[] memory currentComposition_,
            address[] memory tokenAddresses_
        )
    {
        uint256 numAllowedTokens = allowedTokens.length;
        currentComposition_ = new uint256[](numAllowedTokens);
        tokenAddresses_ = new address[](numAllowedTokens);

        uint256 currentNAV = totalNAVInAccountingAsset();

        if (currentNAV == 0) {
            // If NAV is 0, all current weights are 0.
            // Populate addresses even if NAV is 0.
            for (uint256 i = 0; i < numAllowedTokens; i++) {
                address currentTokenAddress = allowedTokens[i];
                tokenAddresses_[i] = currentTokenAddress;
                // currentComposition_ is already initialized to zeros
            }
            return (currentComposition_, tokenAddresses_);
        }

        for (uint256 i = 0; i < numAllowedTokens; i++) {
            address currentTokenAddress = allowedTokens[i];
            tokenAddresses_[i] = currentTokenAddress;

            uint256 tokenBalance = IERC20(currentTokenAddress).balanceOf(address(this));

            if (tokenBalance == 0) {
                currentComposition_[i] = 0;
                continue;
            }

            uint256 tokenValueInAA = _getTokenValueInAccountingAsset(currentTokenAddress, tokenBalance);
            currentComposition_[i] = (tokenValueInAA * TOTAL_WEIGHT_BASIS_POINTS) / currentNAV;
        }
        return (currentComposition_, tokenAddresses_);
    }

    /**
     * @notice Gets the target composition of the fund's assets.
     * @dev Returns arrays for target weights (BPS) and token addresses.
     * The order in all arrays corresponds to the order of tokens in the `allowedTokens` array.
     * @return targetComposition_ An array of target weights in basis points.
     * @return tokenAddresses_ An array of the addresses of the allowed tokens.
     */
    function getTargetCompositionBPS()
        external
        override
        view
        returns (
            uint256[] memory targetComposition_,
            address[] memory tokenAddresses_
        )
    {
        uint256 numAllowedTokens = allowedTokens.length;
        targetComposition_ = new uint256[](numAllowedTokens);
        tokenAddresses_ = new address[](numAllowedTokens);

        for (uint256 i = 0; i < numAllowedTokens; i++) {
            address currentTokenAddress = allowedTokens[i];
            tokenAddresses_[i] = currentTokenAddress;
            targetComposition_[i] = targetWeights[currentTokenAddress];
        }
        return (targetComposition_, tokenAddresses_);
    }

    /**
     * @notice Safely gets NAV with error handling
     * @return nav The NAV value or 0 if failed
     */
    function _safeGetNAV() internal view returns (uint256 nav) {
        try this.totalNAVInAccountingAsset() returns (uint256 value) {
            return value;
        } catch {
            return 0;
        }
    }

    /**
     * @notice Safely gets token balance with error handling
     * @param token Token address
     * @return balance The token balance or 0 if failed
     */
    function _safeGetTokenBalance(address token) internal view returns (uint256 balance) {
        try IERC20(token).balanceOf(address(this)) returns (uint256 value) {
            return value;
        } catch {
            return 0;
        }
    }

    /**
     * @notice Safely gets token value in accounting asset with error handling
     * @param token Token address
     * @param amount Token amount
     * @return value The value in accounting asset or 0 if failed
     */
    function _safeGetTokenValue(address token, uint256 amount) internal view returns (uint256 value) {
        if (amount == 0) return 0;
        if (token == WETH_ADDRESS) return 0;

        try this.getTokenValueInWETH(token, amount, DEFAULT_POOL_FEE) returns (uint256 val) {
            return val;
        } catch {
            try this.getTokenValueInWETH(token, amount, 500) returns (uint256 val) {
                return val;
            } catch {
                try this.getTokenValueInWETH(token, amount, 10000) returns (uint256 val) {
                    return val;
                } catch {
                    return 0;
                }
            }
        }
    }

    /**
     * @notice Safely gets WETH value in USDC with error handling
     * @param wethAmount WETH amount
     * @return value The USDC value or 0 if failed
     */
    function _safeGetWETHValueInUSDC(uint256 wethAmount) internal view returns (uint256 value) {
        if (wethAmount == 0) return 0;
        
        try this.getWETHValueInToken(USDC_ADDRESS, wethAmount, DEFAULT_POOL_FEE) returns (uint256 val) {
            return val;
        } catch {
            try this.getWETHValueInToken(USDC_ADDRESS, wethAmount, 500) returns (uint256 val) {
                return val;
            } catch {
                try this.getWETHValueInToken(USDC_ADDRESS, wethAmount, 10000) returns (uint256 val) {
                    return val;
                } catch {
                    return 0;
                }
            }
        }
    }

    /**
     * @notice Safely performs token swap with error handling
     * @param tokenIn Input token address
     * @param tokenOut Output token address
     * @param amountIn Amount to swap
     * @param slippageBps Slippage tolerance
     * @return success True if swap succeeded
     */
    function _safeSwapTokens(address tokenIn, address tokenOut, uint256 amountIn, uint256 slippageBps) internal returns (bool success) {
        if (amountIn == 0) return true;
        if (tokenIn == tokenOut) return false;

        uint24 bestFee = DEFAULT_POOL_FEE;
        try this.getMostLiquidPool(tokenIn, tokenOut) returns (uint24 fee, address) {
            bestFee = fee;
        } catch {
        }

        uint256 expectedAmountOut;
        if (tokenOut == WETH_ADDRESS) {
            try this.getTokenValueInWETH(tokenIn, amountIn, bestFee) returns (uint256 amount) {
                expectedAmountOut = amount;
            } catch {
                return false;
            }
        } else if (tokenIn == WETH_ADDRESS) {
            try this.getWETHValueInToken(tokenOut, amountIn, bestFee) returns (uint256 amount) {
                expectedAmountOut = amount;
            } catch {
                return false;
            }
        } else {
            try this.getTWAPPrice(tokenIn, tokenOut, amountIn, bestFee) returns (uint256 amount) {
                expectedAmountOut = amount;
            } catch {
                return false;
            }
        }

        if (expectedAmountOut == 0) return false;
        
        uint256 amountOutMin = (expectedAmountOut * (TOTAL_WEIGHT_BASIS_POINTS - slippageBps)) / TOTAL_WEIGHT_BASIS_POINTS;

        address pool = uniswapV3Factory.getPool(tokenIn, tokenOut, bestFee);
        if (pool == address(0)) return false;
        
        bool zeroForOne = tokenIn < tokenOut;
        bytes memory data = abi.encode(tokenIn, tokenOut, bestFee);
        
        uint160 sqrtPriceLimitX96 = zeroForOne 
            ? uint160(4295128740)
            : uint160(1461446703485210103287273052203988822378723970340);
        
        try IUniswapV3Pool(pool).swap(
            address(this),
            zeroForOne,
            int256(amountIn),
            sqrtPriceLimitX96,
            data
        ) returns (int256 amount0, int256 amount1) {
            uint256 amountOut = uint256(-(zeroForOne ? amount1 : amount0));
            
            if (amountOut < amountOutMin) return false;
            
            emit FundTokenSwapped(tokenIn, amountIn, tokenOut, amountOut);
            return true;
        } catch (bytes memory reason) {
            emit SwapFailed(tokenIn, tokenOut, amountIn, reason);
            return false;
        }
    }

    /**
     * @notice Emits rebalance event with safe value retrieval
     * @param navBefore NAV before rebalance
     */
    function _emitRebalanceEvent(uint256 navBefore) internal {
        uint256 navAfter = _safeGetNAV();
        uint256 wethUsdcValue = _safeGetWETHValueInUSDC(1 ether);
        emit RebalanceCycleExecuted(navBefore, navAfter, block.timestamp, wethUsdcValue);
    }

    /**
     * @notice Rebalances the fund's assets to match target weights
     * @dev First sells tokens that are overweight, then buys tokens that are underweight
     *      Uses a two-step process to minimize price impact
     *      Always emits RebalanceCycleExecuted event when rebalancing occurs
     */
    function _rebalance() internal {
        uint256 navBeforeRebalanceAA = _safeGetNAV();
        if (navBeforeRebalanceAA == 0) {
            _emitRebalanceEvent(0);
            return;
        }

        TokenRebalanceInfo[] memory rebalanceInfos = new TokenRebalanceInfo[](allowedTokens.length);

        for (uint256 i = 0; i < allowedTokens.length; i++) {
            address currentToken = allowedTokens[i];
            rebalanceInfos[i].token = currentToken;
            rebalanceInfos[i].currentBalance = _safeGetTokenBalance(currentToken);
            rebalanceInfos[i].currentValueInAccountingAsset = _safeGetTokenValue(currentToken, rebalanceInfos[i].currentBalance);
            rebalanceInfos[i].targetValueInAccountingAsset =
                (navBeforeRebalanceAA * targetWeights[currentToken]) / TOTAL_WEIGHT_BASIS_POINTS;
            rebalanceInfos[i].deltaValueInAccountingAsset = int256(rebalanceInfos[i].targetValueInAccountingAsset)
                - int256(rebalanceInfos[i].currentValueInAccountingAsset);
        }

        for (uint256 i = 0; i < rebalanceInfos.length; i++) {
            if (rebalanceInfos[i].deltaValueInAccountingAsset < 0) {
                uint256 valueToSellInAA = uint256(-rebalanceInfos[i].deltaValueInAccountingAsset);
                uint256 amountToSellInTokenUnits;
                if (rebalanceInfos[i].currentValueInAccountingAsset > 0) {
                    amountToSellInTokenUnits = Math.min(
                        rebalanceInfos[i].currentBalance,
                        (rebalanceInfos[i].currentBalance * valueToSellInAA)
                            / rebalanceInfos[i].currentValueInAccountingAsset
                    );
                } else {
                    amountToSellInTokenUnits = 0;
                }
                if (amountToSellInTokenUnits == 0) continue;
                
                uint256 actualBalance = _safeGetTokenBalance(rebalanceInfos[i].token);
                amountToSellInTokenUnits = Math.min(amountToSellInTokenUnits, actualBalance);
                if (amountToSellInTokenUnits == 0) continue;
                
                _safeSwapTokens(rebalanceInfos[i].token, WETH_ADDRESS, amountToSellInTokenUnits, DEFAULT_SLIPPAGE_BPS);
            }
        }

        uint256 availableAccountingAssetForBuys = _safeGetTokenBalance(WETH_ADDRESS);
        if (availableAccountingAssetForBuys == 0) {
            _emitRebalanceEvent(navBeforeRebalanceAA);
            return;
        }
        
        uint256 totalAccountingAssetNeededForBuys = 0;
        for (uint256 i = 0; i < rebalanceInfos.length; i++) {
            if (rebalanceInfos[i].deltaValueInAccountingAsset > 0) {
                totalAccountingAssetNeededForBuys += uint256(rebalanceInfos[i].deltaValueInAccountingAsset);
            }
        }
        if (totalAccountingAssetNeededForBuys == 0) {
            _emitRebalanceEvent(navBeforeRebalanceAA);
            return;
        }

        for (uint256 i = 0; i < rebalanceInfos.length; i++) {
            if (rebalanceInfos[i].deltaValueInAccountingAsset > 0) {
                uint256 idealAAToSpend = uint256(rebalanceInfos[i].deltaValueInAccountingAsset);
                uint256 actualAAToSpend = (
                    idealAAToSpend * Math.min(availableAccountingAssetForBuys, totalAccountingAssetNeededForBuys)
                ) / totalAccountingAssetNeededForBuys;
                
                uint256 currentAABalance = _safeGetTokenBalance(WETH_ADDRESS);
                actualAAToSpend = Math.min(actualAAToSpend, currentAABalance);
                if (actualAAToSpend == 0) continue;
                
                _safeSwapTokens(WETH_ADDRESS, rebalanceInfos[i].token, actualAAToSpend, DEFAULT_SLIPPAGE_BPS);
            }
        }

        _emitRebalanceEvent(navBeforeRebalanceAA);
    }

    /**
     * @notice Swaps tokens using Uniswap V3
     * @dev Uses Uniswap V3 router to execute a swap with slippage protection
     * @param _tokenIn Address of the token to sell
     * @param _tokenOut Address of the token to buy
     * @param _amountIn Amount of input token to swap
     * @param _slippageBps Maximum acceptable slippage in basis points
     */
    function _swapTokens(address _tokenIn, address _tokenOut, uint256 _amountIn, uint256 _slippageBps) internal {
        if (_amountIn == 0) return;
        if (_tokenIn == _tokenOut) revert E5();

        // Try to find the best pool fee tier
        uint24 bestFee = DEFAULT_POOL_FEE;
        try this.getMostLiquidPool(_tokenIn, _tokenOut) returns (uint24 fee, address) {
            bestFee = fee;
        } catch {
            // Use default fee if getMostLiquidPool fails
        }

        // Get expected amount out using optimized WETH TWAP Oracle functions
        uint256 expectedAmountOut;
        if (_tokenOut == WETH_ADDRESS) {
            // Converting any token to WETH
            try this.getTokenValueInWETH(_tokenIn, _amountIn, bestFee) returns (uint256 amount) {
                expectedAmountOut = amount;
            } catch {
                revert E6();
            }
        } else if (_tokenIn == WETH_ADDRESS) {
            // Converting WETH to any token
            try this.getWETHValueInToken(_tokenOut, _amountIn, bestFee) returns (uint256 amount) {
                expectedAmountOut = amount;
            } catch {
                revert E6();
            }
        } else {
            // Converting between two non-WETH tokens
            try this.getTWAPPrice(_tokenIn, _tokenOut, _amountIn, bestFee) returns (uint256 amount) {
                expectedAmountOut = amount;
            } catch {
                revert E6();
            }
        }

        if (expectedAmountOut == 0) revert E6();
        
        uint256 amountOutMin = (expectedAmountOut * (TOTAL_WEIGHT_BASIS_POINTS - _slippageBps)) / TOTAL_WEIGHT_BASIS_POINTS;

        // Get the pool for this token pair and fee
        address pool = uniswapV3Factory.getPool(_tokenIn, _tokenOut, bestFee);
        if (pool == address(0)) revert E6(); // Pool doesn't exist
        
        // Determine swap direction
        bool zeroForOne = _tokenIn < _tokenOut;
        
        // Prepare callback data
        bytes memory data = abi.encode(_tokenIn, _tokenOut, bestFee);
        
        // Calculate price limit to avoid "SPL" (Slippage Protection Limit) error
        // Use the working price limits from our successful test
        uint160 sqrtPriceLimitX96 = zeroForOne 
            ? uint160(4295128740)  // MIN_SQRT_RATIO + 1 (working value)
            : uint160(1461446703485210103287273052203988822378723970340); // MAX_SQRT_RATIO - 1 (working value)
        
        // Execute the swap directly with the pool
        try IUniswapV3Pool(pool).swap(
            address(this), // recipient
            zeroForOne,
            int256(_amountIn),
            sqrtPriceLimitX96,
            data
        ) returns (int256 amount0, int256 amount1) {
            uint256 amountOut = uint256(-(zeroForOne ? amount1 : amount0));
            
            // Check we received enough tokens
            if (amountOut < amountOutMin) revert E6();
            
            emit FundTokenSwapped(_tokenIn, _amountIn, _tokenOut, amountOut);
        } catch (bytes memory reason) {
            // If swap fails, emit an event and revert with more context
            emit SwapFailed(_tokenIn, _tokenOut, _amountIn, reason);
            revert E6(); // Swap failed
        }
    }


    /**
     * @notice Approves a token for spending if current allowance is insufficient
     * @dev Avoids unnecessary approve calls if allowance is already sufficient
     * @param _tokenContract The ERC20 token contract
     * @param _spender Address to approve spending for
     * @param _amount Amount to approve
     */
    function _approveTokenIfNeeded(IERC20 _tokenContract, address _spender, uint256 _amount) internal {
        if (_tokenContract.allowance(address(this), _spender) < _amount) {
            _tokenContract.forceApprove(_spender, _amount);
        }
    }
    
    /**
     * @notice Gets the value of a token amount in WETH units (accounting asset)
     * @dev Uses the optimized WETH-specific TWAP Oracle function
     * @param _token Address of the token to value
     * @param _amount Amount of the token to value
     * @return WETH value of the specified token amount
     */
    function _getTokenValueInAccountingAsset(address _token, uint256 _amount) internal view returns (uint256) {
        if (_amount == 0) return 0;
        if (_token == WETH_ADDRESS) revert E5(); // Token should not be WETH itself

        // Use the optimized WETH helper function with fallback fee tiers
        try this.getTokenValueInWETH(_token, _amount, DEFAULT_POOL_FEE) returns (uint256 value) {
            return value;
        } catch {
            // Fallback to other fee tiers
            try this.getTokenValueInWETH(_token, _amount, 500) returns (uint256 value) {
                return value;
            } catch {
                try this.getTokenValueInWETH(_token, _amount, 10000) returns (uint256 value) {
                    return value;
                } catch {
                    return 0;
                }
            }
        }
    }

    
    /**
     * @notice Gets the USDC value of a given WETH amount
     * @dev Uses the optimized WETH-specific TWAP Oracle function
     * @param _wethAmount Amount of WETH to convert
     * @return USDC value of the WETH amount
     */
    function _getWETHValueInUSDC(uint256 _wethAmount) internal view returns (uint256) {
        if (_wethAmount == 0) return 0;
        
        // Use the optimized WETH helper function with fallback fee tiers
        try this.getWETHValueInToken(USDC_ADDRESS, _wethAmount, DEFAULT_POOL_FEE) returns (uint256 value) {
            return value;
        } catch {
            // Fallback to other fee tiers
            try this.getWETHValueInToken(USDC_ADDRESS, _wethAmount, 500) returns (uint256 value) {
                return value;
            } catch {
                try this.getWETHValueInToken(USDC_ADDRESS, _wethAmount, 10000) returns (uint256 value) {
                    return value;
                } catch {
                    return 0;
                }
            }
        }
    }

    /**
     * @notice Checks if the fund needs rebalancing
     * @dev Compares current asset weights to target weights and determines maximum deviation
     * @return needsRebalance True if any asset deviates from target by more than threshold
     * @return maxDeviationBPS Maximum deviation found in basis points
     */
    function _isRebalanceNeeded() internal view returns (bool needsRebalance, uint256 maxDeviationBPS) {
        uint256 currentNAV = totalNAVInAccountingAsset();
        if (currentNAV == 0) {
            return (false, 0);
        }
        maxDeviationBPS = 0;
        needsRebalance = false; // Explicitly initialize
        for (uint256 i = 0; i < allowedTokens.length; i++) {
            address currentToken = allowedTokens[i];
            uint256 tokenBalance = IERC20(currentToken).balanceOf(address(this));
            uint256 tokenValueInAA = _getTokenValueInAccountingAsset(currentToken, tokenBalance);
            
            // This check `if (currentNAV == 0) return (true, TOTAL_WEIGHT_BASIS_POINTS);` was inside the loop
            // and would cause issues if the first token had 0 value but NAV was non-zero due to other tokens.
            // The initial currentNAV == 0 check at the function start handles the main case.
            // If currentNAV becomes 0 mid-loop due to an unpriceable token, calculations might be skewed.
            // _getTokenValueInAccountingAsset returns 0 for unpriceable tokens, which is handled.

            uint256 actualWeightBPS = (tokenValueInAA * TOTAL_WEIGHT_BASIS_POINTS) / currentNAV;
            uint256 targetWeightBPS = targetWeights[currentToken];
            uint256 deviation = actualWeightBPS > targetWeightBPS ? actualWeightBPS - targetWeightBPS : targetWeightBPS - actualWeightBPS;
            if (deviation > maxDeviationBPS) maxDeviationBPS = deviation;
            if (deviation > REBALANCE_DEVIATION_THRESHOLD_BPS) needsRebalance = true;
        }
        // Emitting RebalanceCheck here is more informative as it's called before deciding to rebalance.
        // The deposit/withdraw functions will also emit it.
        return (needsRebalance, maxDeviationBPS);
    }

    /**
     * @notice Callback function required by Uniswap V3 for swap execution
     * @dev This function is called by the Uniswap V3 pool during swap execution
     * @param amount0Delta Change in token0 balance 
     * @param amount1Delta Change in token1 balance
     * @param data Encoded swap data
     */
    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata data
    ) external override {
        require(amount0Delta > 0 || amount1Delta > 0, "Invalid swap");
        
        // Decode the data to get token addresses and fee
        (address tokenIn, address tokenOut, uint24 fee) = abi.decode(data, (address, address, uint24));
        
        // Verify the callback is from a legitimate Uniswap V3 pool
        address expectedPool = uniswapV3Factory.getPool(tokenIn, tokenOut, fee);
        require(msg.sender == expectedPool, "Invalid callback sender");
        
        // Determine which token we need to pay and how much
        address tokenToPay;
        uint256 amountToPay;
        
        if (amount0Delta > 0) {
            tokenToPay = tokenIn < tokenOut ? tokenIn : tokenOut;
            amountToPay = uint256(amount0Delta);
        } else {
            tokenToPay = tokenIn < tokenOut ? tokenOut : tokenIn;
            amountToPay = uint256(amount1Delta);
        }
        
        // Transfer the required tokens to the pool
        IERC20(tokenToPay).safeTransfer(msg.sender, amountToPay);
    }

    // Interface compatibility functions
    function ACCOUNTING_ASSET() external view returns (address) {
        return WETH_ADDRESS;
    }

}