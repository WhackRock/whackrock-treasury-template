// SPDX-License-Identifier: BUSL-1.1
// Copyright (C) 2024 WhackRock Labs. All rights reserved.
pragma solidity ^0.8.20;

/**
 * @title IUniswapV2Pair
 * @notice Interface for a Uniswap V2 pair contract.
 * @dev This interface includes only the functions needed for the UniTwapDualOracle.
 */
interface IUniswapV2Pair {
    /**
     * @notice Returns the address of the first token in the pair
     * @return Address of token0
     */
    function token0() external view returns (address);
    
    /**
     * @notice Returns the address of the second token in the pair
     * @return Address of token1
     */
    function token1() external view returns (address);
    
    /**
     * @notice Returns the current reserves of the pair tokens
     * @return reserve0 The reserve amount of token0
     * @return reserve1 The reserve amount of token1
     * @return blockTimestampLast The timestamp of the last block in which reserves were updated
     */
    function getReserves() external view returns (
        uint112 reserve0,
        uint112 reserve1,
        uint32 blockTimestampLast
    );
} 