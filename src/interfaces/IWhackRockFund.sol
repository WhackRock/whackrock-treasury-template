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
 *    WHACKROCK – AGENT MANAGED WEIGHTED FUND  
 *    © 2024 WhackRock Labs – All rights reserved.
 */

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IAerodromeRouter} from "./IRouter.sol"; // Defines IAerodromeRouter

/**
 * @title IWhackRockFund
 * @author WhackRock Labs
 * @notice Interface for the WhackRockFund contract, which implements a tokenized investment fund
 * @dev This interface defines the events and functions required for an ERC20-based investment fund
 * with automatic rebalancing, AUM fee collection, and DEX integration
 */
interface IWhackRockFund {
    // --- Events ---
    /**
     * @notice Emitted when the fund's agent is updated
     * @param oldAgent Address of the previous agent
     * @param newAgent Address of the new agent
     */
    event AgentUpdated(address indexed oldAgent, address indexed newAgent);
    
    /**
     * @notice Emitted when target weights for the fund's assets are updated
     * @param agent Address of the agent that updated the weights
     * @param tokens Array of token addresses in the fund
     * @param weights Array of corresponding target weights (in basis points)
     * @param timestamp Block timestamp when weights were updated
     */
    event TargetWeightsUpdated(
        address indexed agent,
        address[] tokens,
        uint256[] weights,
        uint256 timestamp
    );
    
    /**
     * @notice Emitted when a rebalance check is performed
     * @param needsRebalance Whether the fund needs rebalancing
     * @param maxDeviationBPS Maximum deviation in basis points from target weights
     * @param currentNAV_AA Current net asset value in accounting asset (WETH) units
     */
    event RebalanceCheck(
        bool needsRebalance, 
        uint256 maxDeviationBPS, 
        uint256 currentNAV_AA
    );
    
    /**
     * @notice Emitted when a rebalance cycle is executed
     * @param navBeforeRebalanceAA NAV in accounting asset before rebalancing
     * @param navAfterRebalanceAA NAV in accounting asset after rebalancing
     * @param blockTimestamp Block timestamp when rebalance was executed
     * @param wethValueInUSDC Value of the WETH in USDC units
     */
    event RebalanceCycleExecuted(
        uint256 navBeforeRebalanceAA,
        uint256 navAfterRebalanceAA,
        uint256 blockTimestamp,
        uint256 wethValueInUSDC
    );
    
    /**
     * @notice Emitted when tokens are swapped during rebalancing
     * @param tokenFrom Address of the token being sold
     * @param amountFrom Amount of tokenFrom sold
     * @param tokenTo Address of the token being bought
     * @param amountTo Amount of tokenTo received
     */
    event FundTokenSwapped(
        address indexed tokenFrom, 
        uint256 amountFrom, 
        address indexed tokenTo, 
        uint256 amountTo
    );
    
    /**
     * @notice Emitted during emergency token withdrawals
     * @param token Address of the token withdrawn
     * @param amount Amount of token withdrawn
     */
    event EmergencyWithdrawal(address indexed token, uint256 amount);
    
    /**
     * @notice Emitted when WETH is deposited and shares are minted
     * @param depositor Address that deposited WETH
     * @param receiver Address that received the minted shares
     * @param wethDeposited Amount of WETH deposited
     * @param sharesMinted Amount of shares minted
     * @param navBeforeDepositWETH NAV in WETH before the deposit
     * @param totalSupplyBeforeDeposit Total supply of shares before the deposit
     * @param wethValueInUSDC Value of the WETH deposited in USDC units
     */
    event WETHDepositedAndSharesMinted(
        address indexed depositor,
        address indexed receiver,
        uint256 wethDeposited,
        uint256 sharesMinted,
        uint256 navBeforeDepositWETH,
        uint256 totalSupplyBeforeDeposit,
        uint256 wethValueInUSDC
    );
    
    /**
     * @notice Emitted when shares are burned and assets are withdrawn
     * @param owner Address that owned the shares
     * @param receiver Address that received the withdrawn assets
     * @param sharesBurned Amount of shares burned
     * @param tokensWithdrawn Array of token addresses withdrawn
     * @param amountsWithdrawn Array of corresponding token amounts withdrawn
     * @param navBeforeWithdrawalWETH NAV in WETH before the withdrawal
     * @param totalSupplyBeforeWithdrawal Total supply of shares before the withdrawal
     * @param totalWETHValueOfWithdrawal Total value withdrawn in WETH units
     * @param wethValueInUSDC Value of the WETH withdrawn in USDC units
     */
    event BasketAssetsWithdrawn(
        address indexed owner,
        address indexed receiver,
        uint256 sharesBurned,
        address[] tokensWithdrawn,
        uint256[] amountsWithdrawn,
        uint256 navBeforeWithdrawalWETH,
        uint256 totalSupplyBeforeWithdrawal,
        uint256 totalWETHValueOfWithdrawal,
        uint256 wethValueInUSDC
    );
    
