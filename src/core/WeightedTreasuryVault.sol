// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC4626 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { ISwapAdapter } from "./interfaces/ISwapAdapter.sol";
import { IPriceOracle } from "./interfaces/IPriceOracle.sol";

contract WeightedTreasuryVault is ERC4626 {
    using SafeERC20 for IERC20;

    /*══════════════ IMMUTABLE CONFIG ══════════════*/
    address public constant BASE_ETH = address(0);
    address public immutable USDCb;
    
    ISwapAdapter public immutable adapter;
    IPriceOracle public immutable oracle;
    address public immutable manager;
    address public immutable wrkRewards;
    uint16  public immutable mgmtFeeBps;         // e.g. 200 = 2 %

    /*══════════════     STATE      ══════════════*/
    IERC20[] public allowedAssets;               // max 8
    uint256[] public targetWeights;              // 1e4 bps
    address   public devWallet;
    uint256   private stateId;                   // increments each _emitState

    /*────────────── EVENTS ─────────────*/
    event VaultState(
        uint256 indexed stateId,
        uint256 timestamp,
        uint256 tvlUsd,
        uint256 sharePrice,
        uint256[] weights,
        address devWallet
    );

    /*────────────── MODIFIER ───────────*/
    modifier onlyM() { require(msg.sender == manager, "not manager"); _; }

    /*────────────── CONSTRUCTOR ────────*/
    constructor(
        string   memory name_,
        string   memory sym_,
        address  _usdcb,
        IERC20[] memory _allowed,
        uint256[] memory _weights,
        address  _manager,
        ISwapAdapter _adapter,
        IPriceOracle _oracle,
        uint16   _mgmtFeeBps,
        address  _devWallet,
        address  _wrkRewards
    )
        ERC4626(IERC20(_usdcb))
        ERC20(name_, sym_)
    {
        require(_mgmtFeeBps <= 1_000, "fee>10%");
        require(_allowed.length == _weights.length && _weights.length <= 8, "len");
        uint256 sum; for (uint i; i<_weights.length; ++i) sum += _weights[i];
        require(sum == 1e4, "weights");

        USDCb         = _usdcb;
        allowedAssets = _allowed;
        targetWeights = _weights;
        manager       = _manager;
        adapter       = _adapter;
        oracle        = _oracle;
        mgmtFeeBps    = _mgmtFeeBps;
        devWallet     = _devWallet;
        wrkRewards    = _wrkRewards;

        _approveTokens();
        _emitState();         // id 0
    }

    /*────────  4626 OVERRIDES  ────────*/
    function totalAssets() public view override returns (uint256 usd) {
        // ETH
        usd += address(this).balance * oracle.usdPrice(BASE_ETH) / 1e18;
        // USDCb
        usd += IERC20(USDCb).balanceOf(address(this));
        // Other tokens
        for (uint i; i<allowedAssets.length; ++i) {
            address tok = address(allowedAssets[i]);
            if (tok == USDCb) continue;
            uint256 bal = allowedAssets[i].balanceOf(address(this));
            usd += bal * oracle.usdPrice(tok) / 1e18;
        }
    }

    /*──────────── DEPOSIT (fee) ───────*/
    function deposit(uint256 assets, address receiver)
        public override returns (uint256 sharesOut)
    {
        uint256 gross = previewDeposit(assets);
        uint256 fee   = gross * mgmtFeeBps / 10_000;
        uint256 dev   = fee * 8_000 / 10_000;
        uint256 wrk   = fee - dev;

        _mint(devWallet,  dev);
        _mint(wrkRewards, wrk);
        _mint(receiver,   gross - fee);
        sharesOut = gross - fee;

        // Accept USDC.b
        IERC20(USDCb).safeTransferFrom(msg.sender, address(this), assets);

        _checkAndRebalance();
        _emitState();
    }

    /**
     * @dev Deposit ETH into the vault
     * @param receiver Address to receive shares
     * @return sharesOut Amount of shares minted
     */
    function depositETH(address receiver) 
        public payable returns (uint256 sharesOut) 
    {
        // Calculate ETH value in USD
        uint256 assets = msg.value * oracle.usdPrice(BASE_ETH) / 1e18;
        require(assets > 0, "insufficient ETH");

        uint256 gross = previewDeposit(assets);
        uint256 fee   = gross * mgmtFeeBps / 10_000;
        uint256 dev   = fee * 8_000 / 10_000;
        uint256 wrk   = fee - dev;

        _mint(devWallet,  dev);
        _mint(wrkRewards, wrk);
        _mint(receiver,   gross - fee);
        sharesOut = gross - fee;

        _checkAndRebalance();
        _emitState();
    }

    /*──────────── WITHDRAW ────────────*/
    function withdraw(uint256 shares, address receiver, address owner)
        public override returns (uint256 assetsUsd)
    {
        if (owner != msg.sender)
            _spendAllowance(owner, msg.sender, shares);

        assetsUsd = convertToAssets(shares);
        _burn(owner, shares);

        for (uint i; i<allowedAssets.length; ++i) {
            uint256 usdPortion = assetsUsd * targetWeights[i] / 1e4;
            address tok = address(allowedAssets[i]);
            if (tok == BASE_ETH) {
                uint256 ethAmt = usdPortion * 1e18 / oracle.usdPrice(BASE_ETH);
                (bool ok,) = receiver.call{value: ethAmt}("");
                require(ok, "eth send");
            } else {
                uint256 amt = (tok == USDCb)
                    ? usdPortion
                    : usdPortion * 1e18 / oracle.usdPrice(tok);
                allowedAssets[i].safeTransfer(receiver, amt);
            }
        }
        _emitState();
    }

    /*──────────── MANAGER OPS ─────────*/
    function setWeights(uint256[] calldata w) external onlyM {
        require(w.length == allowedAssets.length, "len");
        uint s; for(uint i;i<w.length;++i) s+=w[i];
        require(s == 1e4, "sum");
        targetWeights = w;
        _emitState();
    }

    function setDevWallet(address newDev) external onlyM {
        devWallet = newDev;
        _emitState();
    }

    function rebalance(bytes calldata data) external onlyM {
        bool ok = adapter.execute(data);
        require(ok, "swap fail");
        _emitState();
    }

    /*────────── INTERNAL HELPERS ──────*/
    function _checkAndRebalance() view internal {
        uint256 tvl = totalAssets();
        if (tvl == 0) return;

        // Check if any asset deviates more than 5% from target weight
        for (uint i; i < allowedAssets.length; ++i) {
            uint256 currentValue = _getAssetValue(allowedAssets[i]);
            uint256 targetValue = tvl * targetWeights[i] / 1e4;
            uint256 deviation = currentValue > targetValue 
                ? currentValue - targetValue 
                : targetValue - currentValue;
            
            if (deviation * 100 / targetValue > 5) {
                // Trigger rebalance if deviation > 5%
                return;
            }
        }
    }

    function _getAssetValue(IERC20 token) internal view returns (uint256) {
        address tok = address(token);
        if (tok == BASE_ETH) {
            return address(this).balance * oracle.usdPrice(BASE_ETH) / 1e18;
        }
        uint256 bal = token.balanceOf(address(this));
        return tok == USDCb ? bal : bal * oracle.usdPrice(tok) / 1e18;
    }

    function _approveTokens() internal {
        for (uint i; i<allowedAssets.length; ++i)
            allowedAssets[i].approve(address(adapter), type(uint).max);
    }

    function _emitState() internal {
        uint256 tvlUsd = totalAssets();
        uint256 price  = totalSupply()==0
            ? 1e18
            : tvlUsd * 1e18 / totalSupply();
        emit VaultState(++stateId, block.timestamp, tvlUsd, price, targetWeights, devWallet);
    }

    receive() external payable {}
}
