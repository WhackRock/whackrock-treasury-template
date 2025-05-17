// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;


import { WeightedTreasuryVault } from "./WeightedTreasuryVault.sol";
import "./interfaces/ISwapAdapter.sol";
import "./interfaces/IPriceOracle.sol";
import "./interfaces/IWhackRockTreasuryFactory.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract WhackRockTreasuryFactory is IWhackRockTreasuryFactory {


    address public immutable override logic;        // WeightedTreasuryVault impl
    address public immutable override USDCb;        // Base USDC.b address
    ISwapAdapter public immutable override adapter;
    IPriceOracle public immutable override oracle;
    address public immutable override wrkRewards;   // global 20 % sink
    address public override owner;                  // can update allowedAssets

    address[] public override allowedAssets;        // Master list of allowed assets

    modifier onlyOwner() {
        require(msg.sender == owner, "not owner");
        _;
    }

    constructor(
        address _logic,
        address _usdcb,
        address[] memory _allowedAssets,
        ISwapAdapter _adapter,
        IPriceOracle _oracle,
        address _wrkRewards
    ) {
        logic       = _logic;
        USDCb       = _usdcb;
        adapter     = _adapter;
        oracle      = _oracle;
        wrkRewards  = _wrkRewards;
        owner       = msg.sender;

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

        emit VaultCreated(vault, manager, weights, tag);
    }


}
