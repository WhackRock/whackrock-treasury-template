// SPDX-License-Identifier: BUSL-1.1
// Copyright (C) 2024 WhackRock Labs. All rights reserved.
pragma solidity ^0.8.20;

import "./ISwapAdapter.sol";
import "./IPriceOracle.sol";

/**
 * @title IWhackRockTreasuryFactory
 * @notice Interface for WhackRockTreasuryFactory contract
 */
interface IWhackRockTreasuryFactory {
    /**
     * @notice Emitted when a new vault is created
     * @param vault The address of the created vault
     * @param manager The address of the vault manager
     * @param allowedAssetsSubset The list of all allowed assets
     * @param weights The initial asset weights
     * @param tag The vault tag (e.g. "AGENT" or "FUND")
     * @param creator The address of the creator
     */
    event VaultCreated(
        address vault,
        address manager,
        address[] allowedAssetsSubset,
        uint256[] weights,
        bytes32 tag,
        address creator
    );
    
    /**
     * @notice Emitted when the allowed assets list is updated
     * @param newAssets The new list of allowed assets
     */
    event AllowedAssetsUpdated(address[] newAssets);

    
    /**
     * @notice Emitted when the USDC.b address is updated
     * @param oldUSDCb The previous USDC.b address
     * @param newUSDCb The new USDC.b address
     */
    event USDCbUpdated(address indexed oldUSDCb, address indexed newUSDCb);
    
    /**
     * @notice Emitted when the adapter is updated
     * @param oldAdapter The previous adapter address
     * @param newAdapter The new adapter address
     */
    event AdapterUpdated(address indexed oldAdapter, address indexed newAdapter);
    
    /**
     * @notice Emitted when the oracle is updated
     * @param oldOracle The previous oracle address
     * @param newOracle The new oracle address
     */
    event OracleUpdated(address indexed oldOracle, address indexed newOracle);
    
    /**
     * @notice Emitted when the WRK rewards address is updated
     * @param oldWrkRewards The previous rewards address
     * @param newWrkRewards The new rewards address
     */
    event WrkRewardsUpdated(address indexed oldWrkRewards, address indexed newWrkRewards);

    
    /**
     * @notice Get the USDC.b token address
     * @return The address of the USDC.b token
     */
    function USDCb() external view returns (address);
    
    /**
     * @notice Set a new USDC.b token address
     * @param _newUSDCb The new USDC.b address
     */
    function setUSDCb(address _newUSDCb) external;
    
    /**
     * @notice Get the swap adapter used by vaults
     * @return The swap adapter contract
     */
    function adapter() external view returns (ISwapAdapter);
    
    /**
     * @notice Set a new swap adapter
     * @param _newAdapter The new adapter address
     */
    function setAdapter(ISwapAdapter _newAdapter) external;
    
    /**
     * @notice Get the price oracle used by vaults
     * @return The price oracle contract
     */
    function oracle() external view returns (IPriceOracle);
    
    /**
     * @notice Set a new price oracle
     * @param _newOracle The new oracle address
     */
    function setOracle(IPriceOracle _newOracle) external;
    
    /**
     * @notice Get the rewards address that receives 20% of fees
     * @return The rewards address
     */
    function wrkRewards() external view returns (address);
    
    /**
     * @notice Set a new rewards address
     * @param _newWrkRewards The new rewards address
     */
    function setWrkRewards(address _newWrkRewards) external;
    
    
    /**
     * @notice Get an allowed asset at a specific index
     * @param index The index in the array
     * @return The asset address
     */
    function allowedAssets(uint256 index) external view returns (address);
    
    /**
     * @notice Replace the entire list of allowed assets
     * @param newAssets The new list of allowed assets
     */
    function setAllowedAssets(address[] calldata newAssets) external;
    
    /**
     * @notice Get the complete list of allowed assets
     * @return The array of allowed asset addresses
     */
    function getAllowedAssets() external view returns (address[] memory);
    
    /**
     * @notice Add a new asset to the list of allowed assets
     * @param asset Address of the asset to add
     */
    function addAllowedAsset(address asset) external;
    
    /**
     * @notice Remove an asset from the list of allowed assets
     * @param asset Address of the asset to remove
     */
    function deleteAllowedAsset(address asset) external;
    
    /**
     * @notice Get a treasury vault at a specific index
     * @param index The index in the array
     * @return The treasury vault address
     */
    function treasuries(uint256 index) external view returns (address);
    
    /**
     * @notice Get the address of a treasury by its name
     * @param name The name of the treasury
     * @return The treasury vault address
     */
    function treasuryNames(string calldata name) external view returns (address);
    
    /**
     * @notice Get the total number of treasuries created by this factory
     * @return count Number of treasuries
     */
    function getTreasuryCount() external view returns (uint256);
    
    /**
     * @notice Get all treasuries created by this factory
     * @return Array of treasury addresses
     */
    function getAllTreasuries() external view returns (address[] memory);
    
    /**
     * @notice Check if a treasury name is already taken
     * @param name The treasury name to check
     * @return bool True if the name is already taken
     */
    function isTreasuryNameTaken(string calldata name) external view returns (bool);
    
    /**
     * @notice Get all vaults owned by a specific address
     * @param owner The owner's address
     * @return Array of vault addresses owned by the specified address
     */
    function getVaultsByOwner(address owner) external view returns (address[] memory);
    
    /**
     * @notice Create a new vault with custom parameters
     * @param name Name of the vault token
     * @param sym Symbol of the vault token
     * @param allowedAssetsSubset Array of asset addresses to use for this vault (must be subset of allowedAssets)
     * @param weights Corresponding weights in basis points (e.g. 6000 = 60%)
     * @param manager Address of the vault manager
     * @param mgmtFeeBps Management fee in basis points (e.g. 200 = 2% upfront fee)
     * @param devWallet Address that receives 80% of the fee
     * @param tag "AGENT" or "FUND" – for indexers/front‑end
     * @return vault The address of the created vault
     */
    function createVault(
        string calldata name,
        string calldata sym,
        address[] calldata allowedAssetsSubset,
        uint256[] calldata weights,
        address manager,
        uint16 mgmtFeeBps,
        address devWallet,
        bytes32 tag
    ) external returns (address vault);
} 