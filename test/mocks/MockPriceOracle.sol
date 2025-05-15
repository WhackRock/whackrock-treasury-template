// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../../src/core/interfaces/IPriceOracle.sol";

contract MockPriceOracle is IPriceOracle {
    mapping(address => uint256) private prices;

    function setPrice(address token, uint256 price) external {
        prices[token] = price;
    }

    function usdPrice(address token) external view override returns (uint256) {
        return prices[token] > 0 ? prices[token] : 1e18; // Default to $1 if not set
    }
} 