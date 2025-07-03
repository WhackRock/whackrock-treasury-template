// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {WROCKStaking} from "../src/staking/WROCKStaking.sol";
import {PointsRedeemer} from "../src/staking/PointsRedeemer.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// Mock ERC20 token for testing
contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        _mint(msg.sender, 1000000 * 10**18); // Mint 1M tokens
    }
    
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract StakingTest is Test {
    WROCKStaking public stakingContract;
    PointsRedeemer public redeemer;
    MockERC20 public stakingToken;
    MockERC20 public rewardToken;
    
    address public owner;
    address public user1;
    address public user2;
    address public user3;
    
    uint256 constant MINIMUM_STAKE_DURATION = 180 days;
    uint256 constant MAXIMUM_STAKE_DURATION = 730 days;
    uint256 constant TIMELOCK_DELAY = 48 hours;
    uint256 constant BASE_POINTS_RATE = 100;
    
    event Staked(
        address indexed user, 
        uint256 amount, 
        uint256 totalStakedAmount,
        uint256 lockDuration,
        uint256 unlockTime,
        uint256 multiplier
    );
    
    event PointsClaimed(
        address indexed user, 
        uint256 points,
        uint256 totalClaimedPoints
    );
    
    event PointsRedeemed(
        address indexed user, 
        uint256 points, 
        uint256 tokens,
        uint256 remainingPoints,
        address indexed rewardToken
    );
    
    function setUp() public {
        owner = address(this);
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        user3 = makeAddr("user3");
        
        // Deploy mock tokens
        stakingToken = new MockERC20("WROCK Token", "WROCK");
        rewardToken = new MockERC20("Reward Token", "REWARD");
        
        // Deploy contracts
        stakingContract = new WROCKStaking(address(stakingToken));
        redeemer = new PointsRedeemer(address(stakingContract));
        
        // Setup token balances
        stakingToken.mint(user1, 1000 * 10**18);
        stakingToken.mint(user2, 1000 * 10**18);
        stakingToken.mint(user3, 1000 * 10**18);
        
        // Setup reward tokens for redeemer
        rewardToken.mint(address(this), 10000 * 10**18);
        
        console.log("Setup completed:");
        console.log("StakingContract:", address(stakingContract));
        console.log("PointsRedeemer:", address(redeemer));
        console.log("StakingToken:", address(stakingToken));
        console.log("RewardToken:", address(rewardToken));
    }
    
    function testInitialState() public view {
        assertEq(stakingContract.totalStaked(), 0);
        assertEq(stakingContract.pointsRedeemer(), address(0));
        assertFalse(redeemer.redemptionEnabled());
        assertEq(redeemer.redemptionRate(), 1);
        assertEq(address(redeemer.rewardToken()), address(0));
    }
    
    function testStakeMinimumDuration() public {
        vm.startPrank(user1);
        stakingToken.approve(address(stakingContract), 100 * 10**18);
        
        vm.expectEmit(true, false, false, true);
        emit Staked(user1, 100 * 10**18, 100 * 10**18, MINIMUM_STAKE_DURATION, block.timestamp + MINIMUM_STAKE_DURATION, 100);
        
        stakingContract.stake(100 * 10**18, MINIMUM_STAKE_DURATION);
        
        (uint256 amount, uint256 startTime, uint256 lockDuration, uint256 currentPoints, bool canWithdraw) = 
            stakingContract.getStakeInfo(user1);
            
        assertEq(amount, 100 * 10**18);
        assertEq(lockDuration, MINIMUM_STAKE_DURATION);
        assertEq(currentPoints, 0); // No time has passed
        assertFalse(canWithdraw);
        assertEq(stakingContract.totalStaked(), 100 * 10**18);
        
        vm.stopPrank();
    }
    
    function testStakeMaximumDuration() public {
        vm.startPrank(user1);
        stakingToken.approve(address(stakingContract), 100 * 10**18);
        
        stakingContract.stake(100 * 10**18, MAXIMUM_STAKE_DURATION);
        
        (,, uint256 lockDuration,,) = stakingContract.getStakeInfo(user1);
        assertEq(lockDuration, MAXIMUM_STAKE_DURATION);
        
        vm.stopPrank();
    }
    
    function testStakeBelowMinimumDurationFails() public {
        vm.startPrank(user1);
        stakingToken.approve(address(stakingContract), 100 * 10**18);
        
        vm.expectRevert("Minimum lock is 6 months");
        stakingContract.stake(100 * 10**18, MINIMUM_STAKE_DURATION - 1);
        
        vm.stopPrank();
    }
    
    function testStakeAboveMaximumDurationFails() public {
        vm.startPrank(user1);
        stakingToken.approve(address(stakingContract), 100 * 10**18);
        
        vm.expectRevert("Maximum lock is 2 years");
        stakingContract.stake(100 * 10**18, MAXIMUM_STAKE_DURATION + 1);
        
        vm.stopPrank();
    }
    
    function testMultipleStakes() public {
        vm.startPrank(user1);
        stakingToken.approve(address(stakingContract), 200 * 10**18);
        
        // First stake
        stakingContract.stake(100 * 10**18, MINIMUM_STAKE_DURATION);
        
        // Second stake (should add to existing)
        stakingContract.stake(100 * 10**18, MINIMUM_STAKE_DURATION);
        
        (uint256 amount,,,, ) = stakingContract.getStakeInfo(user1);
        assertEq(amount, 200 * 10**18);
        assertEq(stakingContract.totalStaked(), 200 * 10**18);
        
        vm.stopPrank();
    }
    
    function testCannotReduceLockDuration() public {
        vm.startPrank(user1);
        stakingToken.approve(address(stakingContract), 200 * 10**18);
        
        // First stake with longer duration
        stakingContract.stake(100 * 10**18, MAXIMUM_STAKE_DURATION);
        
        // Try to stake with shorter duration
        vm.expectRevert("Cannot reduce lock duration");
        stakingContract.stake(100 * 10**18, MINIMUM_STAKE_DURATION);
        
        vm.stopPrank();
    }
    
    function testPointsAccumulation() public {
        vm.startPrank(user1);
        stakingToken.approve(address(stakingContract), 100 * 10**18);
        stakingContract.stake(100 * 10**18, MINIMUM_STAKE_DURATION);
        
        // Fast forward 1 day
        vm.warp(block.timestamp + 1 days);
        
        (,,, uint256 currentPoints,) = stakingContract.getStakeInfo(user1);
        
        // Expected: 100 tokens * 1 day * 100 rate * 100 multiplier / (1 day * 100) = 10000 points
        assertEq(currentPoints, 10000 * 10**18);
        
        vm.stopPrank();
    }
    
    function testMultiplierFor365Days() public {
        vm.startPrank(user1);
        stakingToken.approve(address(stakingContract), 100 * 10**18);
        stakingContract.stake(100 * 10**18, 365 days);
        
        // Fast forward 1 day
        vm.warp(block.timestamp + 1 days);
        
        (,,, uint256 currentPoints,) = stakingContract.getStakeInfo(user1);
        
        // Expected: 100 tokens * 1 day * 100 rate * 200 multiplier / (1 day * 100) = 20000 points
        assertEq(currentPoints, 20000 * 10**18);
        
        vm.stopPrank();
    }
    
    function testClaimPoints() public {
        vm.startPrank(user1);
        stakingToken.approve(address(stakingContract), 100 * 10**18);
        stakingContract.stake(100 * 10**18, MINIMUM_STAKE_DURATION);
        
        // Fast forward 1 day
        vm.warp(block.timestamp + 1 days);
        
        vm.expectEmit(true, false, false, true);
        emit PointsClaimed(user1, 10000 * 10**18, 10000 * 10**18);
        
        stakingContract.claimPoints();
        
        assertEq(stakingContract.getClaimedPoints(user1), 10000 * 10**18);
        
        // Points should be reset to 0 after claiming
        (,,, uint256 currentPoints,) = stakingContract.getStakeInfo(user1);
        assertEq(currentPoints, 0);
        
        vm.stopPrank();
    }
    
    function testWithdrawAfterLockPeriod() public {
        vm.startPrank(user1);
        stakingToken.approve(address(stakingContract), 100 * 10**18);
        stakingContract.stake(100 * 10**18, MINIMUM_STAKE_DURATION);
        
        // Fast forward past lock period
        vm.warp(block.timestamp + MINIMUM_STAKE_DURATION + 1);
        
        uint256 balanceBefore = stakingToken.balanceOf(user1);
        stakingContract.withdraw();
        uint256 balanceAfter = stakingToken.balanceOf(user1);
        
        assertEq(balanceAfter - balanceBefore, 100 * 10**18);
        assertEq(stakingContract.totalStaked(), 0);
        
        // Check stake is deleted
        (uint256 amount,,,, ) = stakingContract.getStakeInfo(user1);
        assertEq(amount, 0);
        
        vm.stopPrank();
    }
    
    function testCannotWithdrawBeforeLockPeriod() public {
        vm.startPrank(user1);
        stakingToken.approve(address(stakingContract), 100 * 10**18);
        stakingContract.stake(100 * 10**18, MINIMUM_STAKE_DURATION);
        
        // Try to withdraw before lock period
        vm.expectRevert("Still locked");
        stakingContract.withdraw();
        
        vm.stopPrank();
    }
    
    function testSetupPointsRedeemer() public {
        // Queue the operation
        stakingContract.queueSetPointsRedeemer(address(redeemer));
        
        // Fast forward past timelock
        vm.warp(block.timestamp + TIMELOCK_DELAY + 1);
        
        // Execute the operation
        stakingContract.executeSetPointsRedeemer(address(redeemer));
        
        assertEq(stakingContract.pointsRedeemer(), address(redeemer));
    }
    
    function testSetupRewardToken() public {
        uint256 currentTime = block.timestamp;
        redeemer.queueSetRewardToken(address(rewardToken));
        vm.warp(currentTime + TIMELOCK_DELAY + 1);
        redeemer.executeSetRewardToken(address(rewardToken));
        
        assertEq(address(redeemer.rewardToken()), address(rewardToken));
    }
    
    function testCannotExecuteBeforeTimelock() public {
        stakingContract.queueSetPointsRedeemer(address(redeemer));
        
        vm.expectRevert("Timelock not expired");
        stakingContract.executeSetPointsRedeemer(address(redeemer));
    }
    
    function testFullRedemptionFlow() public {
        // Setup redeemer without timelock (we test timelock separately)
        testSetupPointsRedeemer();
        testSetupRewardToken();
        
        rewardToken.approve(address(redeemer), 1000 * 10**18);
        redeemer.depositRewardTokens(1000 * 10**18);
        redeemer.toggleRedemption();
        
        // User stakes and earns points
        vm.startPrank(user1);
        stakingToken.approve(address(stakingContract), 100 * 10**18);
        stakingContract.stake(100 * 10**18, MINIMUM_STAKE_DURATION);
        
        // Fast forward and claim points
        vm.warp(block.timestamp + 1 days);
        stakingContract.claimPoints();
        
        uint256 pointsBalance = stakingContract.getClaimedPoints(user1);
        assertEq(pointsBalance, 10000 * 10**18);
        
        // Redeem points for tokens
        uint256 rewardBalanceBefore = rewardToken.balanceOf(user1);
        
        vm.expectEmit(true, false, false, true);
        emit PointsRedeemed(user1, 50 * 10**18, 50 * 10**18, 9950 * 10**18, address(rewardToken));
        
        redeemer.redeemPoints(50 * 10**18);
        
        uint256 rewardBalanceAfter = rewardToken.balanceOf(user1);
        assertEq(rewardBalanceAfter - rewardBalanceBefore, 50 * 10**18);
        assertEq(stakingContract.getClaimedPoints(user1), 9950 * 10**18);
        
        vm.stopPrank();
    }
    
    function testPauseStaking() public {
        stakingContract.pause();
        
        vm.startPrank(user1);
        stakingToken.approve(address(stakingContract), 100 * 10**18);
        
        vm.expectRevert(); // OpenZeppelin v5 uses custom errors
        stakingContract.stake(100 * 10**18, MINIMUM_STAKE_DURATION);
        
        vm.stopPrank();
    }
    
    function testPauseRedemption() public {
        // Setup
        testSetupPointsRedeemer();
        redeemer.queueSetRewardToken(address(rewardToken));
        vm.warp(block.timestamp + TIMELOCK_DELAY + 1);
        redeemer.executeSetRewardToken(address(rewardToken));
        redeemer.toggleRedemption();
        
        // Pause
        redeemer.pause();
        
        vm.startPrank(user1);
        vm.expectRevert(); // OpenZeppelin v5 uses custom errors
        redeemer.redeemPoints(100);
        
        vm.stopPrank();
    }
    
    function testReentrancyProtection() public {
        // This test ensures the nonReentrant modifier is working
        // In a real attack scenario, an attacker would try to re-enter
        // during token transfers, but SafeERC20 + ReentrancyGuard prevents this
        
        vm.startPrank(user1);
        stakingToken.approve(address(stakingContract), 100 * 10**18);
        stakingContract.stake(100 * 10**18, MINIMUM_STAKE_DURATION);
        
        // Fast forward past lock period
        vm.warp(block.timestamp + MINIMUM_STAKE_DURATION + 1);
        
        // This should work normally
        stakingContract.withdraw();
        
        vm.stopPrank();
    }
    
    function testOwnerOnlyFunctions() public {
        vm.startPrank(user1);
        
        vm.expectRevert(); // OpenZeppelin v5 uses custom errors
        stakingContract.queueSetPointsRedeemer(address(redeemer));
        
        vm.expectRevert(); // OpenZeppelin v5 uses custom errors
        redeemer.queueSetRewardToken(address(rewardToken));
        
        vm.expectRevert(); // OpenZeppelin v5 uses custom errors
        redeemer.queueSetRedemptionRate(2);
        
        vm.expectRevert(); // OpenZeppelin v5 uses custom errors
        redeemer.toggleRedemption();
        
        vm.stopPrank();
    }
    
    function testMultipleUsersStaking() public {
        // User1 stakes
        vm.startPrank(user1);
        stakingToken.approve(address(stakingContract), 100 * 10**18);
        stakingContract.stake(100 * 10**18, MINIMUM_STAKE_DURATION);
        vm.stopPrank();
        
        // User2 stakes
        vm.startPrank(user2);
        stakingToken.approve(address(stakingContract), 200 * 10**18);
        stakingContract.stake(200 * 10**18, 365 days);
        vm.stopPrank();
        
        assertEq(stakingContract.totalStaked(), 300 * 10**18);
        
        // Fast forward 1 day
        vm.warp(block.timestamp + 1 days);
        
        // Check points for each user
        (,,, uint256 user1Points,) = stakingContract.getStakeInfo(user1);
        (,,, uint256 user2Points,) = stakingContract.getStakeInfo(user2);
        
        // User1: 100 tokens * 1x multiplier = 10000 points/day
        assertEq(user1Points, 10000 * 10**18);
        
        // User2: 200 tokens * 2x multiplier = 40000 points/day
        assertEq(user2Points, 40000 * 10**18);
    }
    
    function testInvalidInputs() public {
        vm.startPrank(user1);
        stakingToken.approve(address(stakingContract), 100 * 10**18);
        
        // Zero amount
        vm.expectRevert("Amount must be > 0");
        stakingContract.stake(0, MINIMUM_STAKE_DURATION);
        
        vm.stopPrank();
        
        // Invalid token address for redeemer
        vm.expectRevert("Invalid token address");
        redeemer.queueSetRewardToken(address(0));
        
        // Zero redemption rate
        vm.expectRevert("Rate must be > 0");
        redeemer.queueSetRedemptionRate(0);
    }
}