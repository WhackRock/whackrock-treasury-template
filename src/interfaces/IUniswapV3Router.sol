// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Use official Uniswap V3 interfaces
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {IQuoterV2} from "@uniswap/v3-periphery/contracts/interfaces/IQuoterV2.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IWETH is IERC20 {
    function deposit() external payable;
    function withdraw(uint256) external;
}

// Re-export the official interfaces with our naming
interface IUniswapV3Router is ISwapRouter {}
interface IUniswapV3Quoter is IQuoterV2 {}