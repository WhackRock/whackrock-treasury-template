// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/**
 * @title UniswapV3TWAPOracle
 * @notice A TWAP (Time-Weighted Average Price) oracle using Uniswap V3 pools, optimized for WETH as base asset
 * @dev Provides price data by querying Uniswap V3 pool observations over a specified time period
 *      Optimized for WETH as the primary accounting asset
 */
contract UniswapV3TWAPOracle {
    error InvalidPool();
    error InvalidTWAPPeriod();
    error InsufficientObservations();
    error ZeroAmount();

    /// @notice Uniswap V3 Factory contract
    IUniswapV3Factory public immutable uniswapV3Factory;
    
    /// @notice Default TWAP period in seconds (15 minutes)
    uint32 public immutable defaultTWAPPeriod;
    
    /// @notice WETH address - the primary accounting asset
    address public immutable WETH;
    
    /// @notice Minimum TWAP period to prevent manipulation (5 minutes)
    uint32 public constant MIN_TWAP_PERIOD = 300;
    
    /// @notice Maximum TWAP period (24 hours)
    uint32 public constant MAX_TWAP_PERIOD = 86400;

    /**
     * @notice Creates a new UniswapV3TWAPOracle optimized for WETH
     * @param _uniswapV3Factory Address of the Uniswap V3 Factory
     * @param _defaultTWAPPeriod Default TWAP period in seconds
     * @param _weth Address of WETH token
     */
    constructor(address _uniswapV3Factory, uint32 _defaultTWAPPeriod, address _weth) {
        if (_uniswapV3Factory == address(0)) revert InvalidPool();
        if (_weth == address(0)) revert InvalidPool();
        if (_defaultTWAPPeriod < MIN_TWAP_PERIOD || _defaultTWAPPeriod > MAX_TWAP_PERIOD) {
            revert InvalidTWAPPeriod();
        }
        
        uniswapV3Factory = IUniswapV3Factory(_uniswapV3Factory);
        defaultTWAPPeriod = _defaultTWAPPeriod;
        WETH = _weth;
    }

    /**
     * @notice Gets the TWAP price of tokenIn in terms of tokenOut
     * @param tokenIn Address of the input token
     * @param tokenOut Address of the output token
     * @param amountIn Amount of input token
     * @param fee Pool fee tier (500, 3000, 10000)
     * @return amountOut Amount of output token equivalent to amountIn
     */
    function getTWAPPrice(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint24 fee
    ) external view returns (uint256 amountOut) {
        return getTWAPPriceWithPeriod(tokenIn, tokenOut, amountIn, fee, defaultTWAPPeriod);
    }

    /**
     * @notice Gets the TWAP price with a custom time period
     * @param tokenIn Address of the input token
     * @param tokenOut Address of the output token
     * @param amountIn Amount of input token
     * @param fee Pool fee tier (500, 3000, 10000)
     * @param twapPeriod TWAP period in seconds
     * @return amountOut Amount of output token equivalent to amountIn
     */
    function getTWAPPriceWithPeriod(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint24 fee,
        uint32 twapPeriod
    ) public view returns (uint256 amountOut) {
        if (amountIn == 0) return 0;
        if (twapPeriod < MIN_TWAP_PERIOD || twapPeriod > MAX_TWAP_PERIOD) {
            revert InvalidTWAPPeriod();
        }

        // Get the pool address
        address poolAddress = uniswapV3Factory.getPool(tokenIn, tokenOut, fee);
        if (poolAddress == address(0)) revert InvalidPool();

        IUniswapV3Pool pool = IUniswapV3Pool(poolAddress);

        // Check if pool has sufficient observations
        (, , , uint16 observationCardinality, , , ) = pool.slot0();
        if (observationCardinality == 0) revert InsufficientObservations();

        // Get TWAP tick
        (int24 arithmeticMeanTick, ) = _consult(poolAddress, twapPeriod);

        // Convert tick to price and calculate output amount
        amountOut = _getQuoteAtTick(
            arithmeticMeanTick,
            uint128(amountIn),
            tokenIn,
            tokenOut
        );

        return amountOut;
    }

    /**
     * @notice Gets the most liquid pool fee tier for a token pair
     * @param tokenA First token address
     * @param tokenB Second token address
     * @return fee The fee tier of the most liquid pool
     * @return poolAddress The address of the most liquid pool
     */
    function getMostLiquidPool(
        address tokenA,
        address tokenB
    ) external view returns (uint24 fee, address poolAddress) {
        uint24[3] memory fees = [uint24(500), uint24(3000), uint24(10000)];
        uint128 maxLiquidity = 0;
        uint24 bestFee = 0;
        address bestPool = address(0);

        for (uint256 i = 0; i < fees.length; i++) {
            address pool = uniswapV3Factory.getPool(tokenA, tokenB, fees[i]);
            if (pool != address(0)) {
                uint128 liquidity = IUniswapV3Pool(pool).liquidity();
                if (liquidity > maxLiquidity) {
                    maxLiquidity = liquidity;
                    bestFee = fees[i];
                    bestPool = pool;
                }
            }
        }

        if (bestPool == address(0)) revert InvalidPool();
        return (bestFee, bestPool);
    }

    /**
     * @notice Checks if a pool exists and has sufficient observations for TWAP
     * @param tokenA First token address
     * @param tokenB Second token address
     * @param fee Pool fee tier
     * @param requiredCardinality Minimum required observation cardinality
     * @return isValid True if pool is valid for TWAP
     */
    function isPoolValidForTWAP(
        address tokenA,
        address tokenB,
        uint24 fee,
        uint16 requiredCardinality
    ) external view returns (bool isValid) {
        address poolAddress = uniswapV3Factory.getPool(tokenA, tokenB, fee);
        if (poolAddress == address(0)) return false;

        IUniswapV3Pool pool = IUniswapV3Pool(poolAddress);
        (, , , uint16 observationCardinality, , , ) = pool.slot0();
        
        return observationCardinality >= requiredCardinality;
    }

    /**
     * @notice Gets the current spot price from a Uniswap V3 pool
     * @param tokenIn Address of the input token
     * @param tokenOut Address of the output token
     * @param amountIn Amount of input token
     * @param fee Pool fee tier
     * @return amountOut Current spot price amount
     */
    function getSpotPrice(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint24 fee
    ) external view returns (uint256 amountOut) {
        if (amountIn == 0) return 0;

        address poolAddress = uniswapV3Factory.getPool(tokenIn, tokenOut, fee);
        if (poolAddress == address(0)) revert InvalidPool();

        IUniswapV3Pool pool = IUniswapV3Pool(poolAddress);
        (uint160 sqrtPriceX96, , , , , , ) = pool.slot0();

        // Convert sqrtPriceX96 to tick for quote calculation
        int24 currentTick = _getTickFromSqrtRatio(sqrtPriceX96);

        amountOut = _getQuoteAtTick(
            currentTick,
            uint128(amountIn),
            tokenIn,
            tokenOut
        );

        return amountOut;
    }

    /**
     * @notice Gets the TWAP price of any token in WETH terms (optimized helper)
     * @param token Address of the token to price in WETH
     * @param amount Amount of token to convert to WETH
     * @param fee Pool fee tier (optional, uses default if 0)
     * @return wethAmount Amount of WETH equivalent
     */
    function getTokenValueInWETH(
        address token,
        uint256 amount,
        uint24 fee
    ) external view returns (uint256 wethAmount) {
        if (amount == 0) return 0;
        if (token == WETH) return amount; // Direct return for WETH
        
        uint24 poolFee = fee == 0 ? 3000 : fee; // Use 0.3% as default
        return getTWAPPriceWithPeriod(token, WETH, amount, poolFee, defaultTWAPPeriod);
    }

    /**
     * @notice Gets the TWAP price of WETH in terms of any token (optimized helper)
     * @param token Address of the token to receive
     * @param wethAmount Amount of WETH to convert
     * @param fee Pool fee tier (optional, uses default if 0)
     * @return tokenAmount Amount of token equivalent
     */
    function getWETHValueInToken(
        address token,
        uint256 wethAmount,
        uint24 fee
    ) external view returns (uint256 tokenAmount) {
        if (wethAmount == 0) return 0;
        if (token == WETH) return wethAmount; // Direct return for WETH
        
        uint24 poolFee = fee == 0 ? 3000 : fee; // Use 0.3% as default
        return getTWAPPriceWithPeriod(WETH, token, wethAmount, poolFee, defaultTWAPPeriod);
    }

    // Internal Oracle Library Functions (compatible with Solidity 0.8.20+)
    
    /**
     * @notice Consult the observation from secondsAgo to now for a given pool
     * @param pool Address of the pool to query
     * @param secondsAgo Number of seconds ago to start the observation from
     * @return arithmeticMeanTick The arithmetic mean tick over the specified period
     * @return harmonicMeanLiquidity The harmonic mean liquidity over the specified period
     */
    function _consult(address pool, uint32 secondsAgo)
        internal
        view
        returns (int24 arithmeticMeanTick, uint128 harmonicMeanLiquidity)
    {
        require(secondsAgo != 0, "BP");

        uint32[] memory secondsAgos = new uint32[](2);
        secondsAgos[0] = secondsAgo;
        secondsAgos[1] = 0;

        (int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityCumulativeX128s) =
            IUniswapV3Pool(pool).observe(secondsAgos);

        int56 tickCumulativesDelta = tickCumulatives[1] - tickCumulatives[0];
        uint160 secondsPerLiquidityCumulativesDelta =
            secondsPerLiquidityCumulativeX128s[1] - secondsPerLiquidityCumulativeX128s[0];

        arithmeticMeanTick = int24(tickCumulativesDelta / int56(uint56(secondsAgo)));
        // Always round to negative infinity
        if (tickCumulativesDelta < 0 && (tickCumulativesDelta % int56(uint56(secondsAgo)) != 0)) arithmeticMeanTick--;

        // We are multiplying here instead of shifting to ensure compilation in older versions of Solidity
        uint192 secondsAgoX160 = uint192(secondsAgo) * type(uint160).max;
        harmonicMeanLiquidity = uint128(secondsAgoX160 / (uint192(secondsPerLiquidityCumulativesDelta) << 32));
    }

    /**
     * @notice Given a tick and a token amount, calculates the amount of token received in exchange
     * @param tick Tick value used to calculate the quote
     * @param baseAmount Amount of token to be converted
     * @param baseToken Address of an ERC20 token contract used as the baseAmount denomination
     * @param quoteToken Address of an ERC20 token contract used as the quoteAmount denomination
     * @return quoteAmount Amount of quoteToken received for baseAmount of baseToken
     */
    function _getQuoteAtTick(
        int24 tick,
        uint128 baseAmount,
        address baseToken,
        address quoteToken
    ) internal pure returns (uint256 quoteAmount) {
        uint160 sqrtRatioX96 = _getSqrtRatioAtTick(tick);

        // Calculate quoteAmount with better precision if it doesn't overflow when multiplied by itself
        if (sqrtRatioX96 <= type(uint128).max) {
            uint256 ratioX192 = uint256(sqrtRatioX96) * sqrtRatioX96;
            quoteAmount = baseToken < quoteToken
                ? _mulDiv(ratioX192, baseAmount, 1 << 192)
                : _mulDiv(1 << 192, baseAmount, ratioX192);
        } else {
            uint256 ratioX128 = _mulDiv(sqrtRatioX96, sqrtRatioX96, 1 << 64);
            quoteAmount = baseToken < quoteToken
                ? _mulDiv(ratioX128, baseAmount, 1 << 128)
                : _mulDiv(1 << 128, baseAmount, ratioX128);
        }
    }

    /**
     * @notice Calculates sqrt(1.0001^tick) * 2^96
     * @param tick The input tick for the above formula
     * @return sqrtPriceX96 A Fixed point Q64.96 number representing the sqrt of the ratio of the two assets (token1/token0)
     */
    function _getSqrtRatioAtTick(int24 tick) internal pure returns (uint160 sqrtPriceX96) {
        uint256 absTick = tick < 0 ? uint256(-int256(tick)) : uint256(int256(tick));
        require(absTick <= uint256(int256(887272)), "T");

        uint256 ratio = absTick & 0x1 != 0 ? 0xfffcb933bd6fad37aa2d162d1a594001 : 0x100000000000000000000000000000000;
        if (absTick & 0x2 != 0) ratio = (ratio * 0xfff97272373d413259a46990580e213a) >> 128;
        if (absTick & 0x4 != 0) ratio = (ratio * 0xfff2e50f5f656932ef12357cf3c7fdcc) >> 128;
        if (absTick & 0x8 != 0) ratio = (ratio * 0xffe5caca7e10e4e61c3624eaa0941cd0) >> 128;
        if (absTick & 0x10 != 0) ratio = (ratio * 0xffcb9843d60f6159c9db58835c926644) >> 128;
        if (absTick & 0x20 != 0) ratio = (ratio * 0xff973b41fa98c081472e6896dfb254c0) >> 128;
        if (absTick & 0x40 != 0) ratio = (ratio * 0xff2ea16466c96a3843ec78b326b52861) >> 128;
        if (absTick & 0x80 != 0) ratio = (ratio * 0xfe5dee046a99a2a811c461f1969c3053) >> 128;
        if (absTick & 0x100 != 0) ratio = (ratio * 0xfcbe86c7900a88aedcffc83b479aa3a4) >> 128;
        if (absTick & 0x200 != 0) ratio = (ratio * 0xf987a7253ac413176f2b074cf7815e54) >> 128;
        if (absTick & 0x400 != 0) ratio = (ratio * 0xf3392b0822b70005940c7a398e4b70f3) >> 128;
        if (absTick & 0x800 != 0) ratio = (ratio * 0xe7159475a2c29b7443b29c7fa6e889d9) >> 128;
        if (absTick & 0x1000 != 0) ratio = (ratio * 0xd097f3bdfd2022b8845ad8f792aa5825) >> 128;
        if (absTick & 0x2000 != 0) ratio = (ratio * 0xa9f746462d870fdf8a65dc1f90e061e5) >> 128;
        if (absTick & 0x4000 != 0) ratio = (ratio * 0x70d869a156d2a1b890bb3df62baf32f7) >> 128;
        if (absTick & 0x8000 != 0) ratio = (ratio * 0x31be135f97d08fd981231505542fcfa6) >> 128;
        if (absTick & 0x10000 != 0) ratio = (ratio * 0x9aa508b5b7a84e1c677de54f3e99bc9) >> 128;
        if (absTick & 0x20000 != 0) ratio = (ratio * 0x5d6af8dedb81196699c329225ee604) >> 128;
        if (absTick & 0x40000 != 0) ratio = (ratio * 0x2216e584f5fa1ea926041bedfe98) >> 128;
        if (absTick & 0x80000 != 0) ratio = (ratio * 0x48a170391f7dc42444e8fa2) >> 128;

        if (tick > 0) ratio = type(uint256).max / ratio;

        // this divides by 1<<32 rounding up to go from a Q128.128 to a Q128.96.
        // we then downcast because we know the result always fits within 160 bits due to our tick input constraint
        // we round up in the division so getTickAtSqrtRatio of the output price is always consistent
        sqrtPriceX96 = uint160((ratio >> 32) + (ratio % (1 << 32) == 0 ? 0 : 1));
    }

    /**
     * @notice Calculates the greatest tick value such that getRatioAtTick(tick) <= ratio
     * @param sqrtPriceX96 The sqrt ratio for which to compute the tick as a Q64.96
     * @return tick The greatest tick for which the ratio is less than or equal to the input ratio
     */
    function _getTickFromSqrtRatio(uint160 sqrtPriceX96) internal pure returns (int24 tick) {
        // second inequality must be < because the price can never reach the price at the max tick
        require(sqrtPriceX96 >= 4295128739 && sqrtPriceX96 < 1461446703485210103287273052203988822378723970342, "R");

        uint256 ratio = uint256(sqrtPriceX96) << 32;

        uint256 r = ratio;
        uint256 msb = 0;

        assembly {
            let f := shl(7, gt(r, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF))
            msb := or(msb, f)
            r := shr(f, r)
        }
        assembly {
            let f := shl(6, gt(r, 0xFFFFFFFFFFFFFFFF))
            msb := or(msb, f)
            r := shr(f, r)
        }
        assembly {
            let f := shl(5, gt(r, 0xFFFFFFFF))
            msb := or(msb, f)
            r := shr(f, r)
        }
        assembly {
            let f := shl(4, gt(r, 0xFFFF))
            msb := or(msb, f)
            r := shr(f, r)
        }
        assembly {
            let f := shl(3, gt(r, 0xFF))
            msb := or(msb, f)
            r := shr(f, r)
        }
        assembly {
            let f := shl(2, gt(r, 0xF))
            msb := or(msb, f)
            r := shr(f, r)
        }
        assembly {
            let f := shl(1, gt(r, 0x3))
            msb := or(msb, f)
            r := shr(f, r)
        }
        assembly {
            let f := gt(r, 0x1)
            msb := or(msb, f)
        }

        if (msb >= 128) r = ratio >> (msb - 127);
        else r = ratio << (127 - msb);

        int256 log_2 = (int256(msb) - 128) << 64;

        assembly {
            r := shr(127, mul(r, r))
            let f := shr(128, r)
            log_2 := or(log_2, shl(63, f))
            r := shr(f, r)
        }
        assembly {
            r := shr(127, mul(r, r))
            let f := shr(128, r)
            log_2 := or(log_2, shl(62, f))
            r := shr(f, r)
        }
        assembly {
            r := shr(127, mul(r, r))
            let f := shr(128, r)
            log_2 := or(log_2, shl(61, f))
            r := shr(f, r)
        }
        assembly {
            r := shr(127, mul(r, r))
            let f := shr(128, r)
            log_2 := or(log_2, shl(60, f))
            r := shr(f, r)
        }
        assembly {
            r := shr(127, mul(r, r))
            let f := shr(128, r)
            log_2 := or(log_2, shl(59, f))
            r := shr(f, r)
        }
        assembly {
            r := shr(127, mul(r, r))
            let f := shr(128, r)
            log_2 := or(log_2, shl(58, f))
            r := shr(f, r)
        }
        assembly {
            r := shr(127, mul(r, r))
            let f := shr(128, r)
            log_2 := or(log_2, shl(57, f))
            r := shr(f, r)
        }
        assembly {
            r := shr(127, mul(r, r))
            let f := shr(128, r)
            log_2 := or(log_2, shl(56, f))
            r := shr(f, r)
        }
        assembly {
            r := shr(127, mul(r, r))
            let f := shr(128, r)
            log_2 := or(log_2, shl(55, f))
            r := shr(f, r)
        }
        assembly {
            r := shr(127, mul(r, r))
            let f := shr(128, r)
            log_2 := or(log_2, shl(54, f))
            r := shr(f, r)
        }
        assembly {
            r := shr(127, mul(r, r))
            let f := shr(128, r)
            log_2 := or(log_2, shl(53, f))
            r := shr(f, r)
        }
        assembly {
            r := shr(127, mul(r, r))
            let f := shr(128, r)
            log_2 := or(log_2, shl(52, f))
            r := shr(f, r)
        }
        assembly {
            r := shr(127, mul(r, r))
            let f := shr(128, r)
            log_2 := or(log_2, shl(51, f))
            r := shr(f, r)
        }
        assembly {
            r := shr(127, mul(r, r))
            let f := shr(128, r)
            log_2 := or(log_2, shl(50, f))
        }

        int256 log_sqrt10001 = log_2 * 255738958999603826347141; // 128.128 number

        int24 tickLow = int24((log_sqrt10001 - 3402992956809132418596140100660247210) >> 128);
        int24 tickHi = int24((log_sqrt10001 + 291339464771989622907027621153398088495) >> 128);

        tick = tickLow == tickHi ? tickLow : _getSqrtRatioAtTick(tickHi) <= sqrtPriceX96 ? tickHi : tickLow;
    }

    /**
     * @notice Calculates floor(a×b÷denominator) with full precision. Throws if result overflows a uint256 or denominator == 0
     * @param a The multiplicand
     * @param b The multiplier
     * @param denominator The divisor
     * @return result The 256-bit result
     */
    function _mulDiv(
        uint256 a,
        uint256 b,
        uint256 denominator
    ) internal pure returns (uint256 result) {
        // 512-bit multiply [prod1 prod0] = a * b
        // Compute the product mod 2**256 and mod 2**256 - 1
        // then use the Chinese Remainder Theorem to reconstruct
        // the 512 bit result. The result is stored in two 256
        // bit values such that product = prod1 * 2**256 + prod0
        uint256 prod0; // Least significant 256 bits of the product
        uint256 prod1; // Most significant 256 bits of the product
        assembly {
            let mm := mulmod(a, b, not(0))
            prod0 := mul(a, b)
            prod1 := sub(sub(mm, prod0), lt(mm, prod0))
        }

        // Handle non-overflow cases, 256 by 256 division
        if (prod1 == 0) {
            require(denominator > 0);
            assembly {
                result := div(prod0, denominator)
            }
            return result;
        }

        // Make sure the result is less than 2**256.
        // Also prevents denominator == 0
        require(denominator > prod1);

        ///////////////////////////////////////////////
        // 512 by 256 division.
        ///////////////////////////////////////////////

        // Make division exact by subtracting the remainder from [prod1 prod0]
        // Compute remainder using mulmod
        uint256 remainder;
        assembly {
            remainder := mulmod(a, b, denominator)
        }
        // Subtract 256 bit number from 512 bit number
        assembly {
            prod1 := sub(prod1, gt(remainder, prod0))
            prod0 := sub(prod0, remainder)
        }

        // Factor powers of two out of denominator
        // Compute largest power of two divisor of denominator.
        // Always >= 1.
        uint256 twos = (0 - denominator) & denominator;
        // Divide denominator by power of two
        assembly {
            denominator := div(denominator, twos)
        }

        // Divide [prod1 prod0] by the factors of two
        assembly {
            prod0 := div(prod0, twos)
        }
        // Shift in bits from prod1 into prod0. For this we need
        // to flip `twos` such that it is 2**256 / twos.
        // If twos is zero, then it becomes one
        assembly {
            twos := add(div(sub(0, twos), twos), 1)
        }
        prod0 |= prod1 * twos;

        // Invert denominator mod 2**256
        // Now that denominator is an odd number, it has an inverse
        // modulo 2**256 such that denominator * inv = 1 mod 2**256.
        // Compute the inverse by starting with a seed that is correct
        // correct for four bits. That is, denominator * inv = 1 mod 2**4
        uint256 inv = (3 * denominator) ^ 2;
        // Now use Newton-Raphson iteration to improve the precision.
        // Thanks to Hensel's lifting lemma, this also works in modular
        // arithmetic, doubling the correct bits in each step.
        inv *= 2 - denominator * inv; // inverse mod 2**8
        inv *= 2 - denominator * inv; // inverse mod 2**16
        inv *= 2 - denominator * inv; // inverse mod 2**32
        inv *= 2 - denominator * inv; // inverse mod 2**64
        inv *= 2 - denominator * inv; // inverse mod 2**128
        inv *= 2 - denominator * inv; // inverse mod 2**256

        // Because the division is now exact we can divide by multiplying
        // with the modular inverse of denominator. This will give us the
        // correct result modulo 2**256. Since the precoditions guarantee
        // that the outcome is less than 2**256, this is the final result.
        // We don't need to compute the high bits of the result and prod1
        // is no longer required.
        result = prod0 * inv;
        return result;
    }
}