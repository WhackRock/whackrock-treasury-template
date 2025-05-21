// SPDX-License-Identifier: BUSL-1.1
// © 2024 WhackRock Labs – All rights reserved.
// WHACKROCK – AGENT‑MANAGED WEIGHTED VAULT
pragma solidity ^0.8.20;



import {ERC20}        from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC4626}      from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {IERC20}       from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20}    from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable}      from "@openzeppelin/contracts/access/Ownable.sol";

import {ISwapAdapter}   from "./interfaces/ISwapAdapter.sol";
import {IPriceOracle}   from "./interfaces/IPriceOracle.sol";
import {IWeightedTreasuryVault} from "./interfaces/IWeightedTreasuryVault.sol";

/**
 * @title WeightedTreasuryVault
 * @notice  ▸ ERC‑4626 share token (accounting asset = USDC.b)
 *          ▸ Up‑front management fee – 80 % dev / 20 % WRK 
 *          ▸ Emits `NeedsRebalance` if ±2 % deviation *and* auto‑rebalance disabled
 *          ▸ Supports basket withdraw, single‑asset withdraw, and ETH deposit
 *          ▸ **Auto‑rebalances** on deposit/withdraw if enabled (USDC.b → hub token)
 */
contract WeightedTreasuryVault_TESTING is ERC4626, IWeightedTreasuryVault, Ownable {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                                 CONSTANTS
    //////////////////////////////////////////////////////////////*/
    address public constant BASE_ETH = address(0);
    uint16  public constant DEVIATION_BPS = 200;     // 2 % drift band
    uint16  public constant AUTO_SLIPPAGE_BPS = 18;  // 0.18 % max slippage on auto‑swaps
    uint256 private constant VIRTUAL_SHARES  = 1e6; // 1 “virtual” share
    uint256 private constant VIRTUAL_ASSETS = 1e6; // 1 USD virtual buffer

    /*//////////////////////////////////////////////////////////////
                                 IMMUTABLES
    //////////////////////////////////////////////////////////////*/
    address      public immutable override USDCb;
    ISwapAdapter public immutable override adapter;
    IPriceOracle public immutable override oracle;
    address      public immutable override wrkRewards;
    uint16       public immutable override mgmtFeeBps;

    /*//////////////////////////////////////////////////////////////
                                   STATE
    //////////////////////////////////////////////////////////////*/
    IERC20[]  public override allowedAssets;
    uint256[] public override targetWeights;
    address   public override devWallet;

    bool public autoRebalanceEnabled = true;
    uint256 private stateId;

    /*//////////////////////////////////////////////////////////////
                                    EVENTS
    //////////////////////////////////////////////////////////////*/
    event AutoRebalanceExecuted(uint256 tvlUsd, uint256 timestamp);
    event AutoRebalanceSkipped(string reason, uint256 timestamp);

    /*//////////////////////////////////////////////////////////////
                                 CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
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
        ERC4626(IERC20(_usdcb))
        Ownable(_manager)
    {
        require(_feeBps <= 1_000, "fee too high" );
        require(_assets.length == _weights.length && _assets.length <= 8, "len err");

        uint256 s;
        for (uint i; i < _weights.length; ++i) s += _weights[i];
        require(s == 1e4, "weights!10000");

        USDCb         = _usdcb;
        allowedAssets = _assets;
        targetWeights = _weights;
        adapter       = _adapter;
        oracle        = _oracle;
        mgmtFeeBps    = _feeBps;
        devWallet     = _dev;
        wrkRewards    = _rewards;

        _approveTokens();
        _mint(owner(), 1e3); // seed against inflation‑attack
        _emitState();
    }

    /*//////////////////////////////////////////////////////////////
                           4626 VIEW – totalAssets
    //////////////////////////////////////////////////////////////*/
    function totalAssets() public view override returns (uint256 usd) {
        if (address(this).balance != 0)
            usd += address(this).balance * oracle.usdPrice(BASE_ETH) / 1e18;

        usd += IERC20(USDCb).balanceOf(address(this));

        for (uint i; i < allowedAssets.length; ++i) {
            address tok = address(allowedAssets[i]);
            if (tok == USDCb) continue;
            uint256 bal = allowedAssets[i].balanceOf(address(this));
            if (bal != 0) usd += bal * oracle.usdPrice(tok) / 1e18;
        }
    }

    /*───────────────────────────────
    *  ERC-4626 share/asset math
    *──────────────────────────────*/
    // 1st deposit => 1:1, afterwards price = TVL / supply (with small buffer)
    function convertToShares(uint256 assets)
        public
        view
        override
        returns (uint256)
    {
        uint256 supply = totalSupply();
        uint256 tvl    = totalAssets();
        return (supply == 0 || tvl == 0)
            ? assets
            : (assets * (supply + VIRTUAL_SHARES)) / (tvl + VIRTUAL_ASSETS);
    }
    
    function convertToAssets(uint256 shares)
        public
        view
        override
        returns (uint256)
    {
        uint256 supply = totalSupply();
        if (supply == 0) return shares;
        uint256 tvl = totalAssets();
        return (shares * (tvl + VIRTUAL_ASSETS)) / (supply + VIRTUAL_SHARES);
    }


    /*//////////////////////////////////////////////////////////////
                           4626 VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Returns the address of the underlying token used for the vault
     * @return Asset address (USDCb)
     */
    function asset() public view override returns (address) {
        return USDCb;
    }

    /**
     * @notice Maximum amount of assets that can be deposited for a receiver
     * @param receiver Address receiving the shares
     * @return Maximum amount of assets that can be deposited
     */
    function maxDeposit(address receiver) public view override returns (uint256) {
        return type(uint256).max;
    }

    /**
     * @notice Maximum amount of shares that can be minted for a receiver
     * @param receiver Address receiving the shares
     * @return Maximum amount of shares that can be minted
     */
    function maxMint(address receiver) public view override returns (uint256) {
        return type(uint256).max;
    }

    /**
     * @notice Maximum amount of assets that can be withdrawn by an owner
     * @param owner Address owning the shares
     * @return Maximum amount of assets that can be withdrawn
     */
    function maxWithdraw(address owner) public view override returns (uint256) {
        return convertToAssets(balanceOf(owner));
    }

    /**
     * @notice Maximum amount of shares that can be redeemed by an owner
     * @param owner Address owning the shares
     * @return Maximum amount of shares that can be redeemed
     */
    function maxRedeem(address owner) public view override returns (uint256) {
        return balanceOf(owner);
    }

    /**
     * @notice Preview the amount of shares received for depositing assets
     * @param assets Amount of assets to deposit
     * @return Amount of shares that would be minted
     */
    function previewDeposit(uint256 assets) public view override returns (uint256) {
        uint256 fee = (assets * mgmtFeeBps) / 10_000;
        uint256 netAssets = assets - fee;
        return convertToShares(netAssets);
    }

    /**
     * @notice Preview the amount of assets needed to mint shares
     * @param shares Amount of shares to mint
     * @return Amount of assets that would be needed
     */
    function previewMint(uint256 shares) public view override returns (uint256) {
        uint256 assets = convertToAssets(shares);
        // Apply fee in reverse: assets + fee = deposit amount
        return (assets * 10_000) / (10_000 - mgmtFeeBps);
    }

    /**
     * @notice Preview the amount of shares needed to withdraw assets
     * @param assets Amount of assets to withdraw
     * @return Amount of shares that would be burned
     */
    function previewWithdraw(uint256 assets) public view override returns (uint256) {
        return convertToShares(assets);
    }

    /**
     * @notice Preview the amount of assets received for redeeming shares
     * @param shares Amount of shares to redeem
     * @return Amount of assets that would be received
     */
    function previewRedeem(uint256 shares) public view override returns (uint256) {
        return convertToAssets(shares);
    }

    /**
     * @notice Get the manager address (alias for owner)
     * @return The manager address
     */
    function manager() external view override returns (address) {
        return owner();
    }

    /**
     * @notice Check if the vault needs rebalancing
     * @return True if rebalancing is needed
     */
    function needsRebalance() external view override returns (bool) {
        return _needsRebalance();
    }

    /*//////////////////////////////////////////////////////////////
                           DEPOSIT / WITHDRAW BASE
    //////////////////////////////////////////////////////////////*/
    function deposit(uint256 assets, address receiver)
        public override returns (uint256 sharesOut)
    {
        // Does this make sense?
        if (totalSupply() <= 1e3) require(assets >= 1e6, "seed small");

        IERC20(USDCb).safeTransferFrom(msg.sender, address(this), assets);

        uint256 fee = (assets * mgmtFeeBps) / 10_000;
        uint256 net = assets - fee;

        uint256 feeShares = convertToShares(fee);
        _mint(devWallet,   (feeShares * 8_000) / 10_000);
        _mint(wrkRewards,  feeShares - (feeShares * 8_000) / 10_000);

        sharesOut = convertToShares(net);
        _mint(receiver, sharesOut);

        _maybeAutoRebalance();
        _emitState();
    }

    /*//////////////////////////////////////////////////////////////
                           DEPOSIT / WITHDRAW BASE
    //////////////////////////////////////////////////////////////*/
    function deposit1(uint256 assets, address receiver)
        public  returns (uint256 sharesOut)
    {
        // Does this make sense?
        if (totalSupply() <= 1e3) require(assets >= 1e6, "seed small");

        IERC20(USDCb).safeTransferFrom(msg.sender, address(this), assets);

        // uint256 fee = (assets * mgmtFeeBps) / 10_000;
        // uint256 net = assets - fee;

        // uint256 feeShares = convertToShares(fee);
        // _mint(devWallet,   (feeShares * 8_000) / 10_000);
        // _mint(wrkRewards,  feeShares - (feeShares * 8_000) / 10_000);

        // sharesOut = convertToShares(net);
        // _mint(receiver, sharesOut);

        // _maybeAutoRebalance();
        // _emitState();
    }

    
    /*//////////////////////////////////////////////////////////////
                           DEPOSIT / WITHDRAW BASE
    //////////////////////////////////////////////////////////////*/
    function deposit2(uint256 assets, address receiver)
        public override returns (uint256 sharesOut)
    {
        // Does this make sense?
        // if (totalSupply() <= 1e3) require(assets >= 1e6, "seed small");

        IERC20(USDCb).safeTransferFrom(msg.sender, address(this), assets);

        // uint256 fee = (assets * mgmtFeeBps) / 10_000;
        // uint256 net = assets - fee;

        // uint256 feeShares = convertToShares(fee);
        // _mint(devWallet,   (feeShares * 8_000) / 10_000);
        // _mint(wrkRewards,  feeShares - (feeShares * 8_000) / 10_000);

        // sharesOut = convertToShares(net);
        // _mint(receiver, sharesOut);

        // _maybeAutoRebalance();
        // _emitState();
    }

    function deposit3(uint256 assets, address receiver) // works
        public  returns (uint256 sharesOut)
    {
        // Does this make sense?
        // if (totalSupply() <= 1e3) require(assets >= 1e6, "seed small");

        IERC20(USDCb).safeTransferFrom(msg.sender, address(this), assets);

        uint256 fee = (assets * mgmtFeeBps) / 10_000;
        uint256 net = assets - fee;

        uint256 feeShares = convertToShares(fee);
        // _mint(devWallet,   (feeShares * 8_000) / 10_000);
        // _mint(wrkRewards,  feeShares - (feeShares * 8_000) / 10_000);

        // sharesOut = convertToShares(net);
        // _mint(receiver, sharesOut);

        // _maybeAutoRebalance();
        // _emitState();
    }

    function deposit4(uint256 assets, address receiver)
        public  returns (uint256 sharesOut)
    {
        // Does this make sense?
        // if (totalSupply() <= 1e3) require(assets >= 1e6, "seed small");

        IERC20(USDCb).safeTransferFrom(msg.sender, address(this), assets);

        uint256 fee = (assets * mgmtFeeBps) / 10_000;
        uint256 net = assets - fee;

        uint256 feeShares = convertToShares(fee);
        // _mint(devWallet,   (feeShares * 8_000) / 10_000);
        // _mint(wrkRewards,  feeShares - (feeShares * 8_000) / 10_000);

        sharesOut = convertToShares(net);
        _mint(receiver, sharesOut);

        // _maybeAutoRebalance();
        // _emitState();
    }

    // /**
    //  * @notice Deposit `assets` (USDC.b) and mint shares to `receiver`.
    //  * @dev Protects against first‑mover inflation, external “gift‑grief” TVL
    //  *      manipulation, and fairly splits the upfront management fee.
    //  */
    // function deposit2(uint256 assets, address receiver)
    //     public override returns (uint256 sharesOut)
    // {
    //     require(assets != 0, "zero assets");

    //     uint256 supplyBefore = totalSupply();
    //     uint256 tvlBefore    = totalAssets();

    //     /* ── 1.  seed‑size guard – ensure first real deposit is meaningful ── */
    //     if (supplyBefore <= 1e3) {
    //         // require ≥ 1 USDC (1e6) after the 1k seed‑shares minted in constructor
    //         require(assets >= 1e6, "seed too small");
    //     }

    //     /* ── 2.  pull funds in – from now on `assets` is in the vault ─────── */
    //     IERC20(USDCb).safeTransferFrom(msg.sender, address(this), assets);

    //     /* ── 3.  gift‑grief guard – nobody may donate extra TVL before mint ─ */
    //     uint256 tvlAfterPull = totalAssets();
    //     // allow +1 wei slack for rounding errors on interest‑bearing tokens, etc.
    //     require(tvlAfterPull <= tvlBefore + assets + 1, "external donation");

    //     /* ── 4.  fee split (80 % dev / 20 % WRK) ──────────────────────────── */
    //     uint256 feeAssets  = (assets * mgmtFeeBps) / 10_000;
    //     uint256 netAssets  = assets - feeAssets;

    //     /* ── 5.  calculate shares using *pre‑mint* supply / TVL ───────────── */
    //     uint256 feeShares  = convertToShares(feeAssets);
    //     sharesOut          = convertToShares(netAssets);
    //     require(sharesOut != 0, "0 shares");

    //     if (feeShares != 0) {
    //         uint256 devPortion = (feeShares * 8_000) / 10_000; // 80 %
    //         _mint(devWallet,  devPortion);
    //         _mint(wrkRewards, feeShares - devPortion);         // 20 %
    //     }

    //     /* ── 6.  mint depositor shares ───────────────────────────────────── */
    //     _mint(receiver, sharesOut);

    //     /* ── 7.  optional auto‑rebalance & state snapshot ─────────────────── */
    //     _maybeAutoRebalance();
    //     _emitState();
    // }


    /**
     * @notice Mint exactly `shares` vault shares to `receiver` by depositing assets
     * @param shares Amount of shares to mint
     * @param receiver Address to receive shares
     * @return assets Amount of assets deposited
     */
    function mint(uint256 shares, address receiver) 
        public override returns (uint256 assets) 
    {
        assets = previewMint(shares);
        
        IERC20(USDCb).safeTransferFrom(msg.sender, address(this), assets);
        
        // Calculate fee
        uint256 fee = (assets * mgmtFeeBps) / 10_000;
        
        // Mint fee shares
        uint256 feeShares = convertToShares(fee);
        _mint(devWallet, (feeShares * 8_000) / 10_000);
        _mint(wrkRewards, feeShares - (feeShares * 8_000) / 10_000);
        
        // Mint requested shares to receiver
        _mint(receiver, shares);
        
        _maybeAutoRebalance();
        _emitState();
    }

    /*//////////////////////////////////////////////////////////////
                             WITHDRAW BASKET
    //////////////////////////////////////////////////////////////*/
    function withdraw(uint256 shares, address receiver, address owner)
        public override returns (uint256 assetsUsd)
    {
        if (owner != msg.sender) _spendAllowance(owner, msg.sender, shares);

        assetsUsd = convertToAssets(shares);
        _burn(owner, shares);

        for (uint i; i < allowedAssets.length; ++i) {
            uint256 usd = (assetsUsd * targetWeights[i]) / 1e4;
            _payout(receiver, allowedAssets[i], usd);
        }

        _maybeAutoRebalance();
        _emitState();
    }

    /**
     * @notice Redeem shares for assets, credits assets to receiver
     * @param shares Amount of shares to redeem
     * @param receiver Address to receive assets
     * @param owner Owner of the shares
     * @return assets Amount of assets redeemed
     */
    function redeem(uint256 shares, address receiver, address owner)
        public override returns (uint256 assets)
    {
        return withdraw(shares, receiver, owner);
    }

    /*//////////////////////////////////////////////////////////////
                      SINGLE‑ASSET WITHDRAW (via adapter)
    //////////////////////////////////////////////////////////////*/
    function withdrawSingle(
        uint256 shares,
        address tokenOut,
        uint256 minOut,
        bytes calldata swapData,
        address receiver
    ) external override returns (uint256 amountOut) {
        require(_isAllowed(tokenOut), "!allowed");
        if (msg.sender != receiver) _spendAllowance(msg.sender, msg.sender, shares);
        _burn(msg.sender, shares);

        if (swapData.length != 0) require(adapter.execute(swapData), "swap fail");

        amountOut = _balanceOf(tokenOut);
        require(amountOut >= minOut, "slip");
        _transferAsset(tokenOut, receiver, amountOut);

        _maybeAutoRebalance();
        _emitState();
    }

    /*//////////////////////////////////////////////////////////////
                          MANAGER‑ONLY FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function setWeights(uint256[] calldata w) public override onlyOwner {
        _setWeights(w);
        if (_needsRebalance()) emit NeedsRebalance(stateId, block.timestamp);
        _emitState();
    }

    function setDevWallet(address d) external override onlyOwner {
        require(d != address(0), "0addr");
        devWallet = d;
        _emitState();
    }

    function setAutoRebalanceEnabled(bool enabled) external onlyOwner {
        autoRebalanceEnabled = enabled;
        _emitState();
    }

    function rebalance() external override onlyOwner {
        _rebalance();
        _emitState();
    }

    function setWeightsAndRebalance(uint256[] calldata w) external override onlyOwner {
        _setWeights(w);
        _rebalance();
        _emitState();
    }

    /*//////////////////////////////////////////////////////////////
                         INTERNAL REBALANCE LOGIC
    //////////////////////////////////////////////////////////////*/
    function _maybeAutoRebalance() internal {
        if (!autoRebalanceEnabled) {
            if (_needsRebalance()) emit NeedsRebalance(stateId, block.timestamp);
            return;
        }
        if (_needsRebalance()) _rebalance(); else emit AutoRebalanceSkipped("Within band", block.timestamp);
    }

    function _rebalance() internal {
        uint256 tvl = totalAssets();
        if (tvl == 0) { emit AutoRebalanceSkipped("Zero TVL", block.timestamp); return; }

        bool anySwap;
        // ---- SELL overweight ----
        for (uint i; i < allowedAssets.length; ++i) {
            IERC20 token = allowedAssets[i];
            if (address(token) == USDCb) continue;
            uint256 cur = _getAssetValue(token);
            uint256 tar = (tvl * targetWeights[i]) / 1e4;
            if (cur <= tar + (tar * DEVIATION_BPS) / 10_000) continue;
            uint256 excessUsd = cur - tar;
            uint256 amountIn = (excessUsd * 1e18) / oracle.usdPrice(address(token));
            if (amountIn == 0) continue;
            bytes memory data = abi.encode(address(token), USDCb, amountIn, AUTO_SLIPPAGE_BPS);
            require(adapter.execute(data), "sell");
            anySwap = true;
        }

        // refresh tvl and usdc balance
        if (anySwap) tvl = totalAssets();
        uint256 usdcBal = IERC20(USDCb).balanceOf(address(this));
        if (usdcBal == 0) { emit AutoRebalanceSkipped("No USDC", block.timestamp); return; }

        // ---- BUY underweight ----
        for (uint i; i < allowedAssets.length && usdcBal != 0; ++i) {
            IERC20 token = allowedAssets[i];
            if (address(token) == USDCb) continue;
            uint256 cur = _getAssetValue(token);
            uint256 tar = (tvl * targetWeights[i]) / 1e4;
            if (tar <= cur + (tar * DEVIATION_BPS) / 10_000) continue;
            uint256 deficitUsd = tar - cur;
            if (deficitUsd > usdcBal) deficitUsd = usdcBal;
            if (deficitUsd == 0) continue;
            bytes memory data = abi.encode(USDCb, address(token), deficitUsd, AUTO_SLIPPAGE_BPS);
            require(adapter.execute(data), "buy");
            usdcBal -= deficitUsd;
        }

        emit AutoRebalanceExecuted(tvl, block.timestamp);
    }

    /*//////////////////////////////////////////////////////////////
                              INTERNAL HELPERS
    //////////////////////////////////////////////////////////////*/
    function _setWeights(uint256[] calldata w) internal {
        require(w.length == allowedAssets.length, "len");
        uint256 sum;
        for (uint i; i < w.length; ++i) sum += w[i];
        require(sum == 1e4, "!=10000");
        targetWeights = w;
    }

    function _needsRebalance() internal view returns (bool) {
        uint256 tvl = totalAssets();
        if (tvl == 0) return false;
        for (uint i; i < allowedAssets.length; ++i) {
            uint256 cur = _getAssetValue(allowedAssets[i]);
            uint256 tar = (tvl * targetWeights[i]) / 1e4;
            uint256 diff = cur > tar ? cur - tar : tar - cur;
            if (diff * 10_000 > tar * DEVIATION_BPS) return true;
        }
        return false;
    }

    function _getAssetValue(IERC20 t) internal view returns (uint256 usd) {
        address a = address(t);
        if (a == BASE_ETH) {
            usd = address(this).balance * oracle.usdPrice(BASE_ETH) / 1e18;
        } else if (a == USDCb) {
            usd = t.balanceOf(address(this));
        } else {
            uint256 bal = t.balanceOf(address(this));
            usd = bal * oracle.usdPrice(a) / 1e18;
        }
    }

    function _approveTokens() internal {
        for (uint i; i < allowedAssets.length; ++i) allowedAssets[i].approve(address(adapter), type(uint256).max);
        IERC20(USDCb).approve(address(adapter), type(uint256).max);
    }

    function _emitState() internal {
        uint256 tvl = totalAssets();
        uint256 px  = totalSupply() == 0 ? 1e18 : (tvl * 1e18) / totalSupply();
        emit VaultState(++stateId, block.timestamp, tvl, px, targetWeights, devWallet);
    }

    /*------------------------------------------------------------*/
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
    function _isAllowed(address tok) internal view returns (bool ok) {
        if (tok == USDCb || tok == BASE_ETH) return true;
        for (uint i; i < allowedAssets.length; ++i) if (address(allowedAssets[i]) == tok) return true;
    }

    function _payout(address to, IERC20 token, uint256 usd) internal {
        address a = address(token);
        uint256 amt = a == USDCb ? usd : (usd * 1e18) / oracle.usdPrice(a);
        if (amt == 0) return;
        token.safeTransfer(to, amt);
    }

    /*//////////////////////////////////////////////////////////////
                              SUBGRAPH SNAPSHOT
    //////////////////////////////////////////////////////////////*/
    function VaultSnapshot()
        external view override
        returns (
            uint256 timestamp,
            uint256 tvlUsd,
            uint256 totalShares,
            uint256 sharePrice,
            address[] memory assets,
            uint256[] memory assetBalances,
            uint256[] memory assetValuesUsd,
            uint256[] memory weights
        )
    {
        uint256 _tvl = totalAssets();
        uint256 _shares = totalSupply();
        uint256 _px = _shares == 0 ? 1e18 : (_tvl * 1e18) / _shares;
        uint n = allowedAssets.length;
        address[] memory addrs = new address[](n);
        uint256[] memory bals  = new uint256[](n);
        uint256[] memory vals  = new uint256[](n);
        for (uint i; i < n; ++i) {
            IERC20 tok = allowedAssets[i];
   
            addrs[i] = address(tok);
            bals[i]  = tok.balanceOf(address(this));
            vals[i]  = _getAssetValue(tok);
        }
        return (block.timestamp, _tvl, _shares, _px, addrs, bals, vals, targetWeights);
    }

    /*//////////////////////////////////////////////////////////////
                                  RECEIVE
    //////////////////////////////////////////////////////////////*/
    receive() external payable {}
}