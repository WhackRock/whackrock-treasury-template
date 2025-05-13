// SPDX‑License‑Identifier: BUSL‑1.1
pragma solidity ^0.8.25;

import { ERC20 }        from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC4626 }       from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import { ERC20Snapshot } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Snapshot.sol";
import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { ISwapAdapter } from "./adapters/ISwapAdapter.sol";
import { IPriceOracle } from "./adapters/IPriceOracle.sol";

/**
 * @title WeightedTreasuryVault
 * @dev  Generic N‑asset ERC‑4626 vault, now with:
 *       • up‑front management fee on every deposit
 *       • fee split 80 % → devWallet, 20 % → wrkRewards
 *       • NO perf fee, NO streaming fee, NO external splitter
 *
 *       Snapshot kept for verifiable performance series.
 */
contract WeightedTreasuryVault is ERC4626, ERC20Snapshot {
    using SafeERC20 for IERC20;

    /*═══════════════ IMMUTABLE CONFIG ═══════════════*/
    IERC20[]     public immutable assets;
    ISwapAdapter public immutable adapter;
    IPriceOracle public immutable oracle;
    address      public immutable manager;        // GAME Worker
    address      public immutable wrkRewards;     // gets 20 % of each fee
    uint16       public immutable mgmtFeeBps;     // e.g. 200 = 2 %

    /*═══════════════  STATE  ═══════════════════════*/
    uint256[] public targetWeights;               // 1e4 basis‑points
    address   public devWallet;                   // gets 80 % of each fee

    /*────────────── modifiers ─────────────*/
    modifier onlyM() { require(msg.sender == manager, "not manager"); _; }

    /*────────────── constructor ───────────*/
    constructor(
        string   memory name_,
        string   memory sym_,
        IERC20[] memory _assets,
        uint256[] memory _weights,
        address  _manager,
        ISwapAdapter _adapter,
        IPriceOracle _oracle,
        uint16   _mgmtFeeBps,            // 0‑1000 (10 % max)
        address  _devWallet,
        address  _wrkRewards
    )
        ERC20(name_, sym_)
        ERC4626(_assets[0])              // dummy “asset” for 4626
    {
        require(_assets.length == _weights.length && _assets.length <= 8, "len");
        require(_mgmtFeeBps <= 1_000, "fee>10%");
        uint256 sum; for (uint i; i<_weights.length; ++i) sum += _weights[i];
        require(sum == 1e4, "weights");

        assets        = _assets;
        targetWeights = _weights;
        manager       = _manager;
        adapter       = _adapter;
        oracle        = _oracle;
        mgmtFeeBps    = _mgmtFeeBps;
        devWallet     = _devWallet;
        wrkRewards    = _wrkRewards;

        _approveTokens();
        _snapshot();                     // snapshot id 1
    }

    /*────────────── 4626 overrides ─────────*/
    function totalAssets() public view override returns (uint256 usd) {
        for (uint i; i<assets.length; ++i)
            usd += oracle.usdPrice(address(assets[i]))
                 * assets[i].balanceOf(address(this)) / 1e18;
    }
    function convertToShares(uint256 assetsUsd, uint256)
        public view override returns (uint256)
    { return totalSupply()==0 ? assetsUsd : assetsUsd*totalSupply()/totalAssets(); }
    function convertToAssets(uint256 shares)
        public view override returns (uint256)
    { return shares*totalAssets()/totalSupply(); }

    /*────────────── DEPOSIT (fee taken here) ─────────*/
    function deposit(uint256 assetsUsd, address receiver)
        public override returns (uint256 sharesOut)
    {
        uint256 gross = convertToShares(assetsUsd, 0);
        uint256 fee   = gross * mgmtFeeBps / 10_000;
        uint256 dev   = fee * 8_000 / 10_000;
        uint256 wrk   = fee - dev;                     // 20 %

        _mint(devWallet,   dev);
        _mint(wrkRewards,  wrk);
        _mint(receiver,    gross - fee);
        sharesOut = gross - fee;

        for (uint i; i<assets.length; ++i) {
            uint256 want = assetsUsd * targetWeights[i] / 1e4;
            assets[i].safeTransferFrom(msg.sender, address(this), want);
        }
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

        for (uint i; i<assets.length; ++i) {
            uint256 give = assetsUsd * targetWeights[i] / 1e4;
            assets[i].safeTransfer(receiver, give);
        }
        _snapshot();
    }

    /*────────────── MANAGER OPS ─────────────────────*/
    function setWeights(uint256[] calldata w) external onlyM {
        require(w.length == assets.length, "len");
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

    /*────────────── helpers ────────────────────────*/
    function _approveTokens() internal {
        for (uint i; i<assets.length; ++i)
            assets[i].safeApprove(address(adapter), type(uint).max);
    }
}
