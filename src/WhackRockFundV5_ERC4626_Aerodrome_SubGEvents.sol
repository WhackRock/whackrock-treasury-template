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
 *    AGENT‑MANAGED WEIGHTED FUND NON-UPGRADEABLE
 *    © 2024 WhackRock Labs – All rights reserved.
 */


import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import {IAerodromeRouter} from "./interfaces/IRouter.sol"; 
import {IWhackRockFund} from "./interfaces/IWhackRockFund.sol"; 

/**
 * @title WhackRockFund
 * @author WhackRock Labs
 * @notice An agent-managed investment fund with custom ERC20 shares, WETH deposits, and basket withdrawals
 * @dev Implements an automated portfolio management system with:
 *      - ERC20 tokenized shares
 *      - Dynamic asset allocation through target weights
 *      - Automatic rebalancing after deposits and withdrawals
 *      - Agent and protocol fee collection through share minting
 *      - DEX integration for asset swaps
 */
contract WhackRockFund is IWhackRockFund, ERC20, Ownable {
    using SafeERC20 for IERC20;

    /**
     * @dev Structure used during rebalancing to track token information
     * @param token Token address
     * @param currentBalance Current token balance held by the fund
     * @param currentValueInAccountingAsset Current value of balance in WETH
     * @param targetValueInAccountingAsset Target value based on weights in WETH
     * @param deltaValueInAccountingAsset Difference between target and current value
     */
    struct TokenRebalanceInfo {
        address token;
        uint256 currentBalance;
        uint256 currentValueInAccountingAsset;
        uint256 targetValueInAccountingAsset;
        int256 deltaValueInAccountingAsset;
    }

    /// @notice Address of the agent managing the fund's investments
    address public agent;
    
    /// @notice DEX router used for swapping tokens during rebalancing
    IAerodromeRouter public immutable dexRouter;
    
    /// @notice Address of WETH, used as the accounting asset for NAV calculations
    address public immutable ACCOUNTING_ASSET; // WETH
    
    /// @notice Address of USDC token used for USD-denominated calculations
    address public immutable USDC_ADDRESS; // USDC token address

    /// @notice Array of token addresses allowed in the fund
    address[] public allowedTokens;
    
    /// @notice Mapping of token address to its target weight in basis points
    mapping(address => uint256) public targetWeights;
    
    /// @notice Mapping to check if a token is allowed in the fund
    mapping(address => bool) public isAllowedTokenInternal;

    // Agent and Protocol AUM Fee parameters
    /// @notice Address receiving the agent's portion of AUM fees
    address public immutable agentAumFeeWallet;
    
    /// @notice Annual AUM fee rate in basis points
    uint256 public immutable agentAumFeeBps;
    
    /// @notice Address receiving the protocol's portion of AUM fees
    address public immutable protocolAumFeeRecipient;
    
    /// @notice Timestamp of the last AUM fee collection
    uint256 public lastAgentAumFeeCollectionTimestamp;

    /// @notice Total basis points representing 100% (10000)
    uint256 public constant TOTAL_WEIGHT_BASIS_POINTS = 10000;
    
    /// @notice Percentage of AUM fee allocated to the agent (60%)
    uint256 public constant AGENT_AUM_FEE_SHARE_BPS = 6000;
    
    /// @notice Percentage of AUM fee allocated to the protocol (40%)
    uint256 public constant PROTOCOL_AUM_FEE_SHARE_BPS = 4000;

    /// @notice Default slippage tolerance for swaps (0.5%)
    uint256 public constant DEFAULT_SLIPPAGE_BPS = 50;
    
    /// @notice Time buffer added to swap deadlines
    uint256 public constant SWAP_DEADLINE_OFFSET = 15 minutes;
    
    /// @notice Default pool stability setting for Aerodrome swaps
    bool public constant DEFAULT_POOL_STABILITY = false;
    
    /// @notice Minimum liquidity required for first deposit in WETH units
    uint256 private constant MINIMUM_SHARES_LIQUIDITY = 1000;
    
    /// @notice Minimum initial deposit amount required to create a new fund (0.1 WETH)
    /// @dev Protects against dust attacks on first deposit that could manipulate share price
    uint256 public constant MINIMUM_INITIAL_DEPOSIT = 0.1 ether;
    
    /// @notice Minimum deposit amount required for all deposits (0.01 WETH)
    /// @dev Prevents dust deposits that could be used for inflation attacks
    uint256 public constant MINIMUM_DEPOSIT = 0.01 ether;
    
    /// @notice Threshold for triggering rebalancing (1% deviation)
    uint256 public constant REBALANCE_DEVIATION_THRESHOLD_BPS = 100;

    /**
     * @notice Restricts function access to the current agent
     */
    modifier onlyAgent() {
        require(msg.sender == agent, "WRF: Caller is not the agent");
        _;
    }

    /**
     * @notice Creates a new WhackRockFund
     * @param _initialOwner Address of the fund owner
     * @param _initialAgent Address of the initial agent managing the fund
     * @param _dexRouterAddress Address of the Aerodrome router
     * @param _initialAllowedTokens Array of initially allowed token addresses
     * @param _initialTargetWeights Array of target weights for each allowed token
     * @param _vaultName Name of the fund's ERC20 token
     * @param _vaultSymbol Symbol of the fund's ERC20 token
     * @param _agentAumFeeWallet Address receiving the agent's portion of AUM fees
     * @param _totalAgentAumFeeBpsRate Total AUM fee rate in basis points
     * @param _protocolAumFeeRecipientAddress Address receiving the protocol's portion of AUM fees
     * @param _usdcAddress Address of USDC token
     */
    constructor(
        address _initialOwner,
        address _initialAgent,
        address _dexRouterAddress,
        address[] memory _initialAllowedTokens,
        uint256[] memory _initialTargetWeights,
        string memory _vaultName,
        string memory _vaultSymbol,
        address _agentAumFeeWallet,
        uint256 _totalAgentAumFeeBpsRate,
        address _protocolAumFeeRecipientAddress,
        address _usdcAddress,
        bytes memory /* data */ // Unused again
    ) ERC20(_vaultName, _vaultSymbol) Ownable(_initialOwner) {
        require(_initialAgent != address(0), "WRF: Initial agent cannot be zero address");
        require(_dexRouterAddress != address(0), "WRF: DEX router cannot be zero address");
        require(_agentAumFeeWallet != address(0), "WRF: Agent AUM fee wallet cannot be zero");
        require(_protocolAumFeeRecipientAddress != address(0), "WRF: Protocol AUM fee recipient cannot be zero");
        require(_usdcAddress != address(0), "WRF: USDC address cannot be zero");

        IAerodromeRouter tempRouter = IAerodromeRouter(_dexRouterAddress);
        ACCOUNTING_ASSET = address(tempRouter.weth());
        require(ACCOUNTING_ASSET != address(0), "WRF: Accounting asset (WETH) not found");
        
        // Use directly provided USDC address
        USDC_ADDRESS = _usdcAddress;

        require(_initialAllowedTokens.length > 0, "WRF: No allowed tokens provided");
        require(
            _initialAllowedTokens.length == _initialTargetWeights.length,
            "WRF: Allowed tokens and weights length mismatch"
        );

        agent = _initialAgent;
        dexRouter = tempRouter;
        allowedTokens = _initialAllowedTokens;
        agentAumFeeWallet = _agentAumFeeWallet;
        agentAumFeeBps = _totalAgentAumFeeBpsRate;
        protocolAumFeeRecipient = _protocolAumFeeRecipientAddress;
        lastAgentAumFeeCollectionTimestamp = block.timestamp;

        uint256 currentTotalWeight = 0;
        for (uint256 i = 0; i < _initialAllowedTokens.length; i++) {
            address currentToken = _initialAllowedTokens[i];
            require(currentToken != address(0), "WRF: Token address cannot be zero");
            require(currentToken != ACCOUNTING_ASSET, "WRF: Accounting asset (WETH) cannot be in allowedTokens list");
            require(_initialTargetWeights[i] > 0, "WRF: Initial weight must be > 0");

            currentTotalWeight += _initialTargetWeights[i];
            targetWeights[currentToken] = _initialTargetWeights[i];
            isAllowedTokenInternal[currentToken] = true;
            _approveTokenIfNeeded(IERC20(currentToken), address(dexRouter), type(uint256).max);
        }
        require(currentTotalWeight == TOTAL_WEIGHT_BASIS_POINTS, "WRF: Initial weights do not sum to total");
        _approveTokenIfNeeded(IERC20(ACCOUNTING_ASSET), address(dexRouter), type(uint256).max);
        
        // Approve USDC for router if needed
        _approveTokenIfNeeded(IERC20(USDC_ADDRESS), address(dexRouter), type(uint256).max);

        emit AgentUpdated(address(0), _initialAgent);
        emit TargetWeightsUpdated(msg.sender, _initialAllowedTokens, _initialTargetWeights, block.timestamp); // Added agent and timestamp
    }

    /**
     * @notice Calculates the total net asset value of the fund in accounting asset (WETH) units
     * @dev Sums up the WETH value of all tokens in the fund, including WETH itself
     * @return totalManagedAssets Total NAV in WETH
     */
    function totalNAVInAccountingAsset() public view returns (uint256 totalManagedAssets) {
        totalManagedAssets = 0;
        for (uint256 i = 0; i < allowedTokens.length; i++) {
            address currentToken = allowedTokens[i];
            uint256 balance = IERC20(currentToken).balanceOf(address(this));
            if (balance > 0) {
                totalManagedAssets += _getTokenValueInAccountingAsset(currentToken, balance);
            }
        }
        totalManagedAssets += IERC20(ACCOUNTING_ASSET).balanceOf(address(this));
        return totalManagedAssets;
    }
    
    /**
     * @notice Calculates the total net asset value of the fund in USDC units
     * @dev Converts the WETH NAV to USDC value using DEX quote
     * @return totalManagedAssetsInUSDC Total NAV in USDC
     */
    function totalNAVInUSDC() public view returns (uint256 totalManagedAssetsInUSDC) {
        uint256 navInWETH = totalNAVInAccountingAsset();
        if (navInWETH == 0) return 0;
        
        // Convert WETH value to USDC value using DEX router
        uint256 usdcValue = _getWETHValueInUSDC(navInWETH);
        
        // If we couldn't get USDC value (e.g. no liquidity), return 0
        if (usdcValue == 0) {
            return 0;
        }
        
        return usdcValue;
    }
    

    /**
     * @notice Deposits WETH into the fund and mints shares
     * @dev Handles first deposit specially, sets initial share price 1:1 with WETH
     *      May trigger rebalancing if asset weights deviate from targets
     * @param amountWETHToDeposit Amount of WETH to deposit
     * @param receiver Address to receive the minted shares
     * @return sharesMinted Number of shares minted
     */
    function deposit(uint256 amountWETHToDeposit, address receiver) external returns (uint256 sharesMinted) {
        // Enforce minimum deposit amount for all deposits
        require(amountWETHToDeposit >= MINIMUM_DEPOSIT, "WRF: Deposit below minimum");
        require(receiver != address(0), "WRF: Receiver cannot be zero address");

        uint256 navBeforeDeposit = totalNAVInAccountingAsset(); 
        uint256 totalSupplyBeforeDeposit = totalSupply();

        if (totalSupplyBeforeDeposit == 0) { // Handles first deposit
            // Require a higher minimum deposit for first deposit to prevent share price manipulation
            require(amountWETHToDeposit >= MINIMUM_INITIAL_DEPOSIT, "WRF: Initial deposit below minimum");
            
            // Initial share price 1:1 with WETH
            sharesMinted = amountWETHToDeposit;
            
            // With minimum initial deposit requirement, we can consider removing this
            // but keeping it as an additional safeguard
            if (sharesMinted < MINIMUM_SHARES_LIQUIDITY && amountWETHToDeposit > 0) {
                sharesMinted = MINIMUM_SHARES_LIQUIDITY;
            }
        } else {
            require(navBeforeDeposit > 0, "WRF: Cannot deposit to vault with zero NAV and existing shares");
            sharesMinted = (amountWETHToDeposit * totalSupplyBeforeDeposit) / navBeforeDeposit;
        }
        require(sharesMinted > 0, "WRF: No shares to mint for deposit");

        IERC20(ACCOUNTING_ASSET).safeTransferFrom(msg.sender, address(this), amountWETHToDeposit);
        _mint(receiver, sharesMinted);

        emit WETHDepositedAndSharesMinted(msg.sender, receiver, amountWETHToDeposit, sharesMinted, navBeforeDeposit, totalSupplyBeforeDeposit);

        (bool needsRebalance, uint256 maxDeviationBPS) = _isRebalanceNeeded();
        emit RebalanceCheck(needsRebalance, maxDeviationBPS, totalNAVInAccountingAsset()); // Pass current NAV
        if (needsRebalance || (totalSupplyBeforeDeposit == 0 && totalSupply() > 0) ) { 
            _rebalance();
        }
        return sharesMinted;
    }
    
    /**
     * @notice Withdraws assets from the fund by burning shares
     * @dev Burns shares and transfers a proportional amount of all fund assets to the receiver
     *      May trigger rebalancing if asset weights deviate from targets after withdrawal
     * @param sharesToBurn Number of shares to burn
     * @param receiver Address to receive the withdrawn assets
     * @param owner Address that owns the shares
     */
    function withdraw(uint256 sharesToBurn, address receiver, address owner) external {
        require(sharesToBurn > 0, "WRF: Shares to burn must be > 0");
        require(receiver != address(0), "WRF: Receiver cannot be zero address");
        require(owner != address(0), "WRF: Owner cannot be zero address");

        if (owner != msg.sender && allowance(owner, msg.sender) < sharesToBurn) {
            revert ERC20InsufficientAllowance(msg.sender, allowance(owner, msg.sender), sharesToBurn);
        }
        if (owner != msg.sender) {
            _spendAllowance(owner, msg.sender, sharesToBurn);
        }

        uint256 totalSupplyBeforeWithdrawal = totalSupply(); // Before burning
        require(totalSupplyBeforeWithdrawal >= sharesToBurn, "WRF: Burn amount exceeds total supply");
        require(balanceOf(owner) >= sharesToBurn, "WRF: Insufficient shares to burn");

        uint256 navBeforeWithdrawal = totalNAVInAccountingAsset(); // NAV before assets are removed

        uint256 numAssetsToWithdraw = allowedTokens.length + 1;
        address[] memory tokensWithdrawn = new address[](numAssetsToWithdraw);
        uint256[] memory amountsWithdrawn = new uint256[](numAssetsToWithdraw);
        uint256 eventIdx = 0;
        uint256 totalWETHValueOfWithdrawal = 0;

        uint256 wethBalance = IERC20(ACCOUNTING_ASSET).balanceOf(address(this));
        if (wethBalance > 0 && totalSupplyBeforeWithdrawal > 0) {
            uint256 wethToWithdraw = (wethBalance * sharesToBurn) / totalSupplyBeforeWithdrawal;
            if (wethToWithdraw > 0) {
                IERC20(ACCOUNTING_ASSET).safeTransfer(receiver, wethToWithdraw);
                tokensWithdrawn[eventIdx] = ACCOUNTING_ASSET;
                amountsWithdrawn[eventIdx] = wethToWithdraw;
                totalWETHValueOfWithdrawal += wethToWithdraw; // Already in WETH
                eventIdx++;
            }
        }

        for (uint256 i = 0; i < allowedTokens.length; i++) {
            address currentToken = allowedTokens[i];
            uint256 tokenBalance = IERC20(currentToken).balanceOf(address(this));
            if (tokenBalance > 0 && totalSupplyBeforeWithdrawal > 0) {
                uint256 tokenAmountToWithdraw = (tokenBalance * sharesToBurn) / totalSupplyBeforeWithdrawal;
                if (tokenAmountToWithdraw > 0) {
                    IERC20(currentToken).safeTransfer(receiver, tokenAmountToWithdraw);
                    tokensWithdrawn[eventIdx] = currentToken;
                    amountsWithdrawn[eventIdx] = tokenAmountToWithdraw;
                    totalWETHValueOfWithdrawal += _getTokenValueInAccountingAsset(currentToken, tokenAmountToWithdraw);
                    eventIdx++;
                }
            }
        }

        _burn(owner, sharesToBurn);

        address[] memory finalTokensWithdrawn = new address[](eventIdx);
        uint256[] memory finalAmountsWithdrawn = new uint256[](eventIdx);
        for (uint256 k = 0; k < eventIdx; k++) {
            finalTokensWithdrawn[k] = tokensWithdrawn[k];
            finalAmountsWithdrawn[k] = amountsWithdrawn[k];
        }
        emit BasketAssetsWithdrawn(
            owner, receiver, sharesToBurn, finalTokensWithdrawn, finalAmountsWithdrawn,
            navBeforeWithdrawal, totalSupplyBeforeWithdrawal, totalWETHValueOfWithdrawal
        );

        (bool needsRebalance, uint256 maxDeviationBPS) = _isRebalanceNeeded();
        emit RebalanceCheck(needsRebalance, maxDeviationBPS, totalNAVInAccountingAsset()); // Pass current NAV
        if (needsRebalance && totalSupply() > 0) {
            _rebalance();
        }
    }

    /**
     * @notice Collects the AUM fee by minting new shares
     * @dev Calculates fee based on time elapsed since last collection
     *      Mints new shares and distributes them between agent and protocol
     *      according to AGENT_AUM_FEE_SHARE_BPS and PROTOCOL_AUM_FEE_SHARE_BPS
     */
    function collectAgentManagementFee() external { 
        require(agentAumFeeBps > 0, "WRF: AUM fee not enabled for this fund");
        require(block.timestamp > lastAgentAumFeeCollectionTimestamp, "WRF: No time elapsed for AUM fee");

        uint256 navAtFeeCalc = totalNAVInAccountingAsset(); // NAV at the point of fee calculation
        uint256 sharesAtFeeCalc = totalSupply(); // Total shares at the point of fee calculation

        if (navAtFeeCalc == 0 || sharesAtFeeCalc == 0) {
            lastAgentAumFeeCollectionTimestamp = block.timestamp;
            return;
        }

        uint256 timeElapsed = block.timestamp - lastAgentAumFeeCollectionTimestamp;
        uint256 totalFeeValueInAA = (navAtFeeCalc * agentAumFeeBps * timeElapsed) / (TOTAL_WEIGHT_BASIS_POINTS * 365 days);
        
        if (totalFeeValueInAA > 0) {
            uint256 totalSharesToMintForFee = (totalFeeValueInAA * sharesAtFeeCalc) / navAtFeeCalc;
            
            if (totalSharesToMintForFee > 0) {
                uint256 agentShares = (totalSharesToMintForFee * AGENT_AUM_FEE_SHARE_BPS) / TOTAL_WEIGHT_BASIS_POINTS;
                uint256 protocolShares = totalSharesToMintForFee - agentShares;

                if (agentShares > 0) {
                    _mint(agentAumFeeWallet, agentShares);
                }
                if (protocolShares > 0) {
                    _mint(protocolAumFeeRecipient, protocolShares);
                }
                
                emit AgentAumFeeCollected(
                    agentAumFeeWallet, agentShares,
                    protocolAumFeeRecipient, protocolShares,
                    totalFeeValueInAA, 
                    navAtFeeCalc, // Added NAV at time of calculation
                    sharesAtFeeCalc, // Added total shares at time of calculation
                    block.timestamp
                );
            }
        }
        lastAgentAumFeeCollectionTimestamp = block.timestamp;
    }

    /**
     * @notice Updates the fund's agent address
     * @dev Only callable by fund owner
     * @param _newAgent Address of the new agent
     */
    function setAgent(address _newAgent) external onlyOwner {
        require(_newAgent != address(0), "WRF: New agent cannot be zero address");
        address oldAgent = agent;
        agent = _newAgent;
        emit AgentUpdated(oldAgent, _newAgent);
    }

    /**
     * @notice Sets new target weights for the fund's assets
     * @dev Only callable by the current agent
     *      Weights must sum to TOTAL_WEIGHT_BASIS_POINTS (10000)
     * @param _weights Array of new target weights in basis points
     */
    function setTargetWeights(uint256[] calldata _weights) external onlyAgent {
        require(_weights.length == allowedTokens.length, "WRF: Weights length mismatch");
        uint256 currentTotalWeight = 0;
        for (uint256 i = 0; i < _weights.length; i++) {
            require(_weights[i] > 0, "WRF: Weight must be > 0");
            currentTotalWeight += _weights[i];
        }
        require(currentTotalWeight == TOTAL_WEIGHT_BASIS_POINTS, "WRF: Weights do not sum to total");

        address[] memory tokensForEvent = new address[](allowedTokens.length);
        for (uint256 i = 0; i < allowedTokens.length; i++) {
            targetWeights[allowedTokens[i]] = _weights[i];
            tokensForEvent[i] = allowedTokens[i];
        }
        emit TargetWeightsUpdated(msg.sender, tokensForEvent, _weights, block.timestamp); // Added agent and timestamp
    }

    /**
     * @notice Manually triggers a rebalance of the fund's assets
     * @dev Only callable by the agent
     *      Emits a RebalanceCycleExecuted event with NAV before and after
     */
    function triggerRebalance() external onlyAgent {
        uint256 navBeforeRebalanceAA = totalNAVInAccountingAsset();
        _rebalance();
        uint256 navAfterRebalanceAA = totalNAVInAccountingAsset();
        emit RebalanceCycleExecuted(navBeforeRebalanceAA, navAfterRebalanceAA, block.timestamp);
    }

    /**
     * @notice Emergency function to withdraw ERC20 tokens
     * @dev Only callable by owner, used in case of token airdrops or emergencies
     * @param _tokenAddress Address of the token to withdraw
     * @param _to Address to receive the withdrawn tokens
     * @param _amount Amount of tokens to withdraw
     */
    function emergencyWithdrawERC20(address _tokenAddress, address _to, uint256 _amount) external onlyOwner {
        require(_to != address(0), "WRF: Cannot withdraw to zero address");
        IERC20 tokenToWithdraw = IERC20(_tokenAddress);
        uint256 balance = tokenToWithdraw.balanceOf(address(this));
        require(_amount <= balance, "WRF: Insufficient balance for emergency withdrawal");
        tokenToWithdraw.safeTransfer(_to, _amount);
        emit EmergencyWithdrawal(_tokenAddress, _amount);
    }

    /**
     * @notice Emergency function to withdraw native ETH
     * @dev Only callable by owner, used in case ETH is accidentally sent to the contract
     * @param _to Address to receive the withdrawn ETH
     * @param _amount Amount of ETH to withdraw
     */
    function emergencyWithdrawNative(address payable _to, uint256 _amount) external onlyOwner {
        require(_to != address(0), "WRF: Cannot withdraw to zero address");
        uint256 balance = address(this).balance;
        require(_amount <= balance, "WRF: Insufficient native (ETH) balance");
        (bool success,) = _to.call{value: _amount}("");
        require(success, "WRF: Native (ETH) transfer failed");
    }

    

    
    /**
     * @notice Rebalances the fund's assets to match target weights
     * @dev First sells tokens that are overweight, then buys tokens that are underweight
     *      Uses a two-step process to minimize price impact
     */
    function _rebalance() internal {
        uint256 currentPortfolioNAVForTargets = totalNAVInAccountingAsset();
        if (currentPortfolioNAVForTargets == 0) return;

        TokenRebalanceInfo[] memory rebalanceInfos = new TokenRebalanceInfo[](allowedTokens.length);

        for (uint256 i = 0; i < allowedTokens.length; i++) {
            address currentToken = allowedTokens[i];
            rebalanceInfos[i].token = currentToken;
            rebalanceInfos[i].currentBalance = IERC20(currentToken).balanceOf(address(this));
            rebalanceInfos[i].currentValueInAccountingAsset =
                _getTokenValueInAccountingAsset(currentToken, rebalanceInfos[i].currentBalance);
            rebalanceInfos[i].targetValueInAccountingAsset =
                (currentPortfolioNAVForTargets * targetWeights[currentToken]) / TOTAL_WEIGHT_BASIS_POINTS;
            rebalanceInfos[i].deltaValueInAccountingAsset = int256(rebalanceInfos[i].targetValueInAccountingAsset)
                - int256(rebalanceInfos[i].currentValueInAccountingAsset);
        }

        for (uint256 i = 0; i < rebalanceInfos.length; i++) {
            if (rebalanceInfos[i].deltaValueInAccountingAsset < 0) {
                uint256 valueToSellInAA = uint256(-rebalanceInfos[i].deltaValueInAccountingAsset);
                uint256 amountToSellInTokenUnits;
                if (rebalanceInfos[i].currentValueInAccountingAsset > 0) {
                    amountToSellInTokenUnits = Math.min(
                        rebalanceInfos[i].currentBalance,
                        (rebalanceInfos[i].currentBalance * valueToSellInAA)
                            / rebalanceInfos[i].currentValueInAccountingAsset
                    );
                } else {
                    amountToSellInTokenUnits = 0;
                }
                if (amountToSellInTokenUnits == 0) continue;
                amountToSellInTokenUnits =
                    Math.min(amountToSellInTokenUnits, IERC20(rebalanceInfos[i].token).balanceOf(address(this)));
                if (amountToSellInTokenUnits == 0) continue;
                _swapTokens(rebalanceInfos[i].token, ACCOUNTING_ASSET, amountToSellInTokenUnits, DEFAULT_SLIPPAGE_BPS);
            }
        }

        uint256 availableAccountingAssetForBuys = IERC20(ACCOUNTING_ASSET).balanceOf(address(this));
        if (availableAccountingAssetForBuys == 0) return;
        uint256 totalAccountingAssetNeededForBuys = 0;
        for (uint256 i = 0; i < rebalanceInfos.length; i++) {
            if (rebalanceInfos[i].deltaValueInAccountingAsset > 0) {
                totalAccountingAssetNeededForBuys += uint256(rebalanceInfos[i].deltaValueInAccountingAsset);
            }
        }
        if (totalAccountingAssetNeededForBuys == 0) return;

        for (uint256 i = 0; i < rebalanceInfos.length; i++) {
            if (rebalanceInfos[i].deltaValueInAccountingAsset > 0) {
                uint256 idealAAToSpend = uint256(rebalanceInfos[i].deltaValueInAccountingAsset);
                uint256 actualAAToSpend = (
                    idealAAToSpend * Math.min(availableAccountingAssetForBuys, totalAccountingAssetNeededForBuys)
                ) / totalAccountingAssetNeededForBuys;
                uint256 currentAABalance = IERC20(ACCOUNTING_ASSET).balanceOf(address(this));
                actualAAToSpend = Math.min(actualAAToSpend, currentAABalance);
                if (actualAAToSpend == 0) continue;
                _swapTokens(ACCOUNTING_ASSET, rebalanceInfos[i].token, actualAAToSpend, DEFAULT_SLIPPAGE_BPS);
            }
        }
    }

    /**
     * @notice Swaps tokens using the DEX router
     * @dev Uses Aerodrome router to execute a swap with slippage protection
     * @param _tokenIn Address of the token to sell
     * @param _tokenOut Address of the token to buy
     * @param _amountIn Amount of input token to swap
     * @param _slippageBps Maximum acceptable slippage in basis points
     */
    function _swapTokens(address _tokenIn, address _tokenOut, uint256 _amountIn, uint256 _slippageBps) internal {
        if (_amountIn == 0) return;
        require(_tokenIn != _tokenOut, "WRF: Cannot swap token for itself");

        IAerodromeRouter.Route[] memory routes = new IAerodromeRouter.Route[](1);
        routes[0] = IAerodromeRouter.Route({
            from: _tokenIn,
            to: _tokenOut,
            stable: DEFAULT_POOL_STABILITY,
            factory: dexRouter.defaultFactory()
        });

        uint256[] memory expectedAmountsOut = dexRouter.getAmountsOut(_amountIn, routes);
        require(
            expectedAmountsOut.length > 0 && expectedAmountsOut[expectedAmountsOut.length - 1] > 0,
            "WRF: Expected swap output is zero"
        );
        uint256 expectedAmountOut = expectedAmountsOut[expectedAmountsOut.length - 1];
        uint256 amountOutMin =
            (expectedAmountOut * (TOTAL_WEIGHT_BASIS_POINTS - _slippageBps)) / TOTAL_WEIGHT_BASIS_POINTS;

        uint256[] memory actualAmounts = dexRouter.swapExactTokensForTokens(
            _amountIn, amountOutMin, routes, address(this), block.timestamp + SWAP_DEADLINE_OFFSET
        );
        require(actualAmounts.length > 0, "WRF: Swap returned no amounts");
        emit FundTokenSwapped(_tokenIn, _amountIn, _tokenOut, actualAmounts[actualAmounts.length - 1]);
    }


    /**
     * @notice Approves a token for spending if current allowance is insufficient
     * @dev Avoids unnecessary approve calls if allowance is already sufficient
     * @param _tokenContract The ERC20 token contract
     * @param _spender Address to approve spending for
     * @param _amount Amount to approve
     */
    function _approveTokenIfNeeded(IERC20 _tokenContract, address _spender, uint256 _amount) internal {
        if (_tokenContract.allowance(address(this), _spender) < _amount) {
            _tokenContract.approve(_spender, _amount);
        }
    }

    
    /**
     * @notice Gets the value of a token amount in accounting asset (WETH) units
     * @dev Uses the DEX router's price oracle to calculate the equivalent WETH value
     * @param _token Address of the token to value
     * @param _amount Amount of the token to value
     * @return WETH value of the specified token amount
     */
    function _getTokenValueInAccountingAsset(address _token, uint256 _amount) internal view returns (uint256) {
        if (_amount == 0) return 0;
        require(
            _token != ACCOUNTING_ASSET, "WRF: _getTokenValueInAccountingAsset called for the accounting asset itself"
        );

        IAerodromeRouter.Route[] memory routes = new IAerodromeRouter.Route[](1);
        routes[0] = IAerodromeRouter.Route({
            from: _token,
            to: ACCOUNTING_ASSET,
            stable: DEFAULT_POOL_STABILITY,
            factory: dexRouter.defaultFactory()
        });

        try dexRouter.getAmountsOut(_amount, routes) returns (uint256[] memory amounts) {
            if (amounts.length > 0) return amounts[amounts.length - 1];
            return 0;
        } catch {
            return 0;
        }
    }

    
    /**
     * @notice Gets the USDC value of a given WETH amount
     * @dev Uses the Aerodrome router to get price quote from WETH to USDC
     * @param _wethAmount Amount of WETH to convert
     * @return USDC value of the WETH amount
     */
    function _getWETHValueInUSDC(uint256 _wethAmount) internal view returns (uint256) {
        if (_wethAmount == 0) return 0;
        
        // Check if we can get a direct quote from WETH to USDC
        IAerodromeRouter.Route[] memory routes = new IAerodromeRouter.Route[](1);
        routes[0] = IAerodromeRouter.Route({
            from: ACCOUNTING_ASSET,
            to: USDC_ADDRESS,
            stable: DEFAULT_POOL_STABILITY,
            factory: dexRouter.defaultFactory()
        });
        
        try dexRouter.getAmountsOut(_wethAmount, routes) returns (uint256[] memory amounts) {
            if (amounts.length > 0 && amounts[amounts.length - 1] > 0) {
                return amounts[amounts.length - 1];
            }
        } catch {
            revert("WRF: Failed to get WETH to USDC quote");
        }
        
        return 0;
    }

    /**
     * @notice Checks if the fund needs rebalancing
     * @dev Compares current asset weights to target weights and determines maximum deviation
     * @return needsRebalance True if any asset deviates from target by more than threshold
     * @return maxDeviationBPS Maximum deviation found in basis points
     */
    function _isRebalanceNeeded() internal view returns (bool needsRebalance, uint256 maxDeviationBPS) {
        uint256 currentNAV = totalNAVInAccountingAsset();
        if (currentNAV == 0) {
            return (false, 0);
        }
        maxDeviationBPS = 0;
        needsRebalance = false; // Explicitly initialize
        for (uint256 i = 0; i < allowedTokens.length; i++) {
            address currentToken = allowedTokens[i];
            uint256 tokenBalance = IERC20(currentToken).balanceOf(address(this));
            uint256 tokenValueInAA = _getTokenValueInAccountingAsset(currentToken, tokenBalance);
            
            // This check `if (currentNAV == 0) return (true, TOTAL_WEIGHT_BASIS_POINTS);` was inside the loop
            // and would cause issues if the first token had 0 value but NAV was non-zero due to other tokens.
            // The initial currentNAV == 0 check at the function start handles the main case.
            // If currentNAV becomes 0 mid-loop due to an unpriceable token, calculations might be skewed.
            // _getTokenValueInAccountingAsset returns 0 for unpriceable tokens, which is handled.

            uint256 actualWeightBPS = (tokenValueInAA * TOTAL_WEIGHT_BASIS_POINTS) / currentNAV;
            uint256 targetWeightBPS = targetWeights[currentToken];
            uint256 deviation = actualWeightBPS > targetWeightBPS ? actualWeightBPS - targetWeightBPS : targetWeightBPS - actualWeightBPS;
            if (deviation > maxDeviationBPS) maxDeviationBPS = deviation;
            if (deviation > REBALANCE_DEVIATION_THRESHOLD_BPS) needsRebalance = true;
        }
        // Emitting RebalanceCheck here is more informative as it's called before deciding to rebalance.
        // The deposit/withdraw functions will also emit it.
        return (needsRebalance, maxDeviationBPS);
    }

}