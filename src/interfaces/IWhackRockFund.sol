// SPDX-License-Identifier: BUSL-1.1

/*
 *  
 *   oooooo   oooooo     oooo ooooo   ooooo       .o.         .oooooo.   oooo    oooo ooooooooo.     .oooooo.     .oooooo.   oooo    oooo 
 *   `888.    `888.     .8'  `888'   `888'      .888.       d8P'  `Y8b  `888   .8P'  `888   `Y88.  d8P'  `Y8b   d8P'  `Y8b  `888   .8P'  
 *    `888.   .8888.   .8'    888     888      .8"888.     888           888  d8'     888   .d88' 888      888 888           888  d8'    
 *     `888  .8'`888. .8'     888ooooo888     .8' `888.    888           88888[       888ooo88P'  888      888 888           88888[      
 *      `888.8'  `888.8'      888     888    .88ooo8888.   888           888`88b.     888`88b.    888      888 888           888`88b.    
 *       `888'    `888'       888     888   .8'     `888.  `88b    ooo   888  `88b.   888  `88b.  `88b    d88' `88b    ooo   888  `88b.  
 *        `8'      `8'       o888o   o888o o88o     o8888o  `Y8bood8P'  o888o  o888o o888o  o888o  `Y8bood8P'   `Y8bood8P'  o888o  o888o 
 *  
 *    AGENT‑MANAGED WEIGHTED FUND   
 *    © 2024 WhackRock Labs – All rights reserved.
 */

pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IAerodromeRouter} from "./IRouter.sol"; // Defines IAerodromeRouter

/**
 * @title IWhackRockFund
 * @dev Interface for the WhackRockFund contract.
 * @notice interface IWhackRockFund should be paired with IERC20
 */
interface IWhackRockFund {
    // --- Events from WhackRockFund ---
    event AgentUpdated(address indexed oldAgent, address indexed newAgent);
    event TargetWeightsUpdated(address[] tokens, uint256[] weights);
    event RebalanceCheck(bool needed, uint256 maxDeviationBPS);
    event RebalanceCycleExecuted(uint256 navBeforeRebalanceAA, uint256 navAfterRebalanceAA, uint256 blockTimestamp);
    event FundTokenSwapped(address indexed tokenFrom, uint256 amountFrom, address indexed tokenTo, uint256 amountTo);
    event EmergencyWithdrawal(address indexed token, uint256 amount);
    event WETHDepositedAndSharesMinted(
        address indexed depositor, address indexed receiver, uint256 wethDeposited, uint256 sharesMinted
    );
    event BasketAssetsWithdrawn(
        address indexed owner,
        address indexed receiver,
        uint256 sharesBurned,
        address[] tokensWithdrawn,
        uint256[] amountsWithdrawn
    );

    // --- Event from Ownable ---
    // event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    // --- Public State Variable Getters ---
    // (Constants like TOTAL_WEIGHT_BASIS_POINTS are part of the contract's public API but not typically listed as functions in interfaces)

    function agent() external view returns (address);

    function dexRouter() external view returns (IAerodromeRouter);

    function ACCOUNTING_ASSET() external view returns (address);

    // Getter for the entire allowedTokens array
    // function allowedTokens() external view returns (address[] memory);

    // Getter for an element in the allowedTokens array (implicitly generated)
    // function allowedTokens(uint256 index) external view returns (address);

    function targetWeights(address token) external view returns (uint256);

    function isAllowedTokenInternal(address token) external view returns (bool);

    function TOTAL_WEIGHT_BASIS_POINTS() external view returns (uint256);
    function DEFAULT_SLIPPAGE_BPS() external view returns (uint256);
    function SWAP_DEADLINE_OFFSET() external view returns (uint256);
    function DEFAULT_POOL_STABILITY() external view returns (bool);
    function REBALANCE_DEVIATION_THRESHOLD_BPS() external view returns (uint256);

    // --- Functions from WhackRockFund ---
    // function totalNAVInAccountingAsset() external view returns (uint256 totalManagedAssets);

    // function deposit(uint256 amountWETHToDeposit, address receiver) external returns (uint256 sharesMinted);

    // function withdraw(uint256 sharesToBurn, address receiver, address owner) external;

    // function setAgent(address _newAgent) external;

    // function setTargetWeights(uint256[] calldata _weights) external;

    // function triggerRebalance() external;

    // function emergencyWithdrawERC20(address _tokenAddress, address _to, uint256 _amount) external;

    // function emergencyWithdrawNative(address payable _to, uint256 _amount) external;

    // --- Functions from Ownable (explicitly listed for clarity) ---
    // function owner() external view returns (address);

    // function renounceOwnership() external;

    // function transferOwnership(address newOwner) external;

    // --- ERC20 Functions (covered by `is IERC20` inheritance) ---
    // function name() external view returns (string memory);
    // function symbol() external view returns (string memory);
    // function decimals() external view returns (uint8);
    // function totalSupply() external view returns (uint256);
    // function balanceOf(address account) external view returns (uint256);
    // function transfer(address recipient, uint256 amount) external returns (bool);
    // function allowance(address owner, address spender) external view returns (uint256);
    // function approve(address spender, uint256 amount) external returns (bool);
    // function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);

    // --- ERC20 Events (covered by `is IERC20` inheritance or its base IERC20 definition) ---
    // event Transfer(address indexed from, address indexed to, uint256 value);
    // event Approval(address indexed owner, address indexed spender, uint256 value);
}
