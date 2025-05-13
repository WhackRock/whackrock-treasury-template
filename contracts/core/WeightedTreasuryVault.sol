// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import { ERC20 }        from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC4626 }       from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import { ERC20Snapshot } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Snapshot.sol";
import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { ISwapAdapter } from "./adapters/ISwapAdapter.sol";
import { IPriceOracle } from "./adapters/IPriceOracle.sol";

/**
 * @title WeightedTreasuryVault
 * @dev  Base ETH + USDC.b ERC-4626 vault with:
 *       • up-front management fee on every deposit
 *       • fee split 80 % → devWallet, 20 % → wrkRewards
 *       • Auto-rebalancing if weights deviate by >2%
 *       • Can rebalance to any asset in the allowed list
 */
contract WeightedTreasuryVault is ERC4626, ERC20Snapshot {
    using SafeERC20 for IERC20;

    /*═══════════════ IMMUTABLE CONFIG ═══════════════*/
    address public constant BASE_ETH = address(0);
    address public immutable USDCb;
    IERC20[] public immutable allowedAssets;  // All assets that can be held
    ISwapAdapter public immutable adapter;
    IPriceOracle public immutable oracle;
    address public immutable manager;        // GAME Worker
    address public immutable wrkRewards;     // gets 20 % of each fee
    uint16  public immutable mgmtFeeBps;     // e.g. 200 = 2 %
    uint16  public constant REBALANCE_THRESHOLD = 200; // 2% deviation threshold

    /*═══════════════  STATE  ═══════════════════════*/
    uint256[] public targetWeights;          // 1e4 basis-points
    address public devWallet;                // gets 80 % of each fee

    /*────────────── modifiers ─────────────*/
    modifier onlyM() { require(msg.sender == manager, "not manager"); _; }

    /*────────────── constructor ───────────*/
    constructor(
        string   memory name_,
        string   memory sym_,
        address  _usdcb,
        IERC20[] memory _allowedAssets,
        uint256[] memory _weights,
        address  _manager,
        ISwapAdapter _adapter,
        IPriceOracle _oracle,
        uint16   _mgmtFeeBps,            // 0-1000 (10 % max)
        address  _devWallet,
        address  _wrkRewards
    )
        ERC20(name_, sym_)
        ERC4626(IERC20(_usdcb))          // USDC.b as the "asset" for 4626
    {
        require(_mgmtFeeBps <= 1_000, "fee>10%");
        require(_allowedAssets.length == _weights.length && _allowedAssets.length <= 8, "len");
        uint256 sum; for (uint i; i<_weights.length; ++i) sum += _weights[i];
        require(sum == 1e4, "weights");

        USDCb = _usdcb;
        allowedAssets = _allowedAssets;
        targetWeights = _weights;
        manager      = _manager;
        adapter      = _adapter;
        oracle       = _oracle;
        mgmtFeeBps   = _mgmtFeeBps;
        devWallet    = _devWallet;
        wrkRewards   = _wrkRewards;

        _approveTokens();
        _snapshot();                     // snapshot id 1
    }

    /*────────────── 4626 overrides ─────────*/
    function totalAssets() public view override returns (uint256 usd) {
        // Get ETH value in USD
        uint256 ethBalance = address(this).balance;
        uint256 ethUsd = ethBalance * oracle.usdPrice(BASE_ETH) / 1e18;
        
        // Get USDC.b value (already in USD)
        uint256 usdcBalance = IERC20(USDCb).balanceOf(address(this));
        
        // Get other assets value in USD
        for (uint i; i<allowedAssets.length; ++i) {
            if (address(allowedAssets[i]) != USDCb) {  // Skip USDC.b as it's already counted
                usd += oracle.usdPrice(address(allowedAssets[i]))
                     * allowedAssets[i].balanceOf(address(this)) / 1e18;
            }
        }
        
        return ethUsd + usdcBalance + usd;
    }

    function convertToShares(uint256 assetsUsd, uint256)
        public view override returns (uint256)
    { return totalSupply()==0 ? assetsUsd : assetsUsd*totalSupply()/totalAssets(); }

    function convertToAssets(uint256 shares)
        public view override returns (uint256)
    { return shares*totalAssets()/totalSupply(); }

    /*────────────── DEPOSIT (fee taken here) ─────────*/
    function deposit(uint256 assetsUsd, address receiver)
        public payable override returns (uint256 sharesOut)
    {
        uint256 gross = convertToShares(assetsUsd, 0);
        uint256 fee   = gross * mgmtFeeBps / 10_000;
        uint256 dev   = fee * 8_000 / 10_000;
        uint256 wrk   = fee - dev;                     // 20 %

        _mint(devWallet,   dev);
        _mint(wrkRewards,  wrk);
        _mint(receiver,    gross - fee);
        sharesOut = gross - fee;

        // Handle ETH deposit
        if (msg.value > 0) {
            require(msg.value * oracle.usdPrice(BASE_ETH) / 1e18 == assetsUsd, "eth value");
        } else {
            // Handle USDC.b deposit
            IERC20(USDCb).safeTransferFrom(msg.sender, address(this), assetsUsd);
        }

        // Check if rebalancing is needed
        _checkAndRebalance();
        _snapshot();
    }

    /*────────────── WITHDRAW (no fee) ───────────────*/
    function withdraw(uint256 shares, address receiver, address owner)
        public override returns (uint256 assetsUsd)
    {
        if (owner != msg.sender)
            _spendAllowance(owner, msg.sender, shares);

        assetsUsd = convertToAssets(shares);
        _burn(owner, shares);

        // Calculate proportional amounts based on target weights
        for (uint i; i<allowedAssets.length; ++i) {
            uint256 amount = assetsUsd * targetWeights[i] / 1e4;
            if (address(allowedAssets[i]) == BASE_ETH) {
                uint256 ethAmount = amount * 1e18 / oracle.usdPrice(BASE_ETH);
                (bool success,) = receiver.call{value: ethAmount}("");
                require(success, "eth transfer failed");
            } else {
                allowedAssets[i].safeTransfer(receiver, amount);
            }
        }

        _snapshot();
    }

    /*────────────── MANAGER OPS ─────────────────────*/
    function setWeights(uint256[] calldata w) external onlyM {
        require(w.length == allowedAssets.length, "len");
        uint s; for(uint i;i<w.length;++i) s+=w[i];
        require(s == 1e4, "sum");
        targetWeights = w;
    }

    function setDevWallet(address newDev) external onlyM {
        devWallet = newDev;
    }

    function rebalance(bytes calldata data) external onlyM {
        (bool ok,) = address(adapter).call(data);
        require(ok, "swap fail");
        _snapshot();
    }

    /*────────────── INTERNAL ────────────────────────*/
    function _checkAndRebalance() internal {
        uint256 total = totalAssets();
        if (total == 0) return;

        // Check each asset's weight deviation
        for (uint i; i<allowedAssets.length; ++i) {
            uint256 currentBalance;
            if (address(allowedAssets[i]) == BASE_ETH) {
                currentBalance = address(this).balance * oracle.usdPrice(BASE_ETH) / 1e18;
            } else {
                currentBalance = allowedAssets[i].balanceOf(address(this));
                if (address(allowedAssets[i]) != USDCb) {
                    currentBalance = currentBalance * oracle.usdPrice(address(allowedAssets[i])) / 1e18;
                }
            }
            
            uint256 currentWeight = currentBalance * 1e4 / total;
            
            // If deviation is more than 2%, trigger rebalance
            if (currentWeight > targetWeights[i] + REBALANCE_THRESHOLD ||
                currentWeight < targetWeights[i] - REBALANCE_THRESHOLD) {
                
                // Calculate required swap
                uint256 targetBalance = total * targetWeights[i] / 1e4;
                uint256 diff = currentBalance > targetBalance ? 
                    currentBalance - targetBalance : 
                    targetBalance - currentBalance;
                
                // Prepare swap data (to be implemented based on your adapter)
                bytes memory swapData = _prepareSwapData(
                    address(allowedAssets[i]),
                    diff,
                    currentBalance > targetBalance
                );
                
                // Execute rebalance
                (bool ok,) = address(adapter).call(swapData);
                require(ok, "rebalance failed");
            }
        }
    }

    function _prepareSwapData(
        address token,
        uint256 amount,
        bool isSelling
    ) internal view returns (bytes memory) {
        // This function should be implemented based on your specific adapter
        // It should return the calldata needed to swap between any two assets
        revert("not implemented");
    }

    function _approveTokens() internal {
        for (uint i; i<allowedAssets.length; ++i) {
            if (address(allowedAssets[i]) != BASE_ETH) {
                allowedAssets[i].safeApprove(address(adapter), type(uint).max);
            }
        }
    }

    // Allow receiving ETH
    receive() external payable {}
}
