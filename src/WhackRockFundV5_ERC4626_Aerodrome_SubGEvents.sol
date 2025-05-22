// SPDX-License-Identifier: BUSL-1.1
// © 2024 WhackRock Labs – All rights reserved.
// WHACKROCK – AGENT‑MANAGED WEIGHTED VAULT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @title IWETH
 * @dev Minimal interface for WETH (Wrapped Ether), needed by IAerodromeRouter.
 */
interface IWETH is IERC20 {
    function deposit() external payable;
    function withdraw(uint256 wad) external;
}

/**
 * @title IAerodromeRouter
 * @dev Interface for the Aerodrome Router, based on official IRouter.sol.
 */
interface IAerodromeRouter {
    struct Route {
        address from;
        address to;
        bool stable;
        address factory;
    }

    function defaultFactory() external view returns (address);
    function weth() external view returns (IWETH);

    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        Route[] calldata routes,
        address to,
        uint deadline
    ) external returns (uint256[] memory amounts);

    function getAmountsOut(uint amountIn, Route[] memory routes) external view returns (uint[] memory amounts);
}

/**
 * @title WhackRockFund
 * @dev An agent-managed fund with custom shares, WETH deposits, and basket withdrawals.
 * Conditionally and automatically rebalances to target weights after deposits and withdrawals
 * if weights deviate beyond a defined threshold.
 * Shares of this fund are ERC20 tokens.
 */
