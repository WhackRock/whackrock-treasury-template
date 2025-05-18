// SPDX-License-Identifier: BUSL-1.1
// Copyright (C) 2024 WhackRock Labs. All rights reserved.
pragma solidity ^0.8.20;

import "../interfaces/IPriceOracle.sol";
import "../interfaces/IUniTwapOracle.sol";
import "../interfaces/IUniswapV2Pair.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/**
 * @title UniTwapDualOracle
 * @notice Returns USD prices using Uniswap V3 AND V2 pools.
 *         Supports direct token/USDC.b pools OR token/WETH + WETH/USDC.b.
 *
 *         • V3: 30‑minute arithmetic mean tick (robust to flash loans)
 *         • V2: Spot price from reserves
 *         • Token decimals read dynamically from token contracts
 *         • WETH address & WETH/USDC.b pool injected at deploy
 */
contract UniTwapDualOracle is IUniTwapOracle {
    uint32 public constant override TWAP_SEC = 1_800;           // 30 min
    address public immutable override USDCb;                    // bridged USDC
    address public immutable override WETH;
    address public immutable override wethUsdcPool;             // WETH/USDC V3 pool
    
    // Maps token address to pool configuration
    mapping(address => PoolConfig) public pools;
    
    constructor(
        address _usdc,
        address _weth,
        address _wethUsdcPool
    ) {
        USDCb = _usdc;
        WETH = _weth;
        wethUsdcPool = _wethUsdcPool;
    }
    
    /**
     * @notice Set a token's price pool configuration
     * @param token Token address to configure
     * @param poolAddress Address of Uniswap pool (V2 or V3)
     * @param viaWeth Whether price should be calculated via WETH
     * @param isV2 Whether the pool is Uniswap V2 (true) or V3 (false)
     */
    function setPoolConfig(
        address token,
        address poolAddress,
        bool viaWeth,
        bool isV2
    ) external override {
        PoolType poolType = isV2 ? PoolType.V2 : PoolType.V3;
        pools[token] = PoolConfig(poolAddress, viaWeth, poolType);
        emit PoolConfigSet(token, poolAddress, viaWeth, poolType);
    }
    
    /**
     * @notice Configure multiple tokens at once
     * @param tokens Array of token addresses
     * @param poolAddresses Array of pool addresses
     * @param viaWeth Array of flags for WETH calculation
     * @param isV2 Array of flags for V2/V3 selection
     */
    function batchSetPoolConfig(
        address[] calldata tokens,
        address[] calldata poolAddresses,
        bool[] calldata viaWeth,
        bool[] calldata isV2
    ) external override {
        require(tokens.length == poolAddresses.length, "Length mismatch");
        require(tokens.length == viaWeth.length, "Length mismatch");
        require(tokens.length == isV2.length, "Length mismatch");
        
        for (uint256 i = 0; i < tokens.length; i++) {
            PoolType poolType = isV2[i] ? PoolType.V2 : PoolType.V3;
            pools[tokens[i]] = PoolConfig(poolAddresses[i], viaWeth[i], poolType);
            emit PoolConfigSet(tokens[i], poolAddresses[i], viaWeth[i], poolType);
        }
    }
    
    /**
     * @notice Get USD price for a token
     * @param token ERC-20 address
     * @return priceUsd1e18 USD price * 1e18
     */
    function usdPrice(address token) 
        external view override
        returns (uint256 priceUsd1e18) 
    {
        // Special case: USDC is always $1
        if (token == USDCb) return 1e18;
        
        // Special case: WETH price from WETH/USDC pool
        if (token == WETH) {
            return getV3Price(IUniswapV3Pool(wethUsdcPool), false);
        }
        
        // Get token's pool configuration
        PoolConfig memory config = pools[token];
        require(config.poolAddress != address(0), "Pool not configured");
        
        // Calculate price based on pool type
        if (config.poolType == PoolType.V2) {
            return getV2Price(IUniswapV2Pair(config.poolAddress), config.viaWeth);
        } else {
            return getV3Price(IUniswapV3Pool(config.poolAddress), config.viaWeth);
        }
    }
    
    /*────────────────────── INTERNAL FUNCTIONS ────────────────────*/
    
    /**
     * @dev Calculate USD price using a Uniswap V2 pool
     * @param pool Uniswap V2 pool
     * @param viaWeth Whether to calculate via WETH
     * @return Price in USD with 18 decimals
     */
    function getV2Price(IUniswapV2Pair pool, bool viaWeth) 
        internal view 
        returns (uint256) 
    {
        address token0 = pool.token0();
        address token1 = pool.token1();
        
        // Get token decimals
        uint8 decimals0 = IERC20Metadata(token0).decimals();
        uint8 decimals1 = IERC20Metadata(token1).decimals();
        
        // Get pool reserves
        (uint112 reserve0, uint112 reserve1, ) = pool.getReserves();
        require(reserve0 > 0 && reserve1 > 0, "Insufficient liquidity");
        
        uint256 price;
        
        // Calculate price based on decimal differences
        if (decimals0 == decimals1) {
            price = (reserve1 * 1e18) / reserve0;
        } else {
            // Adjust for decimal differences
            uint256 decimalAdjustment = 10 ** uint256(
                decimals0 > decimals1 
                    ? decimals0 - decimals1 
                    : decimals1 - decimals0
            );
            
            if (decimals0 > decimals1) {
                price = (reserve1 * 1e18 * decimalAdjustment) / reserve0;
            } else {
                price = (reserve1 * 1e18) / (reserve0 * decimalAdjustment);
            }
        }
        
        // Direct USDC pricing
        if (token0 == USDCb || token1 == USDCb) {
            address baseToken = (token0 == USDCb) ? token1 : token0;
            uint8 baseDecimals = IERC20Metadata(baseToken).decimals();
            
            // If USDC is token0, we need to invert the price
            if (token0 == USDCb) {
                // Calculate baseToken/USDC price
                price = (reserve0 * 1e18) / reserve1;
                
                // Adjust for decimal differences
                if (decimals0 != decimals1) {
                    uint256 decimalAdjustment = 10 ** uint256(
                        decimals0 > decimals1 
                            ? decimals0 - decimals1 
                            : decimals1 - decimals0
                    );
                    
                    if (decimals0 > decimals1) {
                        price = price * decimalAdjustment;
                    } else {
                        price = price / decimalAdjustment;
                    }
                }
                
                // Invert to get USDC/baseToken
                price = (1e36 / price);
            }
            
            // Standardize to 18 decimals
            uint256 decimalAdjustment_ = 10 ** (18 - baseDecimals);
            return price * decimalAdjustment_;
        }
        
        // If price should be calculated via WETH
        if (viaWeth) {
            uint256 wethUsdPrice = getV3Price(IUniswapV3Pool(wethUsdcPool), false);
            return (price * wethUsdPrice) / 1e18;
        }
        
        return price;
    }
    
    /**
     * @dev Calculate USD price using a Uniswap V3 pool
     * @param pool Uniswap V3 pool
     * @param viaWeth Whether to calculate via WETH
     * @return Price in USD with 18 decimals
     */
    function getV3Price(IUniswapV3Pool pool, bool viaWeth) 
        internal view 
        returns (uint256) 
    {
        // Get TWAP tick
        int24 tick = calculateTWAP(pool);
        
        // Calculate price from tick
        uint256 sqrtPriceX96 = TickMath.getSqrtRatioAtTick(tick);
        uint256 priceX192 = uint256(sqrtPriceX96) * uint256(sqrtPriceX96);
        
        address token0 = pool.token0();
        address token1 = pool.token1();
        
        // Get token decimals
        uint8 decimals0 = IERC20Metadata(token0).decimals();
        uint8 decimals1 = IERC20Metadata(token1).decimals();
        
        // Calculate raw price
        uint256 price = priceX192 * 1e18 / (1 << 192);
        
        // Apply decimal adjustments
        if (decimals0 != decimals1) {
            uint256 decimalAdjustment = 10 ** uint256(
                decimals0 > decimals1 
                    ? decimals0 - decimals1 
                    : decimals1 - decimals0
            );
            
            if (decimals0 > decimals1) {
                price = price * decimalAdjustment;
            } else {
                price = price / decimalAdjustment;
            }
        }
        
        // Direct USDC pricing
        if (token0 == USDCb || token1 == USDCb) {
            address baseToken = (token0 == USDCb) ? token1 : token0;
            uint8 baseDecimals = IERC20Metadata(baseToken).decimals();
            
            // Standardize to 18 decimals
            uint256 decimalAdjustment = 10 ** (18 - baseDecimals);
            return price * decimalAdjustment;
        }
        
        // If price should be calculated via WETH
        if (viaWeth) {
            uint256 wethUsdPrice = getV3Price(IUniswapV3Pool(wethUsdcPool), false);
            return (price * wethUsdPrice) / 1e18;
        }
        
        return price;
    }
    
    /**
     * @dev Calculate time-weighted average tick from Uniswap V3 pool
     * @param pool Uniswap V3 pool
     * @return Average tick over TWAP period
     */
    function calculateTWAP(IUniswapV3Pool pool) 
        internal view 
        returns (int24) 
    {
        uint32[] memory secondsAgos = new uint32[](2);
        secondsAgos[0] = 0;
        secondsAgos[1] = TWAP_SEC;
        
        (int56[] memory tickCumulatives, ) = pool.observe(secondsAgos);
        
        int56 tickCumulativesDelta = tickCumulatives[0] - tickCumulatives[1];
        int24 timeWeightedAverageTick = int24(tickCumulativesDelta / int32(TWAP_SEC));
        
        return timeWeightedAverageTick;
    }

    function getPoolConfig(address token) external view override returns (PoolConfig memory){
        return pools[token];
    }
} 