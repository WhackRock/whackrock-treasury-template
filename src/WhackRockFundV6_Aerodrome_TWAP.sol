// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

/*
 * * oooooo   oooooo     oooo ooooo   ooooo      .o.          .oooooo.   oooo    oooo ooooooooo.     .oooooo.     .oooooo.   oooo    oooo 
 *  `888.     `888.     .8'  `888'   `888'      .888.        d8P'  `Y8b  `888   .8P'  `888   `Y88.  d8P'  `Y8b   d8P'  `Y8b  `888   .8P'  
 *   `888.   .8888.   .8'    888     888      .8"888.      888          888  d8'     888   .d88' 888    888 888          888  d8'    
 *   `888  .8'`888. .8'     888ooooo888     .8' `888.     888          88888[       888ooo88P'  888    888 888          88888[      
 *   `888.8'  `888.8'      888     888    .88ooo8888.    888          888`88b.     888`88b.    888    888 888          888`88b.    
 *   `888'    `888'       888     888   .8'     `888.   `88b    ooo  888  `88b.   888  `88b.   `88b  d88'  `88b    ooo  888  `88b.  
 *   `8'      `8'       o888o   o888o o88o     o8888o   `Y8bood8P'  o888o  o888o o888o  o888o  `Y8bood8P'   `Y8bood8P'  o888o  o888o 
 * * AGENT-MANAGED WEIGHTED FUND (TWAP-PROTECTED)
 * © 2024 WhackRock Labs – All rights reserved.
 */

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import {IAerodromeRouter} from "./interfaces/IRouter.sol";
import {IWhackRockFund} from "./interfaces/IWhackRockFund.sol";


// [AUDIT-FIX #1] Interface to interact with Aerodrome/Velodrome V2 style pools for TWAP data.
interface IAerodromePool {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function price0CumulativeLast() external view returns (uint256);
    function price1CumulativeLast() external view returns (uint256);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
}

/**
 * @title WhackRockFund (TWAP-Protected)
 * @author WhackRock Labs
 * @notice An agent-managed investment fund that uses a manipulation-resistant TWAP oracle.
 * @dev This version incorporates a full fix for the NAV manipulation vulnerability by using
 * a Time-Weighted Average Price (TWAP) oracle based on Aerodrome's pool data.
 */
