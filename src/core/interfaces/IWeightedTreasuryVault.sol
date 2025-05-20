// SPDX-License-Identifier: BUSL-1.1
// Copyright (C) 2024 WhackRock Labs. All rights reserved.
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/interfaces/IERC4626.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./ISwapAdapter.sol";
import "./IPriceOracle.sol";

/**
 * @title IWeightedTreasuryVault
 * @notice Interface for WeightedTreasuryVault contract
 * @dev Designed to pair with a contract that extends ERC4626 token vault standard
 */
interface IWeightedTreasuryVault {
    /*══════════════ EVENTS ═════════════*/
    /**
     * @notice Emitted when the vault needs rebalancing
     * @param stateId The current state ID of the vault
     * @param timestamp The timestamp when rebalancing is needed
     */
    event NeedsRebalance(uint256 indexed stateId, uint256 timestamp);
    
    /**
     * @notice Emitted when the vault state changes
     * @param stateId The ID of the new state
     * @param timestamp The timestamp of the state change
     * @param tvlUsd The total value locked in USD
     * @param sharePrice The price per share
     * @param weights The new target weights
     * @param devWallet The developer wallet address
     */
    event VaultState(
        uint256 indexed stateId,
        uint256 timestamp,
        uint256 tvlUsd,
        uint256 sharePrice,
        uint256[] weights,
        address devWallet
    );

    /*══════════════ CONSTANTS ═══════════*/
    /**
     * @notice Address representing ETH (address(0))
     * @return The ETH address constant
     */
    function BASE_ETH() external view returns (address);
    
    /**
     * @notice The deviation threshold in basis points for rebalancing
     * @return The deviation threshold
     */
    function DEVIATION_BPS() external view returns (uint16);

    /*══════════════ IMMUTABLES ═══════════*/
    /**
     * @notice Get the USDC.b token address
     * @return The address of the USDC.b token
     */
    function USDCb() external view returns (address);
    
    /**
     * @notice Get the swap adapter used for rebalancing
     * @return The swap adapter contract
     */
    function adapter() external view returns (ISwapAdapter);
    
    /**
     * @notice Get the price oracle used for asset pricing
     * @return The price oracle contract
     */
    function oracle() external view returns (IPriceOracle);
    
    /**
     * @notice Get the manager address (alias for owner)
     * @return The manager address
     */
    function manager() external view returns (address);
    
    /**
     * @notice Get the rewards address that receives 20% of fees
     * @return The rewards address
     */
    function wrkRewards() external view returns (address);
    
    /**
     * @notice Get the management fee in basis points
     * @return The management fee basis points
     */
    function mgmtFeeBps() external view returns (uint16);

    /*══════════════ STATE ═══════════*/
    /**
     * @notice Get the allowed asset at a specific index
     * @param index The index in the array
     * @return The asset contract
     */
    function allowedAssets(uint256 index) external view returns (IERC20);
    
    /**
     * @notice Get the target weight for an asset at a specific index
     * @param index The index in the array
     * @return The weight in basis points
     */
    function targetWeights(uint256 index) external view returns (uint256);
    
    /**
     * @notice Get the developer wallet address that receives 80% of fees
     * @return The developer wallet address
     */
    function devWallet() external view returns (address);

    /*══════════════ FUNCTIONS ═══════════*/
    /**
     * @notice Deposit ETH into the vault
     * @param receiver Address to receive shares
     * @return sharesOut Amount of shares minted
     */
    function depositETH(address receiver) external payable returns (uint256 sharesOut);

    /**
     * @notice Burn shares and receive a single asset token
     * @param shares Vault shares to redeem
     * @param tokenOut Desired token (must be in allowed list or WETH/USDCb)
     * @param minOut Slippage guard (tokenOut units)
     * @param swapData Universal Router calldata prepared off-chain
     * @param receiver Payout address
     * @return amountOut Amount of token received
     */
    function withdrawSingle(
        uint256 shares,
        address tokenOut,
        uint256 minOut,
        bytes calldata swapData,
        address receiver
    ) external returns (uint256 amountOut);

    /**
     * @notice Set target weights for vault assets
     * @param w New weights array in basis points (must sum to 10000)
     */
    function setWeights(uint256[] calldata w) external;
    
    /**
     * @notice Set the developer wallet address
     * @param d New developer wallet address
     */
    function setDevWallet(address d) external;
    
    /**
     * @notice Execute rebalancing swaps
     */
    function rebalance() external;
    

    
    /**
     * @notice Set new weights and rebalance in one transaction
     * @param w New weights array in basis points (must sum to 10000)
     */
    function setWeightsAndRebalance(uint256[] calldata w) external;
    
    /**
     * @notice Check if the vault needs rebalancing
     * @return True if rebalancing is needed
     */
    function needsRebalance() external view returns (bool);

    /**
     * @notice Returns a full snapshot of the vault's value and composition, for subgraph indexing
     */
    function VaultSnapshot()
        external
        view
        returns (uint256 timestamp, uint256 tvlUsd, uint256 totalShares, uint256 sharePrice, address[] memory assets, uint256[] memory assetBalances, uint256[] memory assetValuesUsd, uint256[] memory weights);
} 