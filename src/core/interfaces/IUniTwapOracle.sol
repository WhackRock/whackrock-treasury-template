// SPDX-License-Identifier: BUSL-1.1
// Copyright (C) 2024 WhackRock Labs. All rights reserved.
pragma solidity ^0.8.20;

import { IPriceOracle } from "./IPriceOracle.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

/**
 * @title IUniTwapOracle
 * @notice Interface for UniTwapDualOracle that provides USD prices using Uniswap pools.
 *         Supports direct token/USDC.b pools OR token/WETH + WETH/USDC.b.
 *         Works with both Uniswap V2 and V3 pools.
 */
interface IUniTwapOracle is IPriceOracle {
    /**
     * @notice Pool types
     */
    enum PoolType { V2, V3 }
    
    /**
     * @notice Pool configuration
     */
    struct PoolConfig { 
        address poolAddress; 
        bool viaWeth;      // Whether to calculate price via WETH
        PoolType poolType; // V2 or V3
    }
    
    /**
     * @notice Time window for TWAP calculation in seconds (for V3 pools)
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
    function wethUsdcPool() external view returns (address);
    
    /**
     * @notice Retrieves the pool configuration for a specific token
     * @param token Address of the token
     * @return Pool configuration containing address, WETH routing flag and pool type
     */
    function getPoolConfig(address token) external view returns (PoolConfig memory);
    
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
    ) external;
    
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
    ) external;
    
    /**
     * @notice Get USD price for a token (inherited from IPriceOracle)
     * @param token ERC-20 address
     * @return priceUsd1e18 USD price * 1e18
     */
    // function usdPrice(address token) external view returns (uint256 priceUsd1e18);
    
    /**
     * @notice Pool configuration update event
     * @param token Token that was configured
     * @param pool Pool address that was set
     * @param viaWeth Whether price calculation is via WETH
     * @param poolType Type of pool (V2 or V3)
     */
    event PoolConfigSet(address indexed token, address indexed pool, bool viaWeth, PoolType poolType);
} 