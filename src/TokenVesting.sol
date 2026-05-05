// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

// Contract for releasing tokens over time (vesting)
contract TokenVesting is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Data structure for each person's vesting info
    struct VestingSchedule {
        uint256 totalAmount; // How many tokens they get in total
        uint256 startTime; // When the timer starts
        uint256 duration; // How long the vesting lasts (1 year)
        uint256 released; // Tokens already taken
        bool revoked; // If the owner canceled this schedule
    }

    // Default duration is 1 year
    uint256 public constant VESTING_DURATION = 365 days;

    IERC20  public immutable token;
    address public revokeReceiver;  // Where unvested tokens go if canceled
    uint256 public totalAllocated;  // Total tokens promised to everyone

    mapping(address => VestingSchedule) public schedules;

    event ScheduleCreated(
        address indexed beneficiary,
        uint256 totalAmount,
        uint256 startTime
    );
    event TokensReleased(address indexed beneficiary, uint256 amount);
    event ScheduleRevoked(address indexed beneficiary, uint256 unvestedReturned);
    event RevokeReceiverUpdated(address indexed newReceiver);

    constructor(address _token, address _revokeReceiver) Ownable(msg.sender) {
        require(_token != address(0), "Vesting: zero token");
        require(_revokeReceiver != address(0), "Vesting: zero revokeReceiver");
        token = IERC20(_token);
        revokeReceiver = _revokeReceiver;
    }

    // Admin creates a new vesting plan for someone
    function createSchedule(
        address beneficiary,
        uint256 totalAmount,
        uint256 startTime
    ) external onlyOwner {
        require(beneficiary != address(0), "Vesting: zero beneficiary");
        require(totalAmount > 0, "Vesting: amount is zero");
        require(startTime >= block.timestamp, "Vesting: start in past");
        require(schedules[beneficiary].totalAmount == 0, "Vesting: schedule exists");

        // Make sure the contract actually has enough tokens to cover this
        require(
            token.balanceOf(address(this)) >= totalAllocated + totalAmount,
            "Vesting: insufficient token balance"
        );

        totalAllocated += totalAmount;

        schedules[beneficiary] = VestingSchedule({
            totalAmount : totalAmount,
            startTime : startTime,
            duration : VESTING_DURATION,
            released : 0,
            revoked : false
        });

        emit ScheduleCreated(beneficiary, totalAmount, startTime);
    }

    // Admin can stop a vesting plan and get unvested tokens back
    function revoke(address beneficiary) external onlyOwner {
        VestingSchedule storage s = schedules[beneficiary];
        require(s.totalAmount > 0, "Vesting: no schedule");
        require(!s.revoked, "Vesting: already revoked");

        uint256 vested = _vestedAmount(s);
        uint256 unvested = s.totalAmount - vested;

        totalAllocated -= unvested;

        // Cap the total at what was earned so far
        s.totalAmount = vested;
        s.revoked = true;

        if (unvested > 0) {
            token.safeTransfer(revokeReceiver, unvested);
        }

        emit ScheduleRevoked(beneficiary, unvested);
    }

    // Change where the returned tokens go
    function setRevokeReceiver(address newReceiver) external onlyOwner {
        require(newReceiver != address(0), "Vesting: zero address");
        revokeReceiver = newReceiver;
        emit RevokeReceiverUpdated(newReceiver);
    }

    // Users call this to get their available tokens
    function release() external nonReentrant {
        VestingSchedule storage s = schedules[msg.sender];
        require(s.totalAmount > 0, "Vesting: no schedule");

        uint256 claimable = _vestedAmount(s) - s.released;
        require(claimable > 0, "Vesting: nothing to release");

        s.released += claimable;
        token.safeTransfer(msg.sender, claimable);

        emit TokensReleased(msg.sender, claimable);
    }

    // Check how much is vested for someone
    function vestedAmount(address beneficiary) external view returns (uint256) {
        return _vestedAmount(schedules[beneficiary]);
    }

    // Check how much they can withdraw right now
    function releasable(address beneficiary) external view returns (uint256) {
        VestingSchedule memory s = schedules[beneficiary];
        return _vestedAmount(s) - s.released;
    }

    // Get progress as a number from 0 to 100
    function vestingProgress(address beneficiary) external view returns (uint256) {
        VestingSchedule memory s = schedules[beneficiary];
        if (s.totalAmount == 0 || block.timestamp < s.startTime) return 0;
        if (block.timestamp >= s.startTime + s.duration) return 100;
        return ((block.timestamp - s.startTime) * 100) / s.duration;
    }

    // Returns the whole schedule struct
    function getSchedule(address beneficiary)
        external
        view
        returns (VestingSchedule memory)
    {
        return schedules[beneficiary];
    }

    // Internal math for linear vesting calculation
    function _vestedAmount(VestingSchedule memory s)
        internal
        view
        returns (uint256)
    {
        if (s.totalAmount == 0) return 0;
        if (block.timestamp < s.startTime) return 0;
        if (block.timestamp >= s.startTime + s.duration) return s.totalAmount;
        return (s.totalAmount * (block.timestamp - s.startTime)) / s.duration;
    }
}