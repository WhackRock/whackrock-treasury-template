// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @notice Interface for interacting with the WROCKStaking contract
 */
interface IWROCKStaking {
    /**
     * @notice Gets the claimed points balance for a user
     * @param user Address to query
     * @return The user's claimed points balance
     */
    function getClaimedPoints(address user) external view returns (uint256);
    
    /**
     * @notice Redeems points from a user's balance
     * @param user Address of the user
     * @param amount Amount of points to redeem
     */
    function redeemPoints(address user, uint256 amount) external;
}

/**
 * @title PointsRedeemer
 * @author WROCK Team
 * @notice This contract handles the redemption of staking points for reward tokens
 * @dev Integrates with WROCKStaking to verify and deduct points, then distributes rewards
 * The owner can configure reward tokens, redemption rates, and enable/disable redemptions
 */
contract PointsRedeemer is Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;
    /// @notice Reference to the WROCKStaking contract
    IWROCKStaking public immutable stakingContract;
    
    /// @notice The ERC20 token distributed as rewards
    IERC20 public rewardToken;
    
    /// @notice Exchange rate: how many tokens per point (default: 1 point = 1 token)
    uint256 public redemptionRate = 1;
    
    /// @notice Whether point redemption is currently enabled
    bool public redemptionEnabled = false;
    
    /// @notice Timelock delay for sensitive owner functions (48 hours)
    uint256 public constant TIMELOCK_DELAY = 48 hours;
    
    /// @notice Mapping of function to pending timelock execution
    mapping(bytes32 => uint256) public timelockExecutions;
    
    /**
     * @notice Emitted when a user redeems points for tokens
     * @param user Address of the user redeeming points
     * @param points Amount of points redeemed
     * @param tokens Amount of tokens received
     * @param remainingPoints User's remaining points balance
     * @param rewardToken Address of the reward token distributed
     */
    event PointsRedeemed(
        address indexed user, 
        uint256 points, 
        uint256 tokens,
        uint256 remainingPoints,
        address indexed rewardToken
    );
    /**
     * @notice Emitted when the redemption rate is updated
     * @param oldRate Previous redemption rate
     * @param newRate New redemption rate
     */
    event RedemptionRateUpdated(
        uint256 oldRate,
        uint256 newRate
    );
    /**
     * @notice Emitted when redemption is enabled or disabled
     * @param enabled New redemption status
     */
    event RedemptionToggled(bool enabled);
    /**
     * @notice Emitted when the reward token is changed
     * @param oldToken Previous reward token address
     * @param newToken New reward token address
     */
    event RewardTokenUpdated(
        address indexed oldToken,
        address indexed newToken
    );
    /**
     * @notice Emitted when reward tokens are deposited
     * @param token Address of the deposited token
     * @param amount Amount of tokens deposited
     * @param newBalance New contract balance after deposit
     */
    event TokensDeposited(
        address indexed token,
        uint256 amount,
        uint256 newBalance
    );
    /**
     * @notice Emitted when tokens are withdrawn by owner
     * @param token Address of the withdrawn token
     * @param amount Amount of tokens withdrawn
     * @param to Recipient address (owner)
     */
    event TokensWithdrawn(
        address indexed token,
        uint256 amount,
        address indexed to
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
     * @notice Initializes the redeemer with the staking contract address
     * @param _stakingContract Address of the WROCKStaking contract
     */
    constructor(address _stakingContract) Ownable(msg.sender) {
        stakingContract = IWROCKStaking(_stakingContract);
    }
    
    /**
     * @notice Redeems points for reward tokens at the current redemption rate
     * @dev Checks points balance via staking contract and transfers reward tokens
     * @param _pointsAmount Amount of points to redeem
     */
    function redeemPoints(uint256 _pointsAmount) external nonReentrant whenNotPaused {
        require(redemptionEnabled, "Redemption not enabled");
        require(address(rewardToken) != address(0), "Reward token not set");
        require(_pointsAmount > 0, "Amount must be > 0");
        
        uint256 availablePoints = stakingContract.getClaimedPoints(msg.sender);
        require(availablePoints >= _pointsAmount, "Insufficient points");
        
        // Calculate tokens to transfer
        uint256 tokensToTransfer = _pointsAmount * redemptionRate;
        uint256 contractBalance = rewardToken.balanceOf(address(this));
        require(contractBalance >= tokensToTransfer, "Insufficient reward tokens");
        
        // Effects before interactions
        stakingContract.redeemPoints(msg.sender, _pointsAmount);
        
        // Get remaining points before transfer (in case of reentrancy)
        uint256 remainingPoints = stakingContract.getClaimedPoints(msg.sender);
        
        // Interactions
        rewardToken.safeTransfer(msg.sender, tokensToTransfer);
        
        emit PointsRedeemed(
            msg.sender, 
            _pointsAmount, 
            tokensToTransfer,
            remainingPoints,
            address(rewardToken)
        );
    }
    
    /**
     * @notice Queues the reward token update for timelock
     * @dev Only callable by owner
     * @param _token Address of the new reward token
     */
    function queueSetRewardToken(address _token) external onlyOwner {
        require(_token != address(0), "Invalid token address");
        bytes32 functionId = keccak256(abi.encodePacked("setRewardToken", _token));
        timelockExecutions[functionId] = block.timestamp + TIMELOCK_DELAY;
        emit TimelockQueued(functionId, block.timestamp + TIMELOCK_DELAY);
    }
    
    /**
     * @notice Executes the queued reward token update after timelock
     * @param _token Address of the new reward token
     */
    function executeSetRewardToken(address _token) external onlyOwner {
        require(_token != address(0), "Invalid token address");
        bytes32 functionId = keccak256(abi.encodePacked("setRewardToken", _token));
        require(timelockExecutions[functionId] != 0, "Not queued");
        require(block.timestamp >= timelockExecutions[functionId], "Timelock not expired");
        
        delete timelockExecutions[functionId];
        address oldToken = address(rewardToken);
        rewardToken = IERC20(_token);
        
        emit TimelockExecuted(functionId);
        emit RewardTokenUpdated(oldToken, _token);
    }
    
    /**
     * @notice Queues the redemption rate update for timelock
     * @dev Only callable by owner
     * @param _rate New redemption rate (tokens per point)
     */
    function queueSetRedemptionRate(uint256 _rate) external onlyOwner {
        require(_rate > 0, "Rate must be > 0");
        bytes32 functionId = keccak256(abi.encodePacked("setRedemptionRate", _rate));
        timelockExecutions[functionId] = block.timestamp + TIMELOCK_DELAY;
        emit TimelockQueued(functionId, block.timestamp + TIMELOCK_DELAY);
    }
    
    /**
     * @notice Executes the queued redemption rate update after timelock
     * @param _rate New redemption rate (tokens per point)
     */
    function executeSetRedemptionRate(uint256 _rate) external onlyOwner {
        require(_rate > 0, "Rate must be > 0");
        bytes32 functionId = keccak256(abi.encodePacked("setRedemptionRate", _rate));
        require(timelockExecutions[functionId] != 0, "Not queued");
        require(block.timestamp >= timelockExecutions[functionId], "Timelock not expired");
        
        delete timelockExecutions[functionId];
        uint256 oldRate = redemptionRate;
        redemptionRate = _rate;
        
        emit TimelockExecuted(functionId);
        emit RedemptionRateUpdated(oldRate, _rate);
    }
    
    /**
     * @notice Toggles whether redemption is enabled or disabled
     * @dev Only callable by owner
     */
    function toggleRedemption() external onlyOwner {
        redemptionEnabled = !redemptionEnabled;
        emit RedemptionToggled(redemptionEnabled);
    }
    
    /**
     * @notice Withdraws tokens from the contract to the owner
     * @dev Only callable by owner, for emergency recovery
     * @param _token Address of the token to withdraw
     * @param _amount Amount of tokens to withdraw
     */
    function withdrawTokens(address _token, uint256 _amount) external onlyOwner nonReentrant {
        require(_token != address(0), "Invalid token");
        IERC20(_token).safeTransfer(owner(), _amount);
        emit TokensWithdrawn(_token, _amount, owner());
    }
    
    /**
     * @notice Calculates how many tokens a user can redeem with their points
     * @param _user Address to check
     * @return Amount of tokens redeemable at current rate
     */
    function checkRedeemableTokens(address _user) external view returns (uint256) {
        uint256 points = stakingContract.getClaimedPoints(_user);
        return points * redemptionRate;
    }
    
    /**
     * @notice Deposits reward tokens into the contract
     * @dev Only callable by owner, requires reward token to be set
     * @param _amount Amount of reward tokens to deposit
     */
    function depositRewardTokens(uint256 _amount) external onlyOwner nonReentrant {
        require(address(rewardToken) != address(0), "Reward token not set");
        require(_amount > 0, "Amount must be > 0");
        
        // Interactions
        rewardToken.safeTransferFrom(msg.sender, address(this), _amount);
        
        uint256 balanceAfter = rewardToken.balanceOf(address(this));
        emit TokensDeposited(address(rewardToken), _amount, balanceAfter);
    }
    
    /**
     * @notice Returns the current balance of reward tokens in the contract
     * @return Current reward token balance
     */
    function getRewardBalance() external view returns (uint256) {
        if (address(rewardToken) == address(0)) return 0;
        return rewardToken.balanceOf(address(this));
    }
    
    /**
     * @notice Prevents accidental ETH transfers to the contract
     * @dev Reverts any ETH sent directly to the contract
     */
    receive() external payable {
        revert("ETH not accepted");
    }
    
    /**
     * @notice Pauses all redemption operations
     * @dev Only callable by owner in emergency situations
     */
    function pause() external onlyOwner {
        _pause();
    }
    
    /**
     * @notice Unpauses all redemption operations
     * @dev Only callable by owner
     */
    function unpause() external onlyOwner {
        _unpause();
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
}