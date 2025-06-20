// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import {WhackRockFund} from "./WhackRockFundV6_UniSwap_TWAP.sol";
import {IWhackRockFundFactory} from "./interfaces/IWhackRockFundFactory.sol";

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
 *    WHACKROCK – FUND FACTORY  
 *    © 2024 WhackRock Labs – All rights reserved.
 */

/**
 * @title WhackRockFundFactory
 * @author WhackRock Labs
 * @notice Factory contract for creating WhackRockFund instances
 * @dev Separates fund creation logic from registry to reduce registry size
 */
contract WhackRockFundFactory is IWhackRockFundFactory {
    /**
     * @notice Creates a new WhackRockFund
     * @dev This function contains all the deployment logic that was in the registry
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
    ) external override returns (address) {
        WhackRockFund newFund = new WhackRockFund(
            _initialOwner, 
            _initialAgent,
            _uniswapV3RouterAddress,
            _uniswapV3QuoterAddress,
            _uniswapV3FactoryAddress,
            _wethAddress,
            _fundAllowedTokens,
            _initialTargetWeights,
            _vaultName,
            _vaultSymbol,
            _vaultURI,
            _agentAumFeeWalletForFund,     
            _agentSetTotalAumFeeBps,       
            _protocolAumFeeRecipientForFunds,
            _usdcTokenAddress,
            "" // data parameter
        );
        
        return address(newFund);
    }
}