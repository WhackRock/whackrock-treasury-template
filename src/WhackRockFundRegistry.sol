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

import "@openzeppelin/contracts/access/Ownable.sol";
import {IAerodromeRouter} from "./interfaces/IRouter.sol";
import {WhackRockFund} from "./WhackRockFundV5_ERC4626_Aerodrome_SubGEvents.sol";
import {IWhackRockFundRegistry} from "./interfaces/IWhackRockFundRegistry.sol";


contract WhackRockFundRegistry is IWhackRockFundRegistry, Ownable {
    IAerodromeRouter public immutable aerodromeRouter;
    address public immutable WETH_ADDRESS; // Derived WETH address for checks

    address[] public deployedFunds;
    mapping(address => address) public fundToCreator;
    uint256 public fundCounter;

    // --- New state variables for registry-level allowed tokens ---
    address[] public allowedTokensList; // List of tokens globally allowed by the registry
    mapping(address => bool) public isTokenAllowedInRegistry; // Quick check for registry allowance
    uint256 public maxInitialAllowedTokensLength; // Max number of tokens a single fund can select

    // --- New state variable for unique symbol check ---
    mapping(string => bool) public isSymbolTaken;

    /**
     * @param _initialOwner The owner of this registry contract.
     * @param _aerodromeRouterAddress The official Aerodrome Router address on Base mainnet.
     * @param _maxInitialTokens The maximum number of allowed tokens a user can select for their fund.
     */
    constructor(address _initialOwner, address _aerodromeRouterAddress, uint256 _maxInitialTokens)
        Ownable(_initialOwner)
    {
        require(_aerodromeRouterAddress != address(0), "Registry: Aerodrome router cannot be zero");
        require(_maxInitialTokens > 0, "Registry: Max initial tokens must be > 0");

        aerodromeRouter = IAerodromeRouter(_aerodromeRouterAddress);
        WETH_ADDRESS = address(aerodromeRouter.weth());
        require(WETH_ADDRESS != address(0), "Registry: Could not derive WETH address");

        maxInitialAllowedTokensLength = _maxInitialTokens;
    }

    /**
     * @notice Adds a token to the registry's global list of allowed tokens.
     * @param _token The address of the token to add.
     */
    function addRegistryAllowedToken(address _token) external onlyOwner {
        require(_token != address(0), "Registry: Token cannot be zero address");
        require(_token != WETH_ADDRESS, "Registry: WETH cannot be an allowed token");
        require(!isTokenAllowedInRegistry[_token], "Registry: Token already allowed");

        allowedTokensList.push(_token);
        isTokenAllowedInRegistry[_token] = true;
        emit RegistryAllowedTokenAdded(_token);
    }

    /**
     * @notice Removes a token from the registry's global list of allowed tokens.
     * @dev This implementation reorders the list for gas efficiency.
     * @param _token The address of the token to remove.
     */
    function removeRegistryAllowedToken(address _token) external onlyOwner {
        require(isTokenAllowedInRegistry[_token], "Registry: Token not in allowed list");

        isTokenAllowedInRegistry[_token] = false; // Mark as not allowed first

        // Find and remove from array (swap with last element and pop)
        for (uint256 i = 0; i < allowedTokensList.length; i++) {
            if (allowedTokensList[i] == _token) {
                allowedTokensList[i] = allowedTokensList[allowedTokensList.length - 1];
                allowedTokensList.pop();
                break; // Token found and removed
            }
        }
        emit RegistryAllowedTokenRemoved(_token);
    }

    /**
     * @notice Sets the maximum number of allowed tokens a fund can be created with.
     * @param _newMaxLength The new maximum length.
     */
    function setMaxInitialAllowedTokensLength(uint256 _newMaxLength) external onlyOwner {
        require(_newMaxLength > 0, "Registry: Max length must be > 0");
        maxInitialAllowedTokensLength = _newMaxLength;
        emit MaxInitialAllowedTokensLengthUpdated(_newMaxLength);
    }

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
    ) external returns (address fundAddress) {
        require(_fundAllowedTokens.length > 0, "Registry: Fund must have at least one token");
        require(
            _fundAllowedTokens.length <= maxInitialAllowedTokensLength,
            "Registry: Exceeds max allowed tokens for a fund"
        );
        require(bytes(_vaultSymbol).length > 0, "Registry: Vault symbol cannot be empty");
        require(!isSymbolTaken[_vaultSymbol], "Registry: Vault symbol already taken");

        // Verify that all tokens chosen for the fund are in the registry's allowed list
        for (uint256 i = 0; i < _fundAllowedTokens.length; i++) {
            require(isTokenAllowedInRegistry[_fundAllowedTokens[i]], "Registry: Fund token not allowed by registry");
            // WhackRockFund constructor already checks if token is WETH, so no need to re-check here.
        }

        // IMPORTANT: This line assumes the full WhackRockFund contract definition
        // (from your 'whackrock_fund_contract' immersive)
        // is available during compilation (e.g., imported correctly).
        WhackRockFund newFund = new WhackRockFund(
            msg.sender, // Creator is the initial owner of the fund
            _initialAgent,
            address(aerodromeRouter),
            _fundAllowedTokens,
            _initialTargetWeights,
            _vaultName,
            _vaultSymbol
        );

        fundAddress = address(newFund);
        deployedFunds.push(fundAddress);
        fundToCreator[fundAddress] = msg.sender;
        isSymbolTaken[_vaultSymbol] = true; // Mark symbol as taken
        fundCounter++;

        emit WhackRockFundCreated(
            fundCounter,
            fundAddress,
            msg.sender,
            _initialAgent,
            _vaultName,
            _vaultSymbol,
            _fundAllowedTokens, // Emitting the tokens chosen for *this* fund
            _initialTargetWeights,
            block.timestamp
        );

        return fundAddress;
    }

    /**
     * @notice Returns the total number of funds created by this factory.
     */
    function getDeployedFundsCount() external view returns (uint256) {
        return deployedFunds.length;
    }

    /**
     * @notice Returns the address of a fund by its index in the deployedFunds array.
     * @param _index The index of the fund.
     */
    function getFundAddressByIndex(uint256 _index) external view returns (address) {
        require(_index < deployedFunds.length, "Registry: Index out of bounds");
        return deployedFunds[_index];
    }

    /**
     * @notice Returns a copy of the registry's global list of allowed tokens.
     * @dev Useful for frontends to know which tokens can be selected.
     */
    function getRegistryAllowedTokens() external view returns (address[] memory) {
        return allowedTokensList;
    }
}
