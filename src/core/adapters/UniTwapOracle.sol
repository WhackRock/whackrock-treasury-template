// SPDX‑License‑Identifier: MIT
pragma solidity ^0.8.20;

import { IPriceOracle } from "../interfaces/IPriceOracle.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-core/contracts/libraries/TickMath.sol";

/**
 * @title UniTwapOracle
 * @notice Returns USD prices using Uniswap V3 pools only.
 *         Supports direct token/USDC.b pools OR token/WETH + WETH/USDC.b.
 *
 *         • 30‑minute arithmetic mean tick (robust to flash loans)
 *         • USDC.b assumed to have 6 decimals
 *         • WETH address & WETH/USDC.b pool injected at deploy
 */
contract UniTwapOracle is IPriceOracle {
    uint32  public constant TWAP_SEC = 1_800;           // 30 min
    address public immutable USDCb;                     // 6‑dec bridged USDC
    address public immutable WETH;
    IUniswapV3Pool public wethUsdcPool;

    struct Pair { IUniswapV3Pool pool; bool viaWeth; }  // token→QUOTE
    mapping(address => Pair) public pair;

    constructor(
        address _usdc,
        address _weth,
        address _wethUsdcPool
    ) {
        USDCb        = _usdc;
        WETH         = _weth;
        wethUsdcPool = IUniswapV3Pool(_wethUsdcPool);
    }

    
    function setPair(
        address token,
        address pool,
        bool viaWeth
    ) external {
        pair[token] = Pair(IUniswapV3Pool(pool), viaWeth);
    }
    
    /**
     * @notice Batch set multiple token/pool pairs at once
     * @param tokens Array of token addresses
     * @param pools Array of corresponding pool addresses
     * @param viaWeth Array of flags indicating if price should be calculated via WETH
     */
    function setPairs(
        address[] calldata tokens,
        address[] calldata pools,
        bool[] calldata viaWeth
    ) external {
        require(tokens.length == pools.length, "length mismatch");
        require(tokens.length == viaWeth.length, "length mismatch");
        
        for (uint256 i = 0; i < tokens.length; i++) {
            pair[tokens[i]] = Pair(IUniswapV3Pool(pools[i]), viaWeth[i]);
        }
    }

    /*───────────────────────── IPriceOracle ─────────────────────────*/

    /// @inheritdoc IPriceOracle
    function usdPrice(address token)
        external view override
        returns (uint256 priceUsd1e18)
    {
        if (token == USDCb) return 1e18;                 // 1 USDC = $1
        if (token == WETH)  return _twapUsd(wethUsdcPool, true);

        Pair memory p = pair[token];
        require(address(p.pool) != address(0), "unmapped token");

        uint256 quote = _twapUsd(p.pool, p.viaWeth);
        return quote;
    }

    /*───────────────────────── INTERNAL LIB ────────────────────────*/

    /// @dev Returns USD price for {pool.token0 ↔ pool.token1}
    function _twapUsd(IUniswapV3Pool pool, bool viaWeth)
        internal view returns (uint256)
    {
        int24 tick = _meanTick(pool);
        uint256 px96 = TickMath.getSqrtRatioAtTick(tick);
        uint256 priceX192 = uint256(px96) * uint256(px96);     // Q192

        // token0 / token1 price with 18‑dec scaling adjustment
        uint256 price1e18 = priceX192 * 1e18 / (1 << 192);

        // Adjust decimals if the quote token is USDC (6 dec)
        if (pool.token1() == USDCb || pool.token0() == USDCb) {
            price1e18 = price1e18 * 1e12;                      // 6 → 18
        }

        if (!viaWeth) return price1e18;

        // token priced in WETH; multiply by WETH/USD
        uint256 wethUsd = _twapUsd(wethUsdcPool, false);
        return price1e18 * wethUsd / 1e18;
    }

    function _meanTick(IUniswapV3Pool pool) internal view returns (int24) {
        uint32[] memory secs = new uint32[](2);
        secs[0] = 0; 
        secs[1] = TWAP_SEC;
        (int56[] memory cumul,) = pool.observe(secs);
        int56 diff = cumul[0] - cumul[1];
        return int24(diff / int32(TWAP_SEC));
    }
}
