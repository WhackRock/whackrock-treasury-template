// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

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
 *    WHACKROCK STAKING CONTRACT  
 *    © 2024 WhackRock Labs – All rights reserved.
 */


import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title WhackRockStaking
 * @author WROCK Team
 * @notice This contract allows users to stake WROCK tokens and earn points based on lock duration
 * @dev Implements a time-weighted staking mechanism with multipliers for longer lock periods
 * Points can be claimed and redeemed through an external PointsRedeemer contract
 */
contract WhackRockStaking is Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;
    
    /// @notice The ERC20 token that users stake
    IERC20 public immutable stakingToken;
    
    /// @notice Minimum duration that tokens must be locked (6 months)
    uint256 public constant MINIMUM_STAKE_DURATION = 180 days;
    
    /// @notice Maximum duration that tokens can be locked (2 years)
    uint256 public constant MAXIMUM_STAKE_DURATION = 730 days;
    
    /// @notice Timelock delay for sensitive owner functions (48 hours)
    uint256 public constant TIMELOCK_DELAY = 48 hours;
    
    /// @notice Base rate for earning points (100 points per token per day)
    uint256 public constant BASE_POINTS_RATE = 100;
    
    /**
     * @notice Struct containing staking information for each user
     * @param amount The amount of tokens staked
     * @param startTime Timestamp when the stake was created
     * @param lastClaimTime Timestamp of the last point calculation
     * @param lockDuration How long the tokens are locked for
     * @param accumulatedPoints Points earned but not yet claimed
     */
    struct Stake {
        uint256 amount;
        uint256 startTime;
        uint256 lastClaimTime;
        uint256 lockDuration;
        uint256 accumulatedPoints;
    }
    
    /// @notice Mapping of user addresses to their stake information
    mapping(address => Stake) public stakes;
    
    /// @notice Mapping of user addresses to their total claimed points
    mapping(address => uint256) public claimedPoints;
    
    /// @notice Total amount of tokens currently staked in the contract
    uint256 public totalStaked;
    
    /// @notice Address of the authorized PointsRedeemer contract
    address public pointsRedeemer;
    
    /// @notice Mapping of function to pending timelock execution
    mapping(bytes32 => uint256) public timelockExecutions;
    
    /**
     * @notice Emitted when a user stakes tokens
     * @param user Address of the staker
     * @param amount Amount of tokens staked in this transaction
     * @param totalStakedAmount User's total staked amount after this stake
     * @param lockDuration Lock duration in seconds
     * @param unlockTime Timestamp when tokens can be withdrawn
     * @param multiplier Points multiplier based on lock duration
     */
    event Staked(
        address indexed user, 
        uint256 amount, 
        uint256 totalStakedAmount,
        uint256 lockDuration,
        uint256 unlockTime,
        uint256 multiplier
    );
    /**
     * @notice Emitted when a user claims their accumulated points
     * @param user Address of the user claiming points
     * @param points Amount of points claimed
     * @param totalClaimedPoints User's total claimed points after this claim
     */
    event PointsClaimed(
        address indexed user, 
        uint256 points,
        uint256 totalClaimedPoints
    );
    /**
     * @notice Emitted when a user withdraws their staked tokens
     * @param user Address of the withdrawer
     * @param amount Amount of tokens withdrawn
     * @param points Points claimed during withdrawal
     * @param totalClaimedPoints User's total claimed points after withdrawal
     * @param stakeDuration Total duration the tokens were staked
     */
    event Withdrawn(
        address indexed user, 
        uint256 amount, 
        uint256 points,
        uint256 totalClaimedPoints,
        uint256 stakeDuration
    );
    /**
     * @notice Emitted when the points redeemer contract is updated
     * @param redeemer Address of the new points redeemer contract
     */
    event PointsRedeemerSet(address indexed redeemer);
    /**
     * @notice Emitted when points are redeemed by the authorized redeemer
     * @param user Address of the user whose points are redeemed
     * @param redeemer Address of the redeemer contract
     * @param amount Amount of points redeemed
     */
    event PointsRedeemed(
        address indexed user,
        address indexed redeemer,
        uint256 amount
    );
    /**
     * @notice Emitted when an owner function is queued for timelock
     * @param functionId Identifier of the function
     * @param executeTime Timestamp when the function can be executed
     */
    event TimelockQueued(
        bytes32 indexed functionId,
        uint256 executeTime
    );
    /**
     * @notice Emitted when a timelocked function is executed
     * @param functionId Identifier of the function
     */
    event TimelockExecuted(bytes32 indexed functionId);
    /**
     * @notice Emitted when a timelocked function is cancelled
     * @param functionId Identifier of the function
     */
    event TimelockCancelled(bytes32 indexed functionId);
    /**
     * @notice Emitted when points are accrued for a user
     * @param user Address of the user accruing points
     * @param points Amount of points accrued
     * @param timestamp Timestamp when points were accrued
     */
    event PointsAccrued(
        address indexed user,
        uint256 points,
        uint256 timestamp
    );
    
    
    /**
     * @notice Initializes the staking contract with the token to be staked
     * @param _stakingToken Address of the ERC20 token to be staked
     */
    constructor(address _stakingToken) Ownable(msg.sender) {
        stakingToken = IERC20(_stakingToken);
    }
    
    /**
     * @notice Stakes tokens for a specified lock duration
     * @dev Users can add to existing stakes but cannot reduce lock duration
     * @param _amount Amount of tokens to stake
     * @param _lockDuration Duration to lock tokens (minimum 180 days)
     */
    function stake(uint256 _amount, uint256 _lockDuration) external nonReentrant whenNotPaused {
        require(_amount > 0, "Amount must be > 0");
        require(_lockDuration >= MINIMUM_STAKE_DURATION, "Minimum lock is 6 months");
        require(_lockDuration <= MAXIMUM_STAKE_DURATION, "Maximum lock is 2 years");
        
        Stake storage userStake = stakes[msg.sender];
        
        if (userStake.amount > 0) {
            _updatePoints(msg.sender);
            require(_lockDuration >= userStake.lockDuration, "Cannot reduce lock duration");
            userStake.lockDuration = _lockDuration;
        } else {
            userStake.startTime = block.timestamp;
            userStake.lastClaimTime = block.timestamp;
            userStake.lockDuration = _lockDuration;
        }
        
        // Effects
        userStake.amount += _amount;
        totalStaked += _amount;
        
        // Interactions
        stakingToken.safeTransferFrom(msg.sender, address(this), _amount);
        uint256 multiplier = _getMultiplier(_lockDuration);
        uint256 unlockTime = userStake.startTime + userStake.lockDuration;
        
        emit Staked(
            msg.sender, 
            _amount, 
            userStake.amount,
            _lockDuration,
            unlockTime,
            multiplier
        );
    }
    
    /**
     * @notice Withdraws staked tokens after lock period has ended
     * @dev Also claims any accumulated points before withdrawal
     */
    function withdraw() external nonReentrant {
        Stake storage userStake = stakes[msg.sender];
        require(userStake.amount > 0, "No stake found");
        require(
            block.timestamp >= userStake.startTime + userStake.lockDuration,
            "Still locked"
        );
        
        _updatePoints(msg.sender);
        
        uint256 amount = userStake.amount;
        uint256 points = userStake.accumulatedPoints;
        
        // Effects
        if (points > 0) {
            claimedPoints[msg.sender] += points;
        }
        
        totalStaked -= amount;
        uint256 stakeDuration = block.timestamp - userStake.startTime;
        delete stakes[msg.sender];
        
        // Interactions
        stakingToken.safeTransfer(msg.sender, amount);
        emit Withdrawn(
            msg.sender, 
            amount, 
            points,
            claimedPoints[msg.sender],
            stakeDuration
        );
    }
    
    /**
     * @notice Claims accumulated points without withdrawing stake
     * @dev Points are moved from accumulated to claimed status
     */
    function claimPoints() external nonReentrant {
        require(stakes[msg.sender].amount > 0, "No stake found");
        _updatePoints(msg.sender);
        
        uint256 points = stakes[msg.sender].accumulatedPoints;
        stakes[msg.sender].accumulatedPoints = 0;
        claimedPoints[msg.sender] += points;
        
        emit PointsClaimed(msg.sender, points, claimedPoints[msg.sender]);
    }
    
    /**
     * @notice Internal function to calculate and update user's accumulated points
     * @dev Called before any stake modification or point claim
     * @param _user Address of the user to update points for
     */
    function _updatePoints(address _user) internal {
        Stake storage userStake = stakes[_user];
        if (userStake.amount == 0) return;
        
        uint256 timeElapsed = block.timestamp - userStake.lastClaimTime;
        if (timeElapsed == 0) return;
        
        uint256 multiplier = _getMultiplier(userStake.lockDuration);
        uint256 newPoints = (userStake.amount * timeElapsed * BASE_POINTS_RATE * multiplier) / (1 days * 100);
        
        userStake.accumulatedPoints += newPoints;
        userStake.lastClaimTime = block.timestamp;
        
        if (newPoints > 0) {
            emit PointsAccrued(_user, newPoints, block.timestamp);
        }
    }
    
    /**
     * @notice Calculates the points multiplier based on lock duration
     * @dev Longer lock durations receive higher multipliers
     * @param _lockDuration The duration tokens are locked for
     * @return The multiplier value (100 = 1x, 200 = 2x)
     */
    function _getMultiplier(uint256 _lockDuration) internal pure returns (uint256) {
        if (_lockDuration >= 365 days) return 200; // 2x multiplier
        if (_lockDuration >= 270 days) return 150; // 1.5x multiplier
        if (_lockDuration >= 180 days) return 100; // 1x multiplier
        return 100;
    }
    
    /**
     * @notice Returns comprehensive staking information for a user
     * @param _user Address to query stake information for
     * @return amount Amount of tokens staked
     * @return startTime Timestamp when stake was created
     * @return lockDuration Duration of the lock period
     * @return currentPoints Total points (accumulated + pending)
     * @return canWithdraw Whether the stake can be withdrawn
     */
    function getStakeInfo(address _user) external view returns (
        uint256 amount,
        uint256 startTime,
        uint256 lockDuration,
        uint256 currentPoints,
        bool canWithdraw
    ) {
        Stake memory userStake = stakes[_user];
        amount = userStake.amount;
        startTime = userStake.startTime;
        lockDuration = userStake.lockDuration;
        
        if (amount > 0) {
            uint256 timeElapsed = block.timestamp - userStake.lastClaimTime;
            uint256 multiplier = _getMultiplier(userStake.lockDuration);
            uint256 pendingPoints = (amount * timeElapsed * BASE_POINTS_RATE * multiplier) / (1 days * 100);
            currentPoints = userStake.accumulatedPoints + pendingPoints;
        }
        
        canWithdraw = amount > 0 && block.timestamp >= startTime + lockDuration;
    }
    
    /**
     * @notice Queues the points redeemer update for timelock
     * @dev Only callable by contract owner
     * @param _redeemer Address of the points redeemer contract
     */
    function queueSetPointsRedeemer(address _redeemer) external onlyOwner {
        bytes32 functionId = keccak256(abi.encodePacked("setPointsRedeemer", _redeemer));
        timelockExecutions[functionId] = block.timestamp + TIMELOCK_DELAY;
        emit TimelockQueued(functionId, block.timestamp + TIMELOCK_DELAY);
    }
    
    /**
     * @notice Executes the queued points redeemer update after timelock
     * @param _redeemer Address of the points redeemer contract
     */
    function executeSetPointsRedeemer(address _redeemer) external onlyOwner {
        bytes32 functionId = keccak256(abi.encodePacked("setPointsRedeemer", _redeemer));
        require(timelockExecutions[functionId] != 0, "Not queued");
        require(block.timestamp >= timelockExecutions[functionId], "Timelock not expired");
        
        delete timelockExecutions[functionId];
        pointsRedeemer = _redeemer;
        
        emit TimelockExecuted(functionId);
        emit PointsRedeemerSet(_redeemer);
    }
    
    /**
     * @notice Cancels a queued timelock operation
     * @param _functionId The function identifier to cancel
     */
    function cancelTimelock(bytes32 _functionId) external onlyOwner {
        require(timelockExecutions[_functionId] != 0, "Not queued");
        delete timelockExecutions[_functionId];
        emit TimelockCancelled(_functionId);
    }
    
    /**
     * @notice Returns the total claimed points for a user
     * @param _user Address to query claimed points for
     * @return Total claimed points available for redemption
     */
    function getClaimedPoints(address _user) external view returns (uint256) {
        return claimedPoints[_user];
    }
    
    /**
     * @notice Redeems points for a user (only callable by authorized redeemer)
     * @dev Reduces the user's claimed points balance
     * @param _user Address of the user redeeming points
     * @param _amount Amount of points to redeem
     */
    function redeemPoints(address _user, uint256 _amount) external nonReentrant {
        require(msg.sender == pointsRedeemer, "Not authorized");
        require(claimedPoints[_user] >= _amount, "Insufficient points");
        
        // Effects before external calls
        claimedPoints[_user] -= _amount;
        emit PointsRedeemed(_user, msg.sender, _amount);
    }
    
    /**
     * @notice Pauses all staking operations
     * @dev Only callable by owner in emergency situations
     */
    function pause() external onlyOwner {
        _pause();
    }
    
    /**
     * @notice Unpauses all staking operations
     * @dev Only callable by owner
     */
    function unpause() external onlyOwner {
        _unpause();
    }
    
    /**
     * @notice Emergency function to recover accidentally sent tokens
     * @dev Only callable by owner after timelock, cannot withdraw staking token
     * @param _token Address of the token to recover
     * @param _amount Amount to recover
     */
    function queueRecoverToken(address _token, uint256 _amount) external onlyOwner {
        require(_token != address(stakingToken), "Cannot recover staking token");
        bytes32 functionId = keccak256(abi.encodePacked("recoverToken", _token, _amount));
        timelockExecutions[functionId] = block.timestamp + TIMELOCK_DELAY;
        emit TimelockQueued(functionId, block.timestamp + TIMELOCK_DELAY);
    }
    
    /**
     * @notice Executes the queued token recovery after timelock
     * @param _token Address of the token to recover
     * @param _amount Amount to recover
     */
    function executeRecoverToken(address _token, uint256 _amount) external onlyOwner {
        require(_token != address(stakingToken), "Cannot recover staking token");
        bytes32 functionId = keccak256(abi.encodePacked("recoverToken", _token, _amount));
        require(timelockExecutions[functionId] != 0, "Not queued");
        require(block.timestamp >= timelockExecutions[functionId], "Timelock not expired");
        
        delete timelockExecutions[functionId];
        IERC20(_token).safeTransfer(owner(), _amount);
        
        emit TimelockExecuted(functionId);
    }
}