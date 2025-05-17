// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;


import { WeightedTreasuryVault } from "./WeightedTreasuryVault.sol";
import "./interfaces/ISwapAdapter.sol";
import "./interfaces/IPriceOracle.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract TreasuryFactory {
    event VaultCreated(
        address vault,
        address manager,
        uint256[] weights,
        bytes32 tag
    );
    event AllowedAssetsUpdated(address[] newAssets);

    address public immutable logic;        // WeightedTreasuryVault impl
    address public immutable USDCb;        // Base USDC.b address
    ISwapAdapter public immutable adapter;
    IPriceOracle public immutable oracle;
    address public immutable wrkRewards;   // global 20 % sink
    address public owner;                  // can update allowedAssets

    address[] public allowedAssets;        // Master list of allowed assets

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

    function setAllowedAssets(address[] calldata newAssets) external onlyOwner {
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

    function getAllowedAssets() external view returns (address[] memory) {
        return allowedAssets;
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
    ) external returns (address vault) {
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
