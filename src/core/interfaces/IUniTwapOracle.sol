// SPDX-License-Identifier: BUSL-1.1
// Copyright (C) 2024 WhackRock Labs. All rights reserved.
pragma solidity ^0.8.20;

import { IPriceOracle } from "./IPriceOracle.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

/**
 * @title IUniTwapOracle
 * @notice Interface for UniTwapOracle that provides USD prices using Uniswap V3 pools.
 *         Supports direct token/USDC.b pools OR token/WETH + WETH/USDC.b.
 */
interface IUniTwapOracle is IPriceOracle {
    /**
     * @notice Time window for TWAP calculation in seconds
     * @return Time window in seconds (e.g., 1800 for 30 minutes)
     */
    function TWAP_SEC() external view returns (uint32);
    
    /**
     * @notice Address of the USDC.b token
     * @return Address of USDC.b token
     */
    function USDCb() external view returns (address);
    
    /**
     * @notice Address of the WETH token
     * @return Address of WETH token
     */
    function WETH() external view returns (address);
    
    /**
     * @notice The Uniswap V3 pool used for WETH/USDC.b price reference
     * @return Address of the WETH/USDC.b pool
     */
    function wethUsdcPool() external view returns (IUniswapV3Pool);
    
    /**
     * @notice Retrieves the pool configuration for a specific token
     * @param token Address of the token
     * @return pool The Uniswap V3 pool used for pricing
     * @return viaWeth Whether price is calculated via WETH
     */
    function pair(address token) external view returns (IUniswapV3Pool pool, bool viaWeth);
    
    /**
     * @notice Set a token-pool pair for price lookups
     * @param token Token address to configure
     * @param pool Uniswap V3 pool address to use for pricing
     * @param viaWeth Whether to calculate price via WETH (true) or directly (false)
     */
    function setPair(
        address token,
        address pool,
        bool viaWeth
    ) external;
    
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
    ) external;
    
    /**
     * @notice Get USD price for a token (inherited from IPriceOracle)
     * @param token ERC-20 address
     * @return priceUsd1e18 USD price * 1e18
     * Special cases:
     * - If token is USDC.b, returns 1e18 ($1)
     * - If token is WETH, uses the WETH/USDC.b pool directly
     * - Otherwise uses the pool configured in the pair mapping
     */
    function usdPrice(address token) external view override returns (uint256 priceUsd1e18);
} 