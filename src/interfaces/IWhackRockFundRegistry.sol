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
 *    WHACKROCK – FUND REGISTRY AND FACTORY
 *    © 2024 WhackRock Labs – All rights reserved.
 */

pragma solidity ^0.8.20;

import {IAerodromeRouter} from "./IRouter.sol";

/**
 * @title IWhackRockFundRegistry
 * @dev Interface for the WhackRockFundRegistry contract.
 */
interface IWhackRockFundRegistry {
    // --- New Events ---
    event WhackRockFundCreated( // Tokens chosen for this specific fund
        uint256 indexed fundId,
        address indexed fundAddress,
        address indexed creator,
        address initialAgent,
        string vaultName,
        string vaultSymbol,
        address[] allowedTokens,
        uint256[] targetWeights,
        uint256 timestamp
    );

    event RegistryAllowedTokenAdded(address indexed token);
    event RegistryAllowedTokenRemoved(address indexed token);
    event MaxInitialAllowedTokensLengthUpdated(uint256 newLength);

    /**
     * @notice Adds a token to the registry's global list of allowed tokens.
     * @param _token The address of the token to add.
     */
    function addRegistryAllowedToken(address _token) external;

    /**
     * @notice Removes a token from the registry's global list of allowed tokens.
     * @dev This implementation reorders the list for gas efficiency.
     * @param _token The address of the token to remove.
     */
    function removeRegistryAllowedToken(address _token) external;

    /**
     * @notice Sets the maximum number of allowed tokens a fund can be created with.
     * @param _newMaxLength The new maximum length.
     */
    function setMaxInitialAllowedTokensLength(uint256 _newMaxLength) external;
    /**
     * @notice Creates and registers a new WhackRockFund.
     * @param _initialAgent The address of the AI agent that will manage the new fund.
     * @param _fundAllowedTokens An array of token addresses the fund can hold (must be a subset of registry's list).
     * @param _initialTargetWeights Corresponding target weights for _fundAllowedTokens (sum must be 10000 BPS).
     * @param _vaultName Name for the new fund's ERC20 shares (e.g., "My Agent Fund").
     * @param _vaultSymbol Symbol for the new fund's ERC20 shares (e.g., "MAF").
     * @return fundAddress The address of the newly created WhackRockFund.
     */
    function createWhackRockFund(
        address _initialAgent,
        address[] memory _fundAllowedTokens,
        uint256[] memory _initialTargetWeights,
        string memory _vaultName,
        string memory _vaultSymbol
    ) external returns (address fundAddress);

    /**
     * @notice Returns the total number of funds created by this factory.
     */
    function getDeployedFundsCount() external view returns (uint256);
    /**
     * @notice Returns the address of a fund by its index in the deployedFunds array.
     * @param _index The index of the fund.
     */
    function getFundAddressByIndex(uint256 _index) external view returns (address);
    /**
     * @notice Returns a copy of the registry's global list of allowed tokens.
     * @dev Useful for frontends to know which tokens can be selected.
     */
    function getRegistryAllowedTokens() external view returns (address[] memory);
}