contract WhackRockFund is IWhackRockFund, ERC20, Ownable {
    using SafeERC20 for IERC20;

    // --- Errors ---
    error E1(); // Zero address
    error E2(); // Invalid amount/length
    error E3(); // Insufficient balance
    error E4(); // Unauthorized
    error E5(); // Invalid state
    error E6(); // Swap or Price Query Failed
    error E7(); // Invalid Pool for token pair
    error E8(); // Oracle update failed
    error E9(); // TWAP update period has not elapsed

    // --- Events ---
    event RebalanceSkipped(string reason);
    event EmergencyNativeWithdrawal(address indexed to, uint256 amount);
    event PoolSet(address indexed token, address indexed pool);

    // --- Structs ---
    struct TokenRebalanceInfo {
        address token;
        uint256 currentBalance;
        uint256 currentValueInAccountingAsset;
        uint256 targetValueInAccountingAsset;
        int256 deltaValueInAccountingAsset;
    }

    // [AUDIT-FIX #1] Struct to store oracle data for each token pair.
    struct OracleInfo {
        uint256 price0CumulativeLast;
        uint256 price1CumulativeLast;
        uint32 blockTimestampLast;
        uint256 priceAverage; // Price of the token in terms of ACCOUNTING_ASSET (WETH), stored as a UQ112.112 number
    }

    // --- State Variables ---
    address public agent;
    IAerodromeRouter public immutable dexRouter;
    address public immutable ACCOUNTING_ASSET; // WETH
    address public immutable USDC_ADDRESS;
    string public baseURI;
    address[] public allowedTokens;
    mapping(address => uint256) public targetWeights;
    
    mapping(address => address) public tokenToPoolMap;
    mapping(address => OracleInfo) private oracleData;

    // Fee parameters
    address public immutable agentAumFeeWallet;
    uint256 public immutable agentAumFeeBps;
    address public immutable protocolAumFeeRecipient;
    uint256 public lastAgentAumFeeCollectionTimestamp;

    // --- Constants ---
    uint256 public constant TOTAL_WEIGHT_BASIS_POINTS = 10000;
    uint256 public constant AGENT_AUM_FEE_SHARE_BPS = 6000;
    uint256 public constant PROTOCOL_AUM_FEE_SHARE_BPS = 4000;
    uint256 public constant DEFAULT_SLIPPAGE_BPS = 50;
    uint256 public constant SWAP_DEADLINE_OFFSET = 15 minutes;
    bool public constant DEFAULT_POOL_STABILITY = false;
    uint256 private constant MINIMUM_SHARES_LIQUIDITY = 1000;
    uint256 public constant MINIMUM_INITIAL_DEPOSIT = 0.01 ether;
    uint256 public constant MINIMUM_DEPOSIT = 0.01 ether;
    uint256 public constant REBALANCE_DEVIATION_THRESHOLD_BPS = 100;
    
    // [REVISED-FIX] This is the "liveness vs. safety" knob. 600 seconds (10 minutes) is a strong default.
    uint32 public constant TWAP_UPDATE_PERIOD = 600;

    // --- Modifiers ---
    modifier onlyAgent() {
        if (msg.sender != agent) revert E4();
        _;
    }

    // --- Constructor ---
    constructor(
        address _initialOwner,
        address _initialAgent,
        address _dexRouterAddress,
        address[] memory _initialAllowedTokens,
        uint256[] memory _initialTargetWeights,
        address[] memory _poolAddresses,
        string memory _vaultName,
        string memory _vaultSymbol,
        string memory _vaultURI,
        string memory _vaultDescription,
        address _agentAumFeeWallet,
        uint256 _totalAgentAumFeeBpsRate,
        address _protocolAumFeeRecipientAddress,
        address _usdcAddress
    ) ERC20(_vaultName, _vaultSymbol) Ownable(_initialOwner) {
        if (_initialAgent == address(0) || _dexRouterAddress == address(0) || _agentAumFeeWallet == address(0) || _protocolAumFeeRecipientAddress == address(0) || _usdcAddress == address(0)) revert E1();
        if (_initialAllowedTokens.length != _initialTargetWeights.length || _initialAllowedTokens.length != _poolAddresses.length) revert E2();

        IAerodromeRouter tempRouter = IAerodromeRouter(_dexRouterAddress);
        ACCOUNTING_ASSET = address(tempRouter.weth());
        if (ACCOUNTING_ASSET == address(0)) revert E1();
        
        USDC_ADDRESS = _usdcAddress;
        agent = _initialAgent;
        dexRouter = tempRouter;
        allowedTokens = _initialAllowedTokens;
        agentAumFeeWallet = _agentAumFeeWallet;
        agentAumFeeBps = _totalAgentAumFeeBpsRate;
        protocolAumFeeRecipient = _protocolAumFeeRecipientAddress;
        lastAgentAumFeeCollectionTimestamp = block.timestamp;
        baseURI = _vaultURI;

        uint256 currentTotalWeight = 0;
        for (uint256 i = 0; i < _initialAllowedTokens.length; i++) {
            address currentToken = _initialAllowedTokens[i];
            if (currentToken == address(0)) revert E1();
            if (currentToken == ACCOUNTING_ASSET) revert E5();
            if (_initialTargetWeights[i] == 0) revert E2();

            _setPool(currentToken, _poolAddresses[i]);
            
            targetWeights[currentToken] = _initialTargetWeights[i];
            currentTotalWeight += _initialTargetWeights[i];
            _approveTokenIfNeeded(IERC20(currentToken), address(dexRouter), type(uint256).max);
        }
        if (currentTotalWeight != TOTAL_WEIGHT_BASIS_POINTS) revert E2();

        _approveTokenIfNeeded(IERC20(ACCOUNTING_ASSET), address(dexRouter), type(uint256).max);
        _approveTokenIfNeeded(IERC20(USDC_ADDRESS), address(dexRouter), type(uint256).max);

        emit AgentUpdated(address(0), _initialAgent);
        emit TargetWeightsUpdated(msg.sender, _initialAllowedTokens, _initialTargetWeights, block.timestamp);
    }

    // --- Core Public/External Functions ---

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
    
    function totalNAVInUSDC() public view returns (uint256) {
        uint256 navInWETH = totalNAVInAccountingAsset();
        if (navInWETH == 0) return 0;
        return _getSpotWETHValueInUSDC(navInWETH);
    }

    function deposit(uint256 amountWETHToDeposit, address receiver) external returns (uint256 sharesMinted) {
        if (amountWETHToDeposit < MINIMUM_DEPOSIT) revert E2();
        if (receiver == address(0)) revert E1();

        _updateAllOracles();

        uint256 navBeforeDeposit = totalNAVInAccountingAsset();
        uint256 totalSupplyBeforeDeposit = totalSupply();

        if (totalSupplyBeforeDeposit == 0) {
            if (amountWETHToDeposit < MINIMUM_INITIAL_DEPOSIT) revert E2();
            sharesMinted = amountWETHToDeposit;
            if (sharesMinted < MINIMUM_SHARES_LIQUIDITY) sharesMinted = MINIMUM_SHARES_LIQUIDITY;
        } else {
            if (navBeforeDeposit == 0) revert E5();
            sharesMinted = (amountWETHToDeposit * totalSupplyBeforeDeposit) / navBeforeDeposit;
        }
        if (sharesMinted == 0) revert E5();

        IERC20(ACCOUNTING_ASSET).safeTransferFrom(msg.sender, address(this), amountWETHToDeposit);
        _mint(receiver, sharesMinted);

        uint256 wethValueInUSDC = _getSpotWETHValueInUSDC(1 ether);
        emit WETHDepositedAndSharesMinted(msg.sender, receiver, amountWETHToDeposit, sharesMinted, navBeforeDeposit, totalSupplyBeforeDeposit, wethValueInUSDC);

        (bool needsRebalance, ) = _isRebalanceNeeded();
        if (needsRebalance || (totalSupplyBeforeDeposit == 0)) {
            _rebalance();
        }
        return sharesMinted;
    }
    
    function withdraw(uint256 sharesToBurn, address receiver, address owner) external {
        if (sharesToBurn == 0) revert E2();
        if (receiver == address(0) || owner == address(0)) revert E1();

        if (owner != msg.sender) {
             _spendAllowance(owner, msg.sender, sharesToBurn);
        }
        
        uint256 totalSupplyBeforeWithdrawal = totalSupply();
        if (balanceOf(owner) < sharesToBurn) revert E3();

        uint256 navBeforeWithdrawal = totalNAVInAccountingAsset();
        _burn(owner, sharesToBurn);

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
                totalWETHValueOfWithdrawal += wethToWithdraw;
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

        address[] memory finalTokensWithdrawn = new address[](eventIdx);
        uint256[] memory finalAmountsWithdrawn = new uint256[](eventIdx);
        for (uint256 k = 0; k < eventIdx; k++) {
            finalTokensWithdrawn[k] = tokensWithdrawn[k];
            finalAmountsWithdrawn[k] = amountsWithdrawn[k];
        }
        
        uint256 wethValueInUSDC = _getSpotWETHValueInUSDC(1 ether);
        emit BasketAssetsWithdrawn(owner, receiver, sharesToBurn, finalTokensWithdrawn, finalAmountsWithdrawn, navBeforeWithdrawal, totalSupplyBeforeWithdrawal, totalWETHValueOfWithdrawal, wethValueInUSDC);

        (bool needsRebalance, uint256 maxDeviationBPS) = _isRebalanceNeeded();
        emit RebalanceCheck(needsRebalance, maxDeviationBPS, totalNAVInAccountingAsset());
        if (needsRebalance && totalSupply() > 0) {
            _rebalance();
        }
    }
    function collectAgentManagementFee() external onlyAgent {
        if (agentAumFeeBps == 0) revert E5();
        if (block.timestamp <= lastAgentAumFeeCollectionTimestamp) revert E5();

        uint256 navAtFeeCalc = totalNAVInAccountingAsset();
        uint256 sharesAtFeeCalc = totalSupply();

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

                if (agentShares > 0) _mint(agentAumFeeWallet, agentShares);
                if (protocolShares > 0) _mint(protocolAumFeeRecipient, protocolShares);

                emit AgentAumFeeCollected(agentAumFeeWallet, agentShares, protocolAumFeeRecipient, protocolShares, totalFeeValueInAA, navAtFeeCalc, sharesAtFeeCalc, block.timestamp);
            }
        }
        lastAgentAumFeeCollectionTimestamp = block.timestamp;
    }
    function setAgent(address _newAgent) external onlyOwner {
        if (_newAgent == address(0)) revert E1();
        address oldAgent = agent;
        agent = _newAgent;
        emit AgentUpdated(oldAgent, _newAgent);
    }
    function setTargetWeights(uint256[] calldata _weights) external onlyAgent {
        _setTargetWeights(_weights);
    }
    function setTargetWeightsAndRebalanceIfNeeded(uint256[] calldata _weights) external onlyAgent {
        _setTargetWeights(_weights);
        (bool needsRebalance, uint256 maxDeviationBPS) = _isRebalanceNeeded();
        emit RebalanceCheck(needsRebalance, maxDeviationBPS, totalNAVInAccountingAsset());
        if (needsRebalance && totalSupply() > 0) {
            _rebalance();
        }
    }
    function triggerRebalance() external onlyAgent { _rebalance(); }
    function getCurrentCompositionBPS() external override view returns (uint256[] memory currentComposition_, address[] memory tokenAddresses_) {
        uint256 numAllowedTokens = allowedTokens.length;
        currentComposition_ = new uint256[](numAllowedTokens);
        tokenAddresses_ = new address[](numAllowedTokens);

        uint256 currentNAV = totalNAVInAccountingAsset();

        for (uint256 i = 0; i < numAllowedTokens; i++) {
            address currentTokenAddress = allowedTokens[i];
            tokenAddresses_[i] = currentTokenAddress;

            if (currentNAV > 0) {
                uint256 tokenBalance = IERC20(currentTokenAddress).balanceOf(address(this));
                if (tokenBalance > 0) {
                    uint256 tokenValueInAA = _getTokenValueInAccountingAsset(currentTokenAddress, tokenBalance);
                    currentComposition_[i] = (tokenValueInAA * TOTAL_WEIGHT_BASIS_POINTS) / currentNAV;
                }
            }
        }
        return (currentComposition_, tokenAddresses_);
    }
    function getTargetCompositionBPS() external override view returns (uint256[] memory targetComposition_, address[] memory tokenAddresses_) {
        uint256 numAllowedTokens = allowedTokens.length;
        targetComposition_ = new uint256[](numAllowedTokens);
        tokenAddresses_ = new address[](numAllowedTokens);

        for (uint256 i = 0; i < numAllowedTokens; i++) {
            address currentTokenAddress = allowedTokens[i];
            tokenAddresses_[i] = currentTokenAddress;
            targetComposition_[i] = targetWeights[currentTokenAddress];
        }
        return (targetComposition_, tokenAddresses_);
    }

    // --- Internal Logic ---

    function _rebalance() internal {
        _updateAllOracles();
        uint256 navBeforeRebalanceAA = totalNAVInAccountingAsset();
        if (navBeforeRebalanceAA == 0) {
            emit RebalanceSkipped("NAV is zero");
            return;
        }

        TokenRebalanceInfo[] memory rebalanceInfos = new TokenRebalanceInfo[](allowedTokens.length);
        for (uint256 i = 0; i < allowedTokens.length; i++) {
            address currentToken = allowedTokens[i];
            rebalanceInfos[i].token = currentToken;
            rebalanceInfos[i].currentBalance = IERC20(currentToken).balanceOf(address(this));
            rebalanceInfos[i].currentValueInAccountingAsset = _getTokenValueInAccountingAsset(currentToken, rebalanceInfos[i].currentBalance);
            rebalanceInfos[i].targetValueInAccountingAsset = (navBeforeRebalanceAA * targetWeights[currentToken]) / TOTAL_WEIGHT_BASIS_POINTS;
            rebalanceInfos[i].deltaValueInAccountingAsset = int256(rebalanceInfos[i].targetValueInAccountingAsset) - int256(rebalanceInfos[i].currentValueInAccountingAsset);
        }

        for (uint256 i = 0; i < rebalanceInfos.length; i++) {
            if (rebalanceInfos[i].deltaValueInAccountingAsset < 0) {
                uint256 valueToSellInAA = uint256(-rebalanceInfos[i].deltaValueInAccountingAsset);
                uint256 amountToSellInTokenUnits;
                if (rebalanceInfos[i].currentValueInAccountingAsset > 0) {
                    amountToSellInTokenUnits = Math.min(rebalanceInfos[i].currentBalance, (rebalanceInfos[i].currentBalance * valueToSellInAA) / rebalanceInfos[i].currentValueInAccountingAsset);
                }
                if (amountToSellInTokenUnits > 0) {
                    _swapTokens(rebalanceInfos[i].token, ACCOUNTING_ASSET, amountToSellInTokenUnits, DEFAULT_SLIPPAGE_BPS);
                }
            }
        }

        uint256 availableAccountingAssetForBuys = IERC20(ACCOUNTING_ASSET).balanceOf(address(this));
        if (availableAccountingAssetForBuys == 0) {
            emit RebalanceSkipped("No accounting asset for buys");
            return;
        }

        uint256 totalAccountingAssetNeededForBuys = 0;
        for (uint256 i = 0; i < rebalanceInfos.length; i++) {
            if (rebalanceInfos[i].deltaValueInAccountingAsset > 0) {
                totalAccountingAssetNeededForBuys += uint256(rebalanceInfos[i].deltaValueInAccountingAsset);
            }
        }
        
        if (totalAccountingAssetNeededForBuys == 0) {
            emit RebalanceSkipped("No underweight assets to buy");
            return;
        }

        for (uint256 i = 0; i < rebalanceInfos.length; i++) {
            if (rebalanceInfos[i].deltaValueInAccountingAsset > 0) {
                uint256 idealAAToSpend = uint256(rebalanceInfos[i].deltaValueInAccountingAsset);
                uint256 actualAAToSpend = (idealAAToSpend * Math.min(availableAccountingAssetForBuys, totalAccountingAssetNeededForBuys)) / totalAccountingAssetNeededForBuys;
                if (actualAAToSpend > 0) {
                    _swapTokens(ACCOUNTING_ASSET, rebalanceInfos[i].token, actualAAToSpend, DEFAULT_SLIPPAGE_BPS);
                }
            }
        }

        uint256 navAfterRebalanceAA = totalNAVInAccountingAsset();
        uint256 wethValueInUSDC = _getSpotWETHValueInUSDC(1 ether);
        emit RebalanceCycleExecuted(navBeforeRebalanceAA, navAfterRebalanceAA, block.timestamp, wethValueInUSDC);
    }

    function _setPool(address _token, address _pool) private {
        IAerodromePool pool = IAerodromePool(_pool);
        address token0 = pool.token0();
        address token1 = pool.token1();

        if (!((token0 == _token && token1 == ACCOUNTING_ASSET) || (token0 == ACCOUNTING_ASSET && token1 == _token))) {
            revert E7();
        }
        
        tokenToPoolMap[_token] = _pool;
        (,,uint32 blockTimestampLast) = pool.getReserves();
        if (blockTimestampLast == 0) revert E8();

        oracleData[_token] = OracleInfo({
            price0CumulativeLast: pool.price0CumulativeLast(),
            price1CumulativeLast: pool.price1CumulativeLast(),
            blockTimestampLast: blockTimestampLast,
            priceAverage: 0
        });
        emit PoolSet(_token, _pool);
    }

    function _updateAllOracles() private {
        for(uint i = 0; i < allowedTokens.length; i++) {
            _updateOracle(allowedTokens[i]);
        }
    }

    function _updateOracle(address _token) private {
        OracleInfo storage o = oracleData[_token];
        IAerodromePool pool = IAerodromePool(tokenToPoolMap[_token]);
        
        (,, uint32 currentBlockTimestamp) = pool.getReserves();
        
        if (currentBlockTimestamp == o.blockTimestampLast) return;
        
        uint32 timeElapsed = currentBlockTimestamp - o.blockTimestampLast;
        
        // [REVISED-FIX] Enforce the minimum update period for security.
        if (timeElapsed < TWAP_UPDATE_PERIOD) revert E9();
        
        uint256 currentPrice0Cumulative = pool.price0CumulativeLast();
        uint256 currentPrice1Cumulative = pool.price1CumulativeLast();

        uint256 priceAverage;
        if (pool.token0() == _token) {
            priceAverage = (currentPrice0Cumulative - o.price0CumulativeLast) / timeElapsed;
        } else {
            priceAverage = (currentPrice1Cumulative - o.price1CumulativeLast) / timeElapsed;
        }
        
        o.priceAverage = priceAverage;
        o.price0CumulativeLast = currentPrice0Cumulative;
        o.price1CumulativeLast = currentPrice1Cumulative;
        o.blockTimestampLast = currentBlockTimestamp;
    }
    
    function _getTokenValueInAccountingAsset(address _token, uint256 _amount) internal view returns (uint256) {
        if (_amount == 0) return 0;
        
        uint256 price = oracleData[_token].priceAverage;
        
        // [REVISED-FIX] Removed the spot price fallback. The contract now ONLY uses the secure TWAP.
        // If the price is 0, it means the oracle hasn't been updated yet, which is a critical state.
        // The check in _updateOracle prevents actions until a safe price is available.
        if (price == 0) revert E8();

        // The price from the Uniswap V2-style oracle is a UQ112.112 fixed-point number.
        // It represents the price scaled by 2**112. To get the actual value, we multiply
        // the amount by this price and then shift right by 112 bits to scale it back down.
        // This is a highly gas-efficient way to perform fixed-point multiplication.
        return (_amount * price) >> 112;
    }
    
    function _getSpotWETHValueInUSDC(uint256 _wethAmount) internal view returns (uint256) {
        if (_wethAmount == 0) return 0;
        IAerodromeRouter.Route[] memory routes = new IAerodromeRouter.Route[](1);
        routes[0] = IAerodromeRouter.Route({from: ACCOUNTING_ASSET, to: USDC_ADDRESS, stable: false, factory: dexRouter.defaultFactory()});
        try dexRouter.getAmountsOut(_wethAmount, routes) returns (uint256[] memory amounts) {
            if (amounts.length > 0 && amounts[amounts.length-1] > 0) return amounts[amounts.length-1];
        } catch {}
        return 0;
    }

    function _approveTokenIfNeeded(IERC20 _tokenContract, address _spender, uint256 _amount) internal {
        if (_tokenContract.allowance(address(this), _spender) < _amount) {
            _tokenContract.approve(_spender, 0);
            _tokenContract.approve(_spender, type(uint256).max);
        }
    }
    
    function _setTargetWeights(uint256[] calldata _weights) internal {
        if (_weights.length != allowedTokens.length) revert E2();
        uint256 currentTotalWeight = 0;
        for (uint256 i = 0; i < _weights.length; i++) {
            if (_weights[i] == 0) revert E2();
            currentTotalWeight += _weights[i];
        }
        if (currentTotalWeight != TOTAL_WEIGHT_BASIS_POINTS) revert E2();

        for (uint256 i = 0; i < _weights.length; i++) {
            targetWeights[allowedTokens[i]] = _weights[i];
        }
        emit TargetWeightsUpdated(msg.sender, allowedTokens, _weights, block.timestamp);
    }
    function _swapTokens(address _tokenIn, address _tokenOut, uint256 _amountIn, uint256 _slippageBps) internal {
        if (_amountIn == 0) return;
        if (_tokenIn == _tokenOut) revert E5();

        IAerodromeRouter.Route[] memory routes = new IAerodromeRouter.Route[](1);
        routes[0] = IAerodromeRouter.Route({from: _tokenIn, to: _tokenOut, stable: DEFAULT_POOL_STABILITY, factory: dexRouter.defaultFactory()});

        uint256[] memory expectedAmountsOut = dexRouter.getAmountsOut(_amountIn, routes);
        if (expectedAmountsOut.length == 0 || expectedAmountsOut[expectedAmountsOut.length - 1] == 0) revert E6();
        
        uint256 expectedAmountOut = expectedAmountsOut[expectedAmountsOut.length - 1];
        uint256 amountOutMin = (expectedAmountOut * (TOTAL_WEIGHT_BASIS_POINTS - _slippageBps)) / TOTAL_WEIGHT_BASIS_POINTS;

        uint256[] memory actualAmounts = dexRouter.swapExactTokensForTokens(_amountIn, amountOutMin, routes, address(this), block.timestamp + SWAP_DEADLINE_OFFSET);
        if (actualAmounts.length == 0) revert E6();
        
        emit FundTokenSwapped(_tokenIn, _amountIn, _tokenOut, actualAmounts[actualAmounts.length - 1]);
    }
    function _isRebalanceNeeded() internal view returns (bool needsRebalance, uint256 maxDeviationBPS) {
        uint256 currentNAV = totalNAVInAccountingAsset();
        if (currentNAV == 0) {
            return (false, 0);
        }
        
        maxDeviationBPS = 0;
        needsRebalance = false;
        
        for (uint256 i = 0; i < allowedTokens.length; i++) {
            address currentToken = allowedTokens[i];
            uint256 tokenBalance = IERC20(currentToken).balanceOf(address(this));
            uint256 tokenValueInAA = _getTokenValueInAccountingAsset(currentToken, tokenBalance);

            uint256 actualWeightBPS = (tokenValueInAA * TOTAL_WEIGHT_BASIS_POINTS) / currentNAV;
            uint256 targetWeightBPS = targetWeights[currentToken];
            
            uint256 deviation = actualWeightBPS > targetWeightBPS ? actualWeightBPS - targetWeightBPS : targetWeightBPS - actualWeightBPS;
            if (deviation > maxDeviationBPS) maxDeviationBPS = deviation;
            if (deviation > REBALANCE_DEVIATION_THRESHOLD_BPS) needsRebalance = true;
        }
        return (needsRebalance, maxDeviationBPS);
    }
}
