// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

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
 *    WHACKROCK – FUND REGISTRY AND FACTORY UPGRADABLE   
 *    © 2024 WhackRock Labs – All rights reserved.
 */

import {IAerodromeRouter} from "./IRouter.sol";

/**
 * @title IWhackRockFundRegistry
 * @author WhackRock Labs
 * @notice Interface for the WhackRockFundRegistry contract which manages the creation and registration of WhackRock investment funds
 * @dev This interface defines the events and functions for fund creation, token allowlist management, and parameter updates
 */
interface IWhackRockFundRegistry {
    // --- Events ---
    /**
     * @notice Emitted when a new WhackRock fund is created
     * @param fundId Unique identifier for the fund
     * @param fundAddress Contract address of the newly created fund
     * @param creator Address that created the fund
     * @param initialAgent Address of the initial agent managing the fund
     * @param vaultName Name of the fund's vault
     * @param vaultSymbol ERC20 symbol for the fund's shares
     * @param vaultURI URI for the fund's vault
     * @param allowedTokens Array of token addresses allowed in the fund
     * @param targetWeights Array of target weights for each allowed token (in basis points)
     * @param agentAumFeeWallet Address that receives the agent's portion of AUM fees
     * @param agentTotalAumFeeBps Total AUM fee rate in basis points
     * @param timestamp Block timestamp when the fund was created
     */
    event WhackRockFundCreated(
        uint256 indexed fundId,
        address indexed fundAddress,
        address indexed creator,
        address initialAgent,
        string vaultName,
        string vaultSymbol,
        string vaultURI,
        address[] allowedTokens,
        uint256[] targetWeights,
        address agentAumFeeWallet,
        uint256 agentTotalAumFeeBps,
        uint256 timestamp
    );

    /**
     * @notice Emitted when a token is added to the registry's global allowlist
     * @param token Address of the token that was added
     */
    event RegistryAllowedTokenAdded(address indexed token);
    
    /**
     * @notice Emitted when a token is removed from the registry's global allowlist
     * @param token Address of the token that was removed
     */
    event RegistryAllowedTokenRemoved(address indexed token);
    
    /**
     * @notice Emitted when the maximum allowed tokens limit is updated
     * @param newLength New maximum number of tokens allowed in a fund at creation
     */
    event MaxInitialAllowedTokensLengthUpdated(uint256 newLength);
    
    /**
     * @notice Emitted when registry parameters are updated
     * @param usdcTokenAddress New address of the USDC token
     * @param whackRockRewardsAddr New address that receives protocol fees
     * @param protocolCreationFeeUsdc New fund creation fee in USDC
     * @param totalAumFeeBps New maximum total AUM fee in basis points
     * @param protocolAumRecipient New address that receives the protocol's portion of AUM fees
     * @param maxAgentDepositFeeBpsAllowed New maximum agent deposit fee in basis points
     */
    event RegistryParamsUpdated(
        address usdcTokenAddress,
        address whackRockRewardsAddr,
        uint256 protocolCreationFeeUsdc,
        uint256 totalAumFeeBps,
        address protocolAumRecipient,
        uint256 maxAgentDepositFeeBpsAllowed
    );

    /**
     * @notice Adds a token to the registry's global list of allowed tokens
     * @dev Only callable by the registry owner
     * @param _token The address of the token to add
     */
    function addRegistryAllowedToken(address _token) external;

    /**
     * @notice Adds a tokens to the registry's global allowlist
     * @dev Only callable by owner, cannot add address(0) or WETH
     * @param _tokens Address of the token to add
     */
    function batchAddRegistryAllowedToken(address[] memory _tokens) external;

    /**
     * @notice Removes a token from the registry's global list of allowed tokens
     * @dev This implementation reorders the list for gas efficiency
     * @param _token The address of the token to remove
     */
    function removeRegistryAllowedToken(address _token) external;

    /**
     * @notice Sets the maximum number of allowed tokens a fund can be created with
     * @dev Only callable by the registry owner
     * @param _newMaxLength The new maximum length
     */
    function setMaxInitialAllowedTokensLength(uint256 _newMaxLength) external;
    
    /**
     * @notice Creates and registers a new WhackRockFund
     * @dev Collects protocol creation fee in USDC if configured
     * @param _initialAgent The address of the agent that will manage the new fund
     * @param _fundAllowedTokens An array of token addresses the fund can hold (must be from the registry's allowlist)
     * @param _initialTargetWeights Corresponding target weights for _fundAllowedTokens (sum must be 10000 BPS)
     * @param _vaultName Name for the new fund's ERC20 shares
     * @param _vaultSymbol Symbol for the new fund's ERC20 shares (must be unique)
     * @param _vaultURI URI for the new fund's ERC20 shares
     * @param _agentAumFeeWalletForFund The wallet address that will receive the agent's AUM fees
     * @param _agentSetTotalAumFeeBps The total AUM fee in basis points set by the agent (must not exceed maximum)
     * @return fundAddress The address of the newly created WhackRockFund
     */
    function createWhackRockFund(
        address _initialAgent,
        address[] memory _fundAllowedTokens,
        uint256[] memory _initialTargetWeights,
        string memory _vaultName,
        string memory _vaultSymbol,
        string memory _vaultURI,
        address _agentAumFeeWalletForFund,
        uint256 _agentSetTotalAumFeeBps
    ) external returns (address fundAddress);

    /**
     * @notice Returns the total number of funds created by this registry
     * @return Number of deployed funds
     */
    function getDeployedFundsCount() external view returns (uint256);
    
    /**
     * @notice Returns the address of a fund by its index in the deployedFunds array
     * @param _index The index of the fund
     * @return Fund contract address
     */
    function getFundAddressByIndex(uint256 _index) external view returns (address);
    
    /**
     * @notice Returns a copy of the registry's global list of allowed tokens
     * @dev Useful for frontends to know which tokens can be selected for fund creation
     * @return Array of allowed token addresses
     */
    function getRegistryAllowedTokens() external view returns (address[] memory);
}