contract WhackRockFund is ERC20, Ownable {
    using SafeERC20 for IERC20;

    struct TokenRebalanceInfo {
        address token;
        uint256 currentBalance;
        uint256 currentValueInAccountingAsset;
        uint256 targetValueInAccountingAsset;
        int256 deltaValueInAccountingAsset;
    }

    address public agent;
    IAerodromeRouter public immutable dexRouter;
    address public immutable ACCOUNTING_ASSET; // WETH

    address[] public allowedTokens;
    mapping(address => uint256) public targetWeights;
    mapping(address => bool) public isAllowedTokenInternal;

    uint256 public constant TOTAL_WEIGHT_BASIS_POINTS = 10000; // Represents 100%
    uint256 public constant DEFAULT_SLIPPAGE_BPS = 50; // 0.5%
    uint256 public constant SWAP_DEADLINE_OFFSET = 15 minutes;
    bool public constant DEFAULT_POOL_STABILITY = false;
    uint256 private constant MINIMUM_SHARES_LIQUIDITY = 1000;
    // NEW: Threshold for triggering rebalance, e.g., 100 BPS = 1% deviation
    uint256 public constant REBALANCE_DEVIATION_THRESHOLD_BPS = 100; 


    event AgentUpdated(address indexed oldAgent, address indexed newAgent);
    event TargetWeightsUpdated(address[] tokens, uint256[] weights);
    event RebalanceCheck(bool needed, uint256 maxDeviationBPS); // For debugging/info
    event RebalanceCycleExecuted(
        uint256 navBeforeRebalanceAA,
        uint256 navAfterRebalanceAA,
        uint256 blockTimestamp
    );
    event FundTokenSwapped(address indexed tokenFrom, uint256 amountFrom, address indexed tokenTo, uint256 amountTo);
    event EmergencyWithdrawal(address indexed token, uint256 amount);
    
    event WETHDepositedAndSharesMinted(
        address indexed depositor,
        address indexed receiver,
        uint256 wethDeposited,
        uint256 sharesMinted
    );
    event BasketAssetsWithdrawn(
        address indexed owner,
        address indexed receiver,
        uint256 sharesBurned,
        address[] tokensWithdrawn,
        uint256[] amountsWithdrawn
    );


    modifier onlyAgent() {
        require(msg.sender == agent, "WRF: Caller is not the agent");
        _;
    }

    constructor(
        address _initialOwner,
        address _initialAgent,
        address _dexRouterAddress,
        address[] memory _initialAllowedTokens,
        uint256[] memory _initialTargetWeights,
        string memory _vaultName,
        string memory _vaultSymbol
    )
        ERC20(_vaultName, _vaultSymbol)
        Ownable(_initialOwner)
    {
        require(_initialAgent != address(0), "WRF: Initial agent cannot be zero address");
        require(_dexRouterAddress != address(0), "WRF: DEX router cannot be zero address");
        IAerodromeRouter tempRouter = IAerodromeRouter(_dexRouterAddress);
        ACCOUNTING_ASSET = address(tempRouter.weth());
        require(ACCOUNTING_ASSET != address(0), "WRF: Accounting asset (WETH) not found");

        require(_initialAllowedTokens.length > 0, "WRF: No allowed tokens provided");
        require(_initialAllowedTokens.length == _initialTargetWeights.length, "WRF: Allowed tokens and weights length mismatch");

        agent = _initialAgent;
        dexRouter = tempRouter;
        allowedTokens = _initialAllowedTokens;

        uint256 currentTotalWeight = 0;
        for (uint i = 0; i < _initialAllowedTokens.length; i++) {
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

        emit AgentUpdated(address(0), _initialAgent);
        emit TargetWeightsUpdated(_initialAllowedTokens, _initialTargetWeights);
    }

    function totalNAVInAccountingAsset() public view returns (uint256 totalManagedAssets) {
        totalManagedAssets = 0;
        for (uint i = 0; i < allowedTokens.length; i++) {
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
     * @dev Internal function to check if the portfolio weights deviate significantly from targets.
     * @return True if rebalance is needed, false otherwise.
     * @return maxDeviationBPS The maximum deviation found among all tokens.
     */
    function _isRebalanceNeeded() internal view returns (bool, uint256 maxDeviationBPS) {
        uint256 currentNAV = totalNAVInAccountingAsset();
        if (currentNAV == 0) {
            return (false, 0); 
        }

        maxDeviationBPS = 0;
        bool needsRebalance = false;

        for (uint i = 0; i < allowedTokens.length; i++) {
            address currentToken = allowedTokens[i];
            uint256 tokenBalance = IERC20(currentToken).balanceOf(address(this));
            uint256 tokenValueInAA = _getTokenValueInAccountingAsset(currentToken, tokenBalance);
            
            uint256 actualWeightBPS = (tokenValueInAA * TOTAL_WEIGHT_BASIS_POINTS) / currentNAV;
            uint256 targetWeightBPS = targetWeights[currentToken];
            
            uint256 deviation;
            if (actualWeightBPS > targetWeightBPS) {
                deviation = actualWeightBPS - targetWeightBPS;
            } else {
                deviation = targetWeightBPS - actualWeightBPS;
            }

            if (deviation > maxDeviationBPS) {
                maxDeviationBPS = deviation;
            }

            if (deviation > REBALANCE_DEVIATION_THRESHOLD_BPS) {
                needsRebalance = true;
                // We can break early if one token already exceeds threshold,
                // but calculating maxDeviationBPS might be useful for event/logging.
                // For now, let's continue to find maxDeviationBPS.
            }
        }
        
        // Also check deviation for the ACCOUNTING_ASSET (WETH) itself if it's not explicitly weighted
        // but its implied weight is (100% - sum of allowedToken weights).
        // For simplicity, current logic assumes allowedTokens sum to 100%.
        // If not, WETH's target weight would need to be considered.
        // The current _rebalance logic implicitly handles WETH.

        return (needsRebalance, maxDeviationBPS);
    }


    function deposit(uint256 amountWETHToDeposit, address receiver) external returns (uint256 sharesMinted) {
        require(amountWETHToDeposit > 0, "WRF: Deposit amount must be > 0");
        require(receiver != address(0), "WRF: Receiver cannot be zero address");

        uint256 nav = totalNAVInAccountingAsset();
        uint256 currentTotalSupply = totalSupply();

        if (currentTotalSupply == 0) {
            sharesMinted = amountWETHToDeposit; // Simplified for first deposit
            if (sharesMinted < MINIMUM_SHARES_LIQUIDITY && amountWETHToDeposit > 0) {
                 sharesMinted = MINIMUM_SHARES_LIQUIDITY;
            }
        } else {
            require(nav > 0, "WRF: Cannot deposit to empty vault with existing shares");
            sharesMinted = (amountWETHToDeposit * currentTotalSupply) / nav;
        }
        require(sharesMinted > 0, "WRF: No shares to mint for deposit");

        IERC20(ACCOUNTING_ASSET).safeTransferFrom(msg.sender, address(this), amountWETHToDeposit);
        _mint(receiver, sharesMinted);

        emit WETHDepositedAndSharesMinted(msg.sender, receiver, amountWETHToDeposit, sharesMinted);
        
        (bool needsRebalance, uint256 maxDeviationBPS) = _isRebalanceNeeded();
        emit RebalanceCheck(needsRebalance, maxDeviationBPS);
        if (needsRebalance || currentTotalSupply == 0) { // Also rebalance if it was the first deposit into an empty fund
            _rebalance(); 
        }
        return sharesMinted;
    }

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
        
        uint256 currentTotalSupply = totalSupply();
        require(currentTotalSupply >= sharesToBurn, "WRF: Burn amount exceeds total supply");
        require(balanceOf(owner) >= sharesToBurn, "WRF: Insufficient shares to burn");

        uint256 numAssetsToWithdraw = allowedTokens.length + 1;
        address[] memory tokensWithdrawn = new address[](numAssetsToWithdraw);
        uint256[] memory amountsWithdrawn = new uint256[](numAssetsToWithdraw);
        uint256 eventIdx = 0;

        uint256 wethBalance = IERC20(ACCOUNTING_ASSET).balanceOf(address(this));
        if (wethBalance > 0 && currentTotalSupply > 0) {
            uint256 wethToWithdraw = (wethBalance * sharesToBurn) / currentTotalSupply;
            if (wethToWithdraw > 0) {
                IERC20(ACCOUNTING_ASSET).safeTransfer(receiver, wethToWithdraw);
                tokensWithdrawn[eventIdx] = ACCOUNTING_ASSET;
                amountsWithdrawn[eventIdx] = wethToWithdraw;
                eventIdx++;
            }
        }

        for (uint i = 0; i < allowedTokens.length; i++) {
            address currentToken = allowedTokens[i];
            uint256 tokenBalance = IERC20(currentToken).balanceOf(address(this));
            if (tokenBalance > 0 && currentTotalSupply > 0) {
                uint256 tokenAmountToWithdraw = (tokenBalance * sharesToBurn) / currentTotalSupply;
                if (tokenAmountToWithdraw > 0) {
                    IERC20(currentToken).safeTransfer(receiver, tokenAmountToWithdraw);
                    tokensWithdrawn[eventIdx] = currentToken;
                    amountsWithdrawn[eventIdx] = tokenAmountToWithdraw;
                    eventIdx++;
                }
            }
        }
        
        _burn(owner, sharesToBurn);

        address[] memory finalTokensWithdrawn = new address[](eventIdx);
        uint256[] memory finalAmountsWithdrawn = new uint256[](eventIdx);
        for(uint k=0; k < eventIdx; k++){
            finalTokensWithdrawn[k] = tokensWithdrawn[k];
            finalAmountsWithdrawn[k] = amountsWithdrawn[k];
        }
        emit BasketAssetsWithdrawn(owner, receiver, sharesToBurn, finalTokensWithdrawn, finalAmountsWithdrawn);
        
        (bool needsRebalance, uint256 maxDeviationBPS) = _isRebalanceNeeded();
        emit RebalanceCheck(needsRebalance, maxDeviationBPS);
        if (needsRebalance && totalSupply() > 0) { // Only rebalance if there are shares left
            _rebalance();
        }
    }


    function setAgent(address _newAgent) external onlyOwner {
        require(_newAgent != address(0), "WRF: New agent cannot be zero address");
        address oldAgent = agent;
        agent = _newAgent;
        emit AgentUpdated(oldAgent, _newAgent);
    }

    function setTargetWeights(uint256[] calldata _weights) external onlyAgent {
        require(_weights.length == allowedTokens.length, "WRF: Weights length mismatch");
        uint256 currentTotalWeight = 0;
        for (uint i = 0; i < _weights.length; i++) {
            require(_weights[i] > 0, "WRF: Weight must be > 0");
            currentTotalWeight += _weights[i];
        }
        require(currentTotalWeight == TOTAL_WEIGHT_BASIS_POINTS, "WRF: Weights do not sum to total");

        address[] memory tokensForEvent = new address[](allowedTokens.length);
        for (uint i = 0; i < allowedTokens.length; i++) {
            targetWeights[allowedTokens[i]] = _weights[i];
            tokensForEvent[i] = allowedTokens[i];
        }
        emit TargetWeightsUpdated(tokensForEvent, _weights);
    }

    function triggerRebalance() external onlyAgent {
        uint256 navBeforeRebalanceAA = totalNAVInAccountingAsset();
        _rebalance();
        uint256 navAfterRebalanceAA = totalNAVInAccountingAsset();
        emit RebalanceCycleExecuted(navBeforeRebalanceAA, navAfterRebalanceAA, block.timestamp);
    }

    function _rebalance() internal {
        uint256 currentPortfolioNAVForTargets = totalNAVInAccountingAsset();
        if (currentPortfolioNAVForTargets == 0) return;

        TokenRebalanceInfo[] memory rebalanceInfos = new TokenRebalanceInfo[](allowedTokens.length);

        for (uint i = 0; i < allowedTokens.length; i++) {
            address currentToken = allowedTokens[i];
            rebalanceInfos[i].token = currentToken;
            rebalanceInfos[i].currentBalance = IERC20(currentToken).balanceOf(address(this));
            rebalanceInfos[i].currentValueInAccountingAsset = _getTokenValueInAccountingAsset(currentToken, rebalanceInfos[i].currentBalance);
            rebalanceInfos[i].targetValueInAccountingAsset = (currentPortfolioNAVForTargets * targetWeights[currentToken]) / TOTAL_WEIGHT_BASIS_POINTS;
            rebalanceInfos[i].deltaValueInAccountingAsset = int256(rebalanceInfos[i].targetValueInAccountingAsset) - int256(rebalanceInfos[i].currentValueInAccountingAsset);
        }

        for (uint i = 0; i < rebalanceInfos.length; i++) {
            if (rebalanceInfos[i].deltaValueInAccountingAsset < 0) {
                uint256 valueToSellInAA = uint256(-rebalanceInfos[i].deltaValueInAccountingAsset);
                uint256 amountToSellInTokenUnits;
                if (rebalanceInfos[i].currentValueInAccountingAsset > 0) {
                    amountToSellInTokenUnits = Math.min(rebalanceInfos[i].currentBalance, (rebalanceInfos[i].currentBalance * valueToSellInAA) / rebalanceInfos[i].currentValueInAccountingAsset);
                } else { amountToSellInTokenUnits = 0; }
                if (amountToSellInTokenUnits == 0) continue;
                amountToSellInTokenUnits = Math.min(amountToSellInTokenUnits, IERC20(rebalanceInfos[i].token).balanceOf(address(this)));
                if (amountToSellInTokenUnits == 0) continue;
                _swapTokens(rebalanceInfos[i].token, ACCOUNTING_ASSET, amountToSellInTokenUnits, DEFAULT_SLIPPAGE_BPS);
            }
        }

        uint256 availableAccountingAssetForBuys = IERC20(ACCOUNTING_ASSET).balanceOf(address(this));
        if (availableAccountingAssetForBuys == 0) return;
        uint256 totalAccountingAssetNeededForBuys = 0;
        for (uint i = 0; i < rebalanceInfos.length; i++) {
            if (rebalanceInfos[i].deltaValueInAccountingAsset > 0) { totalAccountingAssetNeededForBuys += uint256(rebalanceInfos[i].deltaValueInAccountingAsset); }
        }
        if (totalAccountingAssetNeededForBuys == 0) return;

        for (uint i = 0; i < rebalanceInfos.length; i++) {
            if (rebalanceInfos[i].deltaValueInAccountingAsset > 0) {
                uint256 idealAAToSpend = uint256(rebalanceInfos[i].deltaValueInAccountingAsset);
                uint256 actualAAToSpend = (idealAAToSpend * Math.min(availableAccountingAssetForBuys, totalAccountingAssetNeededForBuys)) / totalAccountingAssetNeededForBuys;
                uint256 currentAABalance = IERC20(ACCOUNTING_ASSET).balanceOf(address(this));
                actualAAToSpend = Math.min(actualAAToSpend, currentAABalance);
                if (actualAAToSpend == 0) continue;
                _swapTokens(ACCOUNTING_ASSET, rebalanceInfos[i].token, actualAAToSpend, DEFAULT_SLIPPAGE_BPS);
            }
        }
    }

    function _swapTokens(address _tokenIn, address _tokenOut, uint256 _amountIn, uint256 _slippageBps) internal {
        if (_amountIn == 0) return;
        require(_tokenIn != _tokenOut, "WRF: Cannot swap token for itself");

        IAerodromeRouter.Route[] memory routes = new IAerodromeRouter.Route[](1);
        routes[0] = IAerodromeRouter.Route({
            from: _tokenIn, to: _tokenOut, stable: DEFAULT_POOL_STABILITY, factory: dexRouter.defaultFactory()
        });

        uint256[] memory expectedAmountsOut = dexRouter.getAmountsOut(_amountIn, routes);
        require(expectedAmountsOut.length > 0 && expectedAmountsOut[expectedAmountsOut.length - 1] > 0, "WRF: Expected swap output is zero");
        uint256 expectedAmountOut = expectedAmountsOut[expectedAmountsOut.length - 1];
        uint256 amountOutMin = (expectedAmountOut * (TOTAL_WEIGHT_BASIS_POINTS - _slippageBps)) / TOTAL_WEIGHT_BASIS_POINTS;

        uint256[] memory actualAmounts = dexRouter.swapExactTokensForTokens(
            _amountIn, amountOutMin, routes, address(this), block.timestamp + SWAP_DEADLINE_OFFSET
        );
        require(actualAmounts.length > 0, "WRF: Swap returned no amounts");
        emit FundTokenSwapped(_tokenIn, _amountIn, _tokenOut, actualAmounts[actualAmounts.length - 1]);
    }

    function _getTokenValueInAccountingAsset(address _token, uint256 _amount) internal view returns (uint256) {
        if (_amount == 0) return 0;
        require(_token != ACCOUNTING_ASSET, "WRF: _getTokenValueInAccountingAsset called for the accounting asset itself");

        IAerodromeRouter.Route[] memory routes = new IAerodromeRouter.Route[](1);
        routes[0] = IAerodromeRouter.Route({
            from: _token, to: ACCOUNTING_ASSET, stable: DEFAULT_POOL_STABILITY, factory: dexRouter.defaultFactory()
        });

        try dexRouter.getAmountsOut(_amount, routes) returns (uint[] memory amounts) {
            if (amounts.length > 0) { return amounts[amounts.length - 1]; }
            return 0;
        } catch { return 0; }
    }

    function _approveTokenIfNeeded(IERC20 _tokenContract, address _spender, uint256 _amount) internal {
        if (_tokenContract.allowance(address(this), _spender) < _amount) {
            _tokenContract.approve(_spender, _amount);
        }
    }
    
    function emergencyWithdrawERC20(address _tokenAddress, address _to, uint256 _amount) external onlyOwner {
        require(_to != address(0), "WRF: Cannot withdraw to zero address");
        IERC20 tokenToWithdraw = IERC20(_tokenAddress);
        uint256 balance = tokenToWithdraw.balanceOf(address(this));
        require(_amount <= balance, "WRF: Insufficient balance for emergency withdrawal");
        tokenToWithdraw.safeTransfer(_to, _amount);
        emit EmergencyWithdrawal(_tokenAddress, _amount);
    }

    function emergencyWithdrawNative(address payable _to, uint256 _amount) external onlyOwner {
        require(_to != address(0), "WRF: Cannot withdraw to zero address");
        uint256 balance = address(this).balance;
        require(_amount <= balance, "WRF: Insufficient native (ETH) balance");
        (bool success, ) = _to.call{value: _amount}("");
        require(success, "WRF: Native (ETH) transfer failed");
    }
}
