// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.20;

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
     */
    event RebalanceCycleExecuted(
        uint256 navBeforeRebalanceAA,
        uint256 navAfterRebalanceAA,
        uint256 blockTimestamp
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
     */
    event WETHDepositedAndSharesMinted(
        address indexed depositor,
        address indexed receiver,
        uint256 wethDeposited,
        uint256 sharesMinted,
        uint256 navBeforeDepositWETH,
        uint256 totalSupplyBeforeDeposit
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
     */
    event BasketAssetsWithdrawn(
        address indexed owner,
        address indexed receiver,
        uint256 sharesBurned,
        address[] tokensWithdrawn,
        uint256[] amountsWithdrawn,
        uint256 navBeforeWithdrawalWETH,
        uint256 totalSupplyBeforeWithdrawal,
        uint256 totalWETHValueOfWithdrawal
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
     * @notice Returns the total basis points used for percentage calculations
     * @return Total weight basis points (10000 = 100%)
     */
    function TOTAL_WEIGHT_BASIS_POINTS() external view returns (uint256);
    
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

    // --- NAV related functions ---
    
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
}
