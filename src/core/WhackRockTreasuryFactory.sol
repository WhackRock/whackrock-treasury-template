// SPDX-License-Identifier: BUSL-1.1
// Copyright (C) 2024 WhackRock Labs. All rights reserved.
pragma solidity ^0.8.20;


import { WeightedTreasuryVault } from "./WeightedTreasuryVault.sol";
import "./interfaces/ISwapAdapter.sol";
import "./interfaces/IPriceOracle.sol";
import "./interfaces/IWhackRockTreasuryFactory.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract WhackRockTreasuryFactory is IWhackRockTreasuryFactory, Ownable {


    address public override USDCb;                 // Base USDC.b address
    ISwapAdapter public override adapter;
    IPriceOracle public override oracle;
    address public override wrkRewards;            // global 20 % sink

    address[] public override allowedAssets;       // Master list of allowed assets
    
    // Registry functionality
    address[] public treasuries;                   // Array of all created treasuries
    mapping(string => address) public treasuryNames; // Mapping of treasury names to addresses to ensure uniqueness
    
    // Owner tracking
    mapping(address => address[]) private vaultsByOwner;  // Mapping of owner address to their vaults

    constructor(
        address _usdcb,
        address[] memory _allowedAssets,
        ISwapAdapter _adapter,
        IPriceOracle _oracle,
        address _wrkRewards
    ) Ownable(msg.sender) {
        USDCb       = _usdcb;
        adapter     = _adapter;
        oracle      = _oracle;
        wrkRewards  = _wrkRewards;

        // Validate initial allowed assets
        // require(_allowedAssets.length <= 8, "too many assets");
        require(_allowedAssets.length >= 2, "min 2 assets");
        
        // Check that USDC.b is included
        bool hasUsdcb;
        for (uint i; i < _allowedAssets.length; ++i) {
            if (_allowedAssets[i] == USDCb) {
                hasUsdcb = true;
                break;
            }
        }
        require(hasUsdcb, "must include USDC.b");

        allowedAssets = _allowedAssets;
    }

    // Registry getter functions
    
    /**
     * @notice Get the total number of treasuries created by this factory
     * @return count Number of treasuries
     */
    function getTreasuryCount() external view returns (uint256) {
        return treasuries.length;
    }
    
    /**
     * @notice Get all treasuries created by this factory
     * @return Array of treasury addresses
     */
    function getAllTreasuries() external view returns (address[] memory) {
        return treasuries;
    }
    
    /**
     * @notice Check if a treasury name is already taken
     * @param name The treasury name to check
     * @return bool True if the name is already taken
     */
    function isTreasuryNameTaken(string calldata name) external view returns (bool) {
        return treasuryNames[name] != address(0);
    }

    /**
     * @notice Get all vaults owned by a specific address
     * @param owner The owner's address
     * @return Array of vault addresses owned by the specified address
     */
    function getVaultsByOwner(address owner) external view returns (address[] memory) {
        return vaultsByOwner[owner];
    }


    /**
     * @notice Set a new USDC.b token address
     * @param _newUSDCb The new USDC.b address
     */
    function setUSDCb(address _newUSDCb) external onlyOwner {
        require(_newUSDCb != address(0), "Zero address not allowed");
        address oldUSDCb = USDCb;
        USDCb = _newUSDCb;
        
        // Update allowedAssets to include new USDC.b
        bool hasNewUsdcb = false;
        for (uint i = 0; i < allowedAssets.length; ++i) {
            if (allowedAssets[i] == _newUSDCb) {
                hasNewUsdcb = true;
                break;
            }
        }
        
        if (!hasNewUsdcb) {
            // Replace old USDC.b with new USDC.b in allowedAssets
            for (uint i = 0; i < allowedAssets.length; ++i) {
                if (allowedAssets[i] == oldUSDCb) {
                    allowedAssets[i] = _newUSDCb;
                    break;
                }
            }
            emit AllowedAssetsUpdated(allowedAssets);
        }
        
        emit USDCbUpdated(oldUSDCb, _newUSDCb);
    }

    /**
     * @notice Set a new swap adapter
     * @param _newAdapter The new adapter address
     */
    function setAdapter(ISwapAdapter _newAdapter) external onlyOwner {
        require(address(_newAdapter) != address(0), "Zero address not allowed");
        ISwapAdapter oldAdapter = adapter;
        adapter = _newAdapter;
        emit AdapterUpdated(address(oldAdapter), address(_newAdapter));
    }

    /**
     * @notice Set a new price oracle
     * @param _newOracle The new oracle address
     */
    function setOracle(IPriceOracle _newOracle) external onlyOwner {
        require(address(_newOracle) != address(0), "Zero address not allowed");
        IPriceOracle oldOracle = oracle;
        oracle = _newOracle;
        emit OracleUpdated(address(oldOracle), address(_newOracle));
    }

    /**
     * @notice Set a new rewards address
     * @param _newWrkRewards The new rewards address
     */
    function setWrkRewards(address _newWrkRewards) external onlyOwner {
        require(_newWrkRewards != address(0), "Zero address not allowed");
        address oldWrkRewards = wrkRewards;
        wrkRewards = _newWrkRewards;
        emit WrkRewardsUpdated(oldWrkRewards, _newWrkRewards);
    }

    function setAllowedAssets(address[] calldata newAssets) external override onlyOwner {
        // require(newAssets.length <= 8, "too many assets");
        require(newAssets.length >= 2, "min 2 assets");
        
        // Check that USDC.b is included
        bool hasUsdcb;
        for (uint i; i < newAssets.length; ++i) {
            if (newAssets[i] == USDCb) {
                hasUsdcb = true;
                break;
            }
        }
        require(hasUsdcb, "must include USDC.b");

        allowedAssets = newAssets;
        emit AllowedAssetsUpdated(newAssets);
    }

    function getAllowedAssets() external view override returns (address[] memory) {
        return allowedAssets;
    }

    /**
     * @notice Add a new asset to the list of allowed assets
     * @param asset Address of the asset to add
     */
    function addAllowedAsset(address asset) external override onlyOwner {
        // Check if asset already exists in the list
        for (uint i = 0; i < allowedAssets.length; ++i) {
            if (allowedAssets[i] == asset) {
                return; // Asset already in list, nothing to do
            }
        }
        
        // Add new asset to the list
        address[] memory newAssets = new address[](allowedAssets.length + 1);
        for (uint i = 0; i < allowedAssets.length; ++i) {
            newAssets[i] = allowedAssets[i];
        }
        newAssets[allowedAssets.length] = asset;
        
        // Update allowedAssets
        allowedAssets = newAssets;
        
        // Emit event
        emit AllowedAssetsUpdated(allowedAssets);
    }
    
    /**
     * @notice Remove an asset from the list of allowed assets
     * @param asset Address of the asset to remove
     */
    function deleteAllowedAsset(address asset) external override onlyOwner {
        // Cannot remove USDC.b
        require(asset != USDCb, "cannot remove USDC.b");
        
        // Find index of asset in the list
        uint assetIndex = type(uint).max; // Invalid index by default
        for (uint i = 0; i < allowedAssets.length; ++i) {
            if (allowedAssets[i] == asset) {
                assetIndex = i;
                break;
            }
        }
        
        // If asset not found, nothing to do
        if (assetIndex == type(uint).max) {
            return;
        }
        
        // Create new array without the asset
        address[] memory newAssets = new address[](allowedAssets.length - 1);
        
        // Copy elements before the index
        for (uint i = 0; i < assetIndex; ++i) {
            newAssets[i] = allowedAssets[i];
        }
        
        // Copy elements after the index
        for (uint i = assetIndex + 1; i < allowedAssets.length; ++i) {
            newAssets[i - 1] = allowedAssets[i];
        }
        
        // Verify we have at least 2 assets left
        require(newAssets.length >= 2, "min 2 assets required");
        
        // Update allowedAssets
        allowedAssets = newAssets;
        
        // Emit event
        emit AllowedAssetsUpdated(allowedAssets);
    }

    /**
     * @param allowedAssetsSubset Array of asset addresses to use for this vault (must be subset of allowedAssets)
     * @param weights       Corresponding weights in basis points (e.g. 6000 = 60%)
     * @param mgmtFeeBps    e.g. 200 = 2 % upfront fee
     * @param devWallet     receives 80 % of that fee
     * @param tag           "AGENT" or "FUND" – for indexers/front‑end
     */
    function createVault(
        string   calldata name,
        string   calldata sym,
        address[] calldata allowedAssetsSubset,
        uint256[] calldata weights,
        address  manager,
        uint16   mgmtFeeBps,
        address  devWallet,
        bytes32  tag
    ) external override returns (address vault) {
        // Check name uniqueness
        require(treasuryNames[name] == address(0), "Treasury name already taken");
        
        // Validate subset length
        require(allowedAssetsSubset.length <= 20, "max 20 assets");
        require(allowedAssetsSubset.length >= 2, "min 2 assets");
        
        // Validate weights match subset
        require(weights.length == allowedAssetsSubset.length, "weights len");
        
        // Check weights sum to 100%
        uint256 sum;
        for (uint i; i < weights.length; ++i) {
            sum += weights[i];
        }
        require(sum == 1e4, "weights");

        // Verify USDC.b is included
        bool hasUsdcb = false;
        for (uint i; i < allowedAssetsSubset.length; ++i) {
            if (allowedAssetsSubset[i] == USDCb) {
                hasUsdcb = true;
                break;
            }
        }
        require(hasUsdcb, "must include USDC.b");
        
        // Verify each asset in subset is in the master allowedAssets list
        for (uint i; i < allowedAssetsSubset.length; ++i) {
            bool isAllowed = false;
            for (uint j; j < allowedAssets.length; ++j) {
                if (allowedAssetsSubset[i] == allowedAssets[j]) {
                    isAllowed = true;
                    break;
                }
            }
            require(isAllowed, "asset not allowed");
        }

        // Convert addresses to IERC20 array
        IERC20[] memory erc20Assets = new IERC20[](allowedAssetsSubset.length);
        for (uint i; i < allowedAssetsSubset.length; ++i) {
            erc20Assets[i] = IERC20(allowedAssetsSubset[i]);
        }

        // Deploy new WeightedTreasuryVault via new keyword
        vault = address(new WeightedTreasuryVault(
            name,
            sym,
            USDCb,
            erc20Assets,
            weights,
            manager,
            adapter,
            oracle,
            mgmtFeeBps,
            devWallet,
            wrkRewards
        ));
        
        // Add vault to registry
        treasuries.push(vault);
        treasuryNames[name] = vault;
        
        // Add to owner mapping
        vaultsByOwner[manager].push(vault);

        emit VaultCreated(vault, manager, weights, tag);
    }
}
