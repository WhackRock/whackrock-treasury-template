// SPDX‑License‑Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IPriceOracle
 * @notice Standard USD price oracle interface (18‑dec scale).
 */
interface IPriceOracle {
    /// @param token ERC‑20 address
    /// @return priceUsd1e18  USD price * 1e18
    function usdPrice(address token) external view returns (uint256 priceUsd1e18);
}
