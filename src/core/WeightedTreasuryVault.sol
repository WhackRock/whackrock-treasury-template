// SPDX-License-Identifier: BUSL-1.1
// Copyright (C) 2024 WhackRock Labs. All rights reserved.
pragma solidity ^0.8.20;

import { ERC20 }        from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC4626 }      from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import { IERC20 }       from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 }    from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Ownable }      from "@openzeppelin/contracts/access/Ownable.sol";
import { Math }         from "@openzeppelin/contracts/utils/math/Math.sol";

import { ISwapAdapter } from "./interfaces/ISwapAdapter.sol";
import { IPriceOracle } from "./interfaces/IPriceOracle.sol";
import { IWeightedTreasuryVault } from "./interfaces/IWeightedTreasuryVault.sol";

/**
 * @title WeightedTreasuryVault
 * @notice  • ERC-4626 share token (asset = USDC.b)  
 *          • Up-front mgmt fee (80 % dev / 20 % WRK)  
 *          • Emits NeedsRebalance if any asset drifts ±2 %  
 *          • Supports **basket withdraw** _and_ **single-asset withdraw**
 */
contract WeightedTreasuryVault is ERC4626, IWeightedTreasuryVault, Ownable {
    using SafeERC20 for IERC20;

    /*══════════════ CONFIG ══════════════*/
    address public constant BASE_ETH = address(0);
    uint16  public constant DEVIATION_BPS = 200;  // 2 %

    address public immutable USDCb;
    ISwapAdapter public immutable adapter;
    IPriceOracle public immutable oracle;
    address public immutable wrkRewards;
    uint16  public immutable mgmtFeeBps;          // e.g. 200 = 2 %

    /*══════════════ STATE ═══════════════*/
    IERC20[]  public allowedAssets;               // max 8
    uint256[] public targetWeights;               // 1e4 bps
    address   public devWallet;
    uint256   private stateId;


    /*══════════════ CONSTRUCTOR ═══════*/
    constructor(
        string   memory name_,
        string   memory sym_,
        address  _usdcb,
        IERC20[] memory _assets,
        uint256[] memory _weights,
        address  _manager,
        ISwapAdapter _adapter,
        IPriceOracle _oracle,
        uint16   _feeBps,
        address  _dev,
        address  _rewards
    )
        ERC20(name_, sym_)
        ERC4626(IERC20(_usdcb))   // USDC.b is the accounting asset
        Ownable(_manager)
    {
        require(_feeBps <= 1_000, "fee > 10%");
        require(_assets.length == _weights.length && _assets.length <= 8, "len");

        uint256 s;
        for (uint i; i < _weights.length; ++i) s += _weights[i];
        require(s == 1e4, "weights");

        USDCb  = _usdcb;
        allowedAssets = _assets;
        targetWeights = _weights;
        adapter   = _adapter;
        oracle    = _oracle;
        mgmtFeeBps= _feeBps;
        devWallet = _dev;
        wrkRewards= _rewards;

        _approveTokens();
        
        // Initialize with a small amount of shares to prevent inflation attacks
        _mint(owner(), 1e3); // Mint small amount to initialize
        
        _emitState();     // snapshot id 0
    }

    /*════════════ ERC-4626 VIEW ═══════*/
    function totalAssets() public view override returns (uint256 usd) {
        usd += address(this).balance * oracle.usdPrice(BASE_ETH) / 1e18;
        usd += IERC20(USDCb).balanceOf(address(this));
        for (uint i; i < allowedAssets.length; ++i) {
            address tok = address(allowedAssets[i]);
            if (tok == USDCb) continue;
            uint256 bal = allowedAssets[i].balanceOf(address(this));
            usd += bal * oracle.usdPrice(tok) / 1e18;
        }
    }
    
    // Add protection against inflation attacks in convertToShares
    function convertToShares(uint256 assets)
        public view override returns (uint256)
    { 
        uint256 supply = totalSupply();
        uint256 _totalAssets = totalAssets();
        
        if (supply == 0 || _totalAssets == 0) {
            // For the first deposit, use a fixed 1:1 ratio
            return assets;
        } else {
            // Add a small virtual amount to both supply and assets 
            // to make manipulation more expensive
            uint256 virtualSupply = 1e18; // Small virtual shares
            uint256 virtualAssets = 1e18; // Corresponding assets
            
            return assets * (supply + virtualSupply) / (_totalAssets + virtualAssets);
        }
    }
    
    function convertToAssets(uint256 shares)
        public view override returns (uint256)
    { 
        uint256 supply = totalSupply();
        if (supply == 0) return shares;
        
        // Add a small virtual amount to both supply and assets
        uint256 virtualSupply = 1e18; // Small virtual shares
        uint256 virtualAssets = 1e18; // Corresponding assets
        
        return shares * (totalAssets() + virtualAssets) / (supply + virtualSupply);
    }

    /*════════════ DEPOSIT (USDC.b) ═════*/
    function deposit(uint256 assets, address receiver)
        public override  returns (uint256 sharesOut)
    {
        // Require minimum initial deposit for the first substantial deposit
        if (totalSupply() <= 1e3) {
            require(assets >= 1e6, "Initial deposit too small");
        }
    
        IERC20(USDCb).safeTransferFrom(msg.sender, address(this), assets);

        // Calculate fee on assets first
        uint256 fee = assets * mgmtFeeBps / 10_000;
        uint256 netAssets = assets - fee;
        
        // Convert net assets to shares
        uint256 netShares = convertToShares(netAssets);
        require(netShares > 0, "0 shares");
        
        // Mint shares for fees and depositor
        uint256 feeShares = convertToShares(fee);
        _mint(devWallet, feeShares * 8_000 / 10_000);
        _mint(wrkRewards, feeShares - (feeShares * 8_000 / 10_000));
        _mint(receiver, netShares);
        
        sharesOut = netShares;

        if (_needsRebalance()) emit NeedsRebalance(stateId, block.timestamp);
        _emitState();
    }

    /*════════════ DEPOSIT ETH ══════════*/
    // TODO: Remove native eth deposits from contracts
    function depositETH(address receiver)
        external payable  returns (uint256 sharesOut)
    {
        // Require minimum initial deposit for the first substantial deposit
        if (totalSupply() <= 1e3) {
            require(msg.value >= 1e15, "Initial deposit too small"); // 0.001 ETH minimum
        }
    
        uint256 usd = msg.value * oracle.usdPrice(BASE_ETH) / 1e18;
        
        // Calculate fee on assets first
        uint256 fee = usd * mgmtFeeBps / 10_000;
        uint256 netAssets = usd - fee;
        
        // Convert net assets to shares
        uint256 netShares = convertToShares(netAssets);
        require(netShares > 0, "0 shares");
        
        // Mint shares for fees and depositor
        uint256 feeShares = convertToShares(fee);
        _mint(devWallet, feeShares * 8_000 / 10_000);
        _mint(wrkRewards, feeShares - (feeShares * 8_000 / 10_000));
        _mint(receiver, netShares);
        
        sharesOut = netShares;

        if (_needsRebalance()) emit NeedsRebalance(stateId, block.timestamp);
        _emitState();
    }

    /*════════════ WITHDRAW BASKET ══════*/
    function withdraw(uint256 shares, address receiver, address owner)
        public override  returns (uint256 assetsUsd)
    {
        if (owner != msg.sender) _spendAllowance(owner, msg.sender, shares);
        assetsUsd = convertToAssets(shares);
        _burn(owner, shares);

        for (uint i; i < allowedAssets.length; ++i) {
            uint256 usd = assetsUsd * targetWeights[i] / 1e4;
            _payout(receiver, allowedAssets[i], usd);
        }
        if (_needsRebalance()) emit NeedsRebalance(stateId, block.timestamp);
        _emitState();
    }

    /*══════════ SINGLE-ASSET WITHDRAW ══════*/
    /**
     * @notice Burn `shares` and receive everything in `tokenOut`.
     * @param shares      Vault shares to redeem
     * @param tokenOut    Desired token (must be in allowed list or WETH/USDCb)
     * @param minOut      Slippage guard (tokenOut units)
     * @param swapData    Universal Router calldata prepared off-chain
     * @param receiver    Payout address
     */
    function withdrawSingle(
        uint256 shares,
        address tokenOut,
        uint256 minOut,
        bytes calldata swapData,
        address receiver
    ) external  returns (uint256 amountOut) {
        require(_isAllowed(tokenOut), "token !allowed");

        // Burn shares first (reduces sharePrice for fairness)
        if (msg.sender != receiver) _spendAllowance(msg.sender, msg.sender, shares);
        _burn(msg.sender, shares);

        // Execute caller-supplied swaps (basket -> tokenOut)
        if (swapData.length > 0) {
            bool ok = adapter.execute(swapData);
            require(ok, "swap fail");
        }

        // Final balance check
        amountOut = _balanceOf(tokenOut);
        require(amountOut >= minOut, "slippage");

        _transferAsset(tokenOut, receiver, amountOut);

        _emitState();
    }

    /*══════════ MANAGER OPS ═══════════*/
    function setWeights(uint256[] calldata w) external onlyOwner {
        _setWeights(w);
        if (_needsRebalance()) emit NeedsRebalance(stateId, block.timestamp);
        _emitState();
    }
    function setDevWallet(address d) external onlyOwner { 
        require(d != address(0), "Zero address not allowed");
        devWallet = d; 
        _emitState(); 
    }

    function rebalance(bytes calldata data) external onlyOwner {
        require(adapter.execute(data), "swap fail");
        _emitState();
    }
    function setWeightsAndRebalance(bytes calldata data, uint256[] calldata w) external onlyOwner {
        _setWeights(w);
        require(adapter.execute(data), "swap fail");
        require(!_needsRebalance(), "setWeightsAndRebalance failed");
        _emitState();
    }

    /**
     * @notice Mint bootstrap shares for testing ERC4626 deposits when totalSupply is zero
     * @dev This is only used for testing and should not be used in production
     * @param shares Amount of shares to mint to the owner
     */
    function _mintBootstrapShares(uint256 shares) external onlyOwner {
        _mint(owner(), shares);
        _emitState();
    }

    /**
     * @notice Get the manager address (alias for owner)
     * @return The manager address
     */
    function manager() external view override returns (address) {
        return owner();
    }

    /*══════════ VIEW HELPERS ══════════*/
    function needsRebalance() external view returns (bool) { return _needsRebalance(); }

    /*══════════ INTERNAL LIB ══════════*/
    function _setWeights(uint256[] calldata w) internal {
        require(w.length == allowedAssets.length, "len");
        uint sum;
        for (uint i; i < w.length; ++i) sum += w[i];
        require(sum == 1e4, "sum");
        targetWeights = w;
    }
    function _needsRebalance() internal view returns (bool) {
        uint256 tvl = totalAssets();
        if (tvl == 0) return false;
        for (uint i; i < allowedAssets.length; ++i) {
            uint256 cur = _getAssetValue(allowedAssets[i]);
            uint256 tar = tvl * targetWeights[i] / 1e4;
            uint256 diff = cur > tar ? cur - tar : tar - cur;
            if (diff * 10_000 > tar * DEVIATION_BPS) return true;
        }
        return false;
    }
    function _getAssetValue(IERC20 t) internal view returns (uint256 usd) {
        address a = address(t);
        if (a == BASE_ETH) {
            usd = address(this).balance * oracle.usdPrice(BASE_ETH) / 1e18;
        } else {
            uint256 bal = t.balanceOf(address(this));
            usd = (a == USDCb) ? bal : bal * oracle.usdPrice(a) / 1e18;
        }
    }
    function _approveTokens() internal {
        for (uint i; i < allowedAssets.length; ++i)
            allowedAssets[i].approve(address(adapter), type(uint).max);
    }
    function _emitState() internal {
        uint tvl = totalAssets();
        uint px  = totalSupply()==0 ? 1e18 : tvl * 1e18 / totalSupply();
        emit VaultState(++stateId, block.timestamp, tvl, px, targetWeights, devWallet);
    }
    function _isAllowed(address tok) internal view returns (bool ok) {
        if (tok == USDCb || tok == BASE_ETH) return true;
        for (uint i; i < allowedAssets.length; ++i)
            if (address(allowedAssets[i]) == tok) return true;
    }
    function _balanceOf(address tok) internal view returns (uint256) {
        return tok == BASE_ETH ? address(this).balance : IERC20(tok).balanceOf(address(this));
    }
    function _transferAsset(address tok, address to, uint256 amt) internal {
        if (tok == BASE_ETH) {
            (bool s,) = to.call{value: amt}("");
            require(s, "eth send");
        } else {
            IERC20(tok).safeTransfer(to, amt);
        }
    }
    function _payout(address to, IERC20 token, uint256 usd) internal {
        address a = address(token);
        uint256 amt = (a == USDCb)
            ? usd
            : usd * 1e18 / oracle.usdPrice(a);
        _transferAsset(a, to, amt);
    }

    /* Fallback for ETH unwrap */
    receive() external payable {}
}