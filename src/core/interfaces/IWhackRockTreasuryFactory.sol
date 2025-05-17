// SPDX-License-Identifier: BUSL-1.1
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
     * @param weights The initial asset weights
     * @param tag The vault tag (e.g. "AGENT" or "FUND")
     */
    event VaultCreated(
        address vault,
        address manager,
        uint256[] weights,
        bytes32 tag
    );
    
    /**
     * @notice Emitted when the allowed assets list is updated
     * @param newAssets The new list of allowed assets
     */
    event AllowedAssetsUpdated(address[] newAssets);

    /**
     * @notice Get the implementation address used for vault deployment
     * @return The address of the implementation contract
     */
    function logic() external view returns (address);
    
    /**
     * @notice Get the USDC.b token address
     * @return The address of the USDC.b token
     */
    function USDCb() external view returns (address);
    
    /**
     * @notice Get the swap adapter used by vaults
     * @return The swap adapter contract
     */
    function adapter() external view returns (ISwapAdapter);
    
    /**
     * @notice Get the price oracle used by vaults
     * @return The price oracle contract
     */
    function oracle() external view returns (IPriceOracle);
    
    /**
     * @notice Get the rewards address that receives 20% of fees
     * @return The rewards address
     */
    function wrkRewards() external view returns (address);
    
    /**
     * @notice Get the owner address that can modify allowed assets
     * @return The owner address
     */
    function owner() external view returns (address);
    
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