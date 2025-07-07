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
 *    WHACKROCK – FUND FACTORY INTERFACE  
 *    © 2024 WhackRock Labs – All rights reserved.
 */

/**
 * @title IWhackRockFundFactory
 * @author WhackRock Labs
 * @notice Interface for the WhackRockFundFactory contract
 * @dev This interface defines the functions required for creating WhackRockFund instances
 */
interface IWhackRockFundFactory {
    /**
     * @notice Creates a new WhackRockFund
     * @dev This function contains all the deployment logic for fund creation
     * @param _initialOwner Address of the initial owner of the fund
     * @param _initialAgent Address of the initial agent managing the fund
     * @param _uniswapV3RouterAddress Address of the Uniswap V3 router
     * @param _uniswapV3QuoterAddress Address of the Uniswap V3 quoter
     * @param _uniswapV3FactoryAddress Address of the Uniswap V3 factory
     * @param _wethAddress Address of WETH token (accounting asset)
     * @param _fundAllowedTokens Array of allowed token addresses for the fund
     * @param _initialTargetWeights Array of target weights for each allowed token
     * @param _vaultName Name of the fund's ERC20 token
     * @param _vaultSymbol Symbol of the fund's ERC20 token
     * @param _vaultURI URI for the fund's metadata
     * @param _agentAumFeeWalletForFund Address receiving the agent's portion of AUM fees
     * @param _agentSetTotalAumFeeBps Total AUM fee in basis points set by the agent
     * @param _protocolAumFeeRecipientForFunds Address receiving the protocol's portion of AUM fees
     * @param _usdcTokenAddress Address of the USDC token
     * @return Address of the newly created fund
     */
    function createFund(
        address _initialOwner,
        address _initialAgent,
        address _uniswapV3RouterAddress,
        address _uniswapV3QuoterAddress,
        address _uniswapV3FactoryAddress,
        address _wethAddress,
        address[] memory _fundAllowedTokens,
        uint256[] memory _initialTargetWeights,
        string memory _vaultName,
        string memory _vaultSymbol,
        string memory _vaultURI,
        address _agentAumFeeWalletForFund,
        uint256 _agentSetTotalAumFeeBps,
        address _protocolAumFeeRecipientForFunds,
        address _usdcTokenAddress
    ) external returns (address);
}