    /**
     * @notice Emitted when AUM fees are collected
     * @param agentFeeWallet Address receiving the agent's portion of fees
     * @param agentSharesMinted Shares minted for the agent's fee
     * @param protocolFeeRecipient Address receiving the protocol's portion of fees
     * @param protocolSharesMinted Shares minted for the protocol's fee
     * @param totalFeeValueInAccountingAsset Total fee value in accounting asset (WETH) units
     * @param navAtFeeCalculation NAV at the time of fee calculation
     * @param totalSharesAtFeeCalculation Total shares at the time of fee calculation
     * @param timestamp Block timestamp when fees were collected
     */
    event AgentAumFeeCollected(
        address indexed agentFeeWallet,
        uint256 agentSharesMinted,
        address indexed protocolFeeRecipient,
        uint256 protocolSharesMinted,
        uint256 totalFeeValueInAccountingAsset,
        uint256 navAtFeeCalculation,
        uint256 totalSharesAtFeeCalculation,
        uint256 timestamp
    );

    // --- Public State Variable Getters ---

    /**
     * @notice Returns the current agent managing the fund
     * @return Address of the current agent
     */
    function agent() external view returns (address);

    /**
     * @notice Returns the DEX router used for swaps
     * @return Aerodrome router interface
     */
    function dexRouter() external view returns (IAerodromeRouter);

    /**
     * @notice Returns the accounting asset (WETH) address
     * @return Address of the accounting asset
     */
    function ACCOUNTING_ASSET() external view returns (address);

    /**
     * @notice Returns the USDC token address
     * @return Address of the USDC token
     */
    function USDC_ADDRESS() external view returns (address);

    /**
     * @notice Returns the array of allowed token addresses
     * @param index Index in the allowed tokens array
     * @return Token address at the specified index
     */
    function allowedTokens(uint256 index) external view returns (address);

    /**
     * @notice Returns the target weight for a specific token
     * @param token Address of the token
     * @return Target weight in basis points (0-10000)
     */
    function targetWeights(address token) external view returns (uint256);

    /**
     * @notice Checks if a token is allowed in the fund
     * @param token Address of the token
     * @return True if the token is allowed, false otherwise
     */
    function isAllowedTokenInternal(address token) external view returns (bool);

    /**
     * @notice Returns the address receiving the agent's portion of AUM fees
     * @return Address of the agent AUM fee wallet
     */
    function agentAumFeeWallet() external view returns (address);

    /**
     * @notice Returns the annual AUM fee rate in basis points
     * @return AUM fee rate in basis points
     */
    function agentAumFeeBps() external view returns (uint256);

    /**
     * @notice Returns the address receiving the protocol's portion of AUM fees
     * @return Address of the protocol AUM fee recipient
     */
    function protocolAumFeeRecipient() external view returns (address);

    /**
     * @notice Returns the timestamp of the last AUM fee collection
     * @return Timestamp of the last fee collection
     */
    function lastAgentAumFeeCollectionTimestamp() external view returns (uint256);

    /**
     * @notice Returns the total basis points used for percentage calculations
     * @return Total weight basis points (10000 = 100%)
     */
    function TOTAL_WEIGHT_BASIS_POINTS() external view returns (uint256);
    
    /**
     * @notice Returns the percentage of AUM fee allocated to the agent
     * @return Agent's share of the AUM fee in basis points
     */
    function AGENT_AUM_FEE_SHARE_BPS() external view returns (uint256);
    
    /**
     * @notice Returns the percentage of AUM fee allocated to the protocol
     * @return Protocol's share of the AUM fee in basis points
     */
    function PROTOCOL_AUM_FEE_SHARE_BPS() external view returns (uint256);
    
    /**
     * @notice Returns the default slippage tolerance for swaps
     * @return Default slippage in basis points
     */
    function DEFAULT_SLIPPAGE_BPS() external view returns (uint256);
    
    /**
     * @notice Returns the deadline offset for swap transactions
     * @return Swap deadline offset in seconds
     */
    function SWAP_DEADLINE_OFFSET() external view returns (uint256);
    
    /**
     * @notice Returns the default pool stability setting for DEX swaps
     * @return True if stable pools are used by default, false for volatile pools
     */
    function DEFAULT_POOL_STABILITY() external view returns (bool);
    
    /**
     * @notice Returns the threshold for rebalancing
     * @return Rebalance deviation threshold in basis points
     */
    function REBALANCE_DEVIATION_THRESHOLD_BPS() external view returns (uint256);

    // --- Core Functions ---
    
    /**
     * @notice Calculates the total net asset value of the fund in accounting asset (WETH) units
     * @return totalManagedAssets Total NAV in WETH
     */
    function totalNAVInAccountingAsset() external view returns (uint256 totalManagedAssets);
    
    /**
     * @notice Calculates the total net asset value of the fund in USDC units
     * @return totalManagedAssetsInUSDC Total NAV in USDC
     */
    function totalNAVInUSDC() external view returns (uint256 totalManagedAssetsInUSDC);

    /**
     * @notice Deposits WETH into the fund and mints shares
     * @dev Handles first deposit specially, sets initial share price 1:1 with WETH
     *      May trigger rebalancing if asset weights deviate from targets
     * @param amountWETHToDeposit Amount of WETH to deposit
     * @param receiver Address to receive the minted shares
     * @return sharesMinted Number of shares minted
     */
    function deposit(uint256 amountWETHToDeposit, address receiver) external returns (uint256 sharesMinted);
    
    /**
     * @notice Withdraws assets from the fund by burning shares
     * @dev Burns shares and transfers a proportional amount of all fund assets to the receiver
     *      May trigger rebalancing if asset weights deviate from targets after withdrawal
     * @param sharesToBurn Number of shares to burn
     * @param receiver Address to receive the withdrawn assets
     * @param owner Address that owns the shares
     */
    function withdraw(uint256 sharesToBurn, address receiver, address owner) external;

    /**
     * @notice Collects the AUM fee by minting new shares
     * @dev Calculates fee based on time elapsed since last collection
     *      Mints new shares and distributes them between agent and protocol
     *      according to AGENT_AUM_FEE_SHARE_BPS and PROTOCOL_AUM_FEE_SHARE_BPS
     */
    function collectAgentManagementFee() external;

    /**
     * @notice Updates the fund's agent address
     * @dev Only callable by fund owner
     * @param _newAgent Address of the new agent
     */
    function setAgent(address _newAgent) external;

    /**
     * @notice Sets new target weights for the fund's assets
     * @dev Only callable by the current agent
     *      Weights must sum to TOTAL_WEIGHT_BASIS_POINTS (10000)
     * @param _weights Array of new target weights in basis points
     */
    function setTargetWeights(uint256[] calldata _weights) external;

    /**
     * @notice Sets new target weights for the fund's assets and rebalances if needed
     * @dev Only callable by the current agent
     *      Weights must sum to TOTAL_WEIGHT_BASIS_POINTS (10000)
     * @param _weights Array of new target weights in basis points
     */
    function setTargetWeightsAndRebalanceIfNeeded(uint256[] calldata _weights) external;

    /**
     * @notice Manually triggers a rebalance of the fund's assets
     * @dev Only callable by the agent
     *      Emits a RebalanceCycleExecuted event with NAV before and after
     */
    function triggerRebalance() external;

    
    /**
     * @notice Gets the target composition of the fund's assets, including token addresses and symbols.
     * @dev Returns arrays for target weights (BPS), token addresses, and token symbols.
     * The order in all arrays corresponds to the order of tokens in the `allowedTokens` array.
     * @return targetComposition_ An array of target weights in basis points.
     * @return tokenAddresses_ An array of the addresses of the allowed tokens.
     * @return tokenSymbols_ An array of the symbols of the allowed tokens.
     */
    function getTargetCompositionBPS() external view returns (uint256[] memory targetComposition_, address[] memory tokenAddresses_, string[] memory tokenSymbols_);


    /**
     * @notice Gets the current composition of the fund's assets, including token addresses and symbols.
     * @dev Returns arrays for current weights (BPS), token addresses, and token symbols.
     * The order in all arrays corresponds to the order of tokens in the `allowedTokens` array.
     * @return currentComposition_ An array of current weights in basis points.
     * @return tokenAddresses_ An array of the addresses of the allowed tokens.
     * @return tokenSymbols_ An array of the symbols of the allowed tokens.
     */
    function getCurrentCompositionBPS() external view returns (uint256[] memory currentComposition_, address[] memory tokenAddresses_, string[] memory tokenSymbols_);
    /**
     * @notice Emergency function to withdraw ERC20 tokens
     * @dev Only callable by owner, used in case of token airdrops or emergencies
     * @param _tokenAddress Address of the token to withdraw
     * @param _to Address to receive the withdrawn tokens
     * @param _amount Amount of tokens to withdraw
     */
    function emergencyWithdrawERC20(address _tokenAddress, address _to, uint256 _amount) external;

    /**
     * @notice Emergency function to withdraw native ETH
     * @dev Only callable by owner, used in case ETH is accidentally sent to the contract
     * @param _to Address to receive the withdrawn ETH
     * @param _amount Amount of ETH to withdraw
     */
    function emergencyWithdrawNative(address payable _to, uint256 _amount) external;
}
