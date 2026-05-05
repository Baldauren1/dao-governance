// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/GovernanceToken.sol";
import "../src/TokenVesting.sol";

// Test file for the governance token and vesting logic
contract Part1Test is Test {

    // Contracts we are testing
    GovernanceToken internal token;
    TokenVesting internal vesting;

    // Test addresses
    address internal deployer = makeAddr("deployer");
    address internal treasury  = makeAddr("treasury");
    address internal community = makeAddr("community");
    address internal liquidity = makeAddr("liquidity");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    // Private key for testing permit signatures
    uint256 internal constant ALICE_PK = 0xA11CE;
    address internal aliceSigner; 

    // Amounts for distribution
    uint256 internal constant TOTAL = 100_000_000e18;
    uint256 internal constant TEAM_AMT = 40_000_000e18;
    uint256 internal constant TREAS_AMT = 30_000_000e18;
    uint256 internal constant COMM_AMT = 20_000_000e18;
    uint256 internal constant LIQ_AMT = 10_000_000e18;

    function setUp() public {
        aliceSigner = vm.addr(ALICE_PK);

        vm.startPrank(deployer);

        // Figure out where the vesting contract will live before deploying it
        address predictedVesting = vm.computeCreateAddress(deployer, 1);

        // Deploy token - sends funds to vesting, treasury, etc.
        token = new GovernanceToken(
            predictedVesting,
            treasury,
            community,
            liquidity
        );

        // Deploy vesting contract
        vesting = new TokenVesting(address(token), treasury);

        // Make sure the predicted address matches the real one
        assertEq(address(vesting), predictedVesting, "Address prediction failed");

        vm.stopPrank();
    }

    //  Governance Token Tests 

    // Check if everyone got the right amount of tokens at the start
    function test_01_InitialDistribution() public view {
        assertEq(token.balanceOf(address(vesting)), TEAM_AMT, "40% to vesting");
        assertEq(token.balanceOf(treasury), TREAS_AMT, "30% to treasury");
        assertEq(token.balanceOf(community), COMM_AMT, "20% to community");
        assertEq(token.balanceOf(liquidity), LIQ_AMT, "10% to liquidity");
        assertEq(token.totalSupply(), TOTAL, "total = 100M");
    }

    // Voting power should stay at 0 until the user delegates
    function test_02_VotingPowerZeroBeforeDelegation() public view {
        assertEq(token.getVotes(community), 0, "no votes before delegate");
    }

    // Self-delegation should turn on the voting power
    function test_03_SelfDelegation() public {
        vm.prank(community);
        token.delegate(community);

        assertEq(token.getVotes(community), COMM_AMT, "votes = token balance");
    }

    // Giving voting power to someone else
    function test_04_DelegateToOther() public {
        vm.prank(community);
        token.delegate(alice);

        assertEq(token.getVotes(alice), COMM_AMT, "alice receives votes");
        assertEq(token.getVotes(community), 0, "community loses votes");
    }

    // Moving voting power from one person to another
    function test_05_Redelegation() public {
        vm.prank(community);
        token.delegate(alice);
        assertEq(token.getVotes(alice), COMM_AMT);

        vm.prank(community);
        token.delegate(bob);

        assertEq(token.getVotes(alice), 0, "alice loses votes");
        assertEq(token.getVotes(bob), COMM_AMT, "bob gains votes");
    }

    // Checking if past votes are recorded correctly (snapshots)
    function test_06_PastVotesSnapshot() public {
        vm.prank(community);
        token.delegate(community);

        uint256 snapshotBlock = block.number;

        // Move forward a block and change delegation
        vm.roll(block.number + 1);
        vm.prank(community);
        token.delegate(alice);

        // Snapshot should still show the old voting power
        assertEq(
            token.getPastVotes(community, snapshotBlock),
            COMM_AMT,
            "snapshot unchanged after re-delegation"
        );
    }

    // Checking the total supply snapshot
    function test_07_PastTotalSupply() public {
        uint256 deployBlock = block.number;
        vm.roll(block.number + 5);

        assertEq(
            token.getPastTotalSupply(deployBlock),
            TOTAL,
            "total supply snapshot = 100M"
        );
    }

    // Testing the EIP-2612 permit function (gasless approval)
    function test_08_PermitGaslessApproval() public {
        uint256 permitValue = 500e18;
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = token.nonces(aliceSigner);

        bytes32 PERMIT_TYPEHASH = keccak256(
            "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
        );
        bytes32 structHash = keccak256(
            abi.encode(PERMIT_TYPEHASH, aliceSigner, bob, permitValue, nonce, deadline)
        );
        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", token.DOMAIN_SEPARATOR(), structHash)
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ALICE_PK, digest);

        vm.prank(bob);
        token.permit(aliceSigner, bob, permitValue, deadline, v, r, s);

        assertEq(token.allowance(aliceSigner, bob), permitValue, "allowance set");
        assertEq(token.nonces(aliceSigner), nonce + 1, "nonce incremented");
    }

    // Make sure permit fails if the time has run out
    function test_09_PermitRevertsOnExpiredDeadline() public {
        uint256 deadline = block.timestamp - 1; 
        uint256 nonce = token.nonces(aliceSigner);

        bytes32 PERMIT_TYPEHASH = keccak256(
            "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
        );
        bytes32 structHash = keccak256(
            abi.encode(PERMIT_TYPEHASH, aliceSigner, bob, 1e18, nonce, deadline)
        );
        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", token.DOMAIN_SEPARATOR(), structHash)
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ALICE_PK, digest);

        vm.expectRevert();
        token.permit(aliceSigner, bob, 1e18, deadline, v, r, s);
    }

    //  Token Vesting Tests 

    // Helper function to set up a quick schedule for Alice
    function _createAliceSchedule()
        internal
        returns (uint256 amount, uint256 startTime)
    {
        amount = 1_000e18;
        startTime = block.timestamp + 60;

        vm.prank(deployer);
        vesting.createSchedule(alice, amount, startTime);
    }

    // Check if the schedule is saved with the right numbers
    function test_10_CreateSchedule() public {
        (uint256 amount, uint256 startTime) = _createAliceSchedule();

        TokenVesting.VestingSchedule memory s = vesting.getSchedule(alice);

        assertEq(s.totalAmount, amount, "totalAmount correct");
        assertEq(s.startTime, startTime, "startTime correct");
        assertEq(s.duration, 365 days, "duration = 365 days");
        assertEq(s.released, 0, "nothing released yet");
    }

    // Make sure nothing can be taken out before the start time
    function test_11_NothingVestedBeforeStart() public {
        _createAliceSchedule();
        assertEq(vesting.vestedAmount(alice), 0, "0 vested before start");
        assertEq(vesting.releasable(alice), 0, "0 releasable before start");
    }

    // At the 6-month mark, half the tokens should be available
    function test_12_LinearVesting_HalfwayPoint() public {
        (uint256 amount, uint256 startTime) = _createAliceSchedule();

        vm.warp(startTime + 365 days / 2);

        uint256 vested = vesting.vestedAmount(alice);
        assertApproxEqAbs(vested, amount / 2, 1e18, "~50% vested at 6 months");
    }

    // At the end of the year, everything should be claimable
    function test_13_FullReleaseAtEnd() public {
        (uint256 amount, uint256 startTime) = _createAliceSchedule();

        vm.warp(startTime + 365 days + 1);

        uint256 balBefore = token.balanceOf(alice);
        vm.prank(alice);
        vesting.release();

        assertEq(token.balanceOf(alice) - balBefore, amount, "alice received full amount");
    }

    // Testing a partial withdrawal during the vesting period
    function test_14_PartialReleaseMidVesting() public {
        (uint256 amount, uint256 startTime) = _createAliceSchedule();

        vm.warp(startTime + 365 days / 4); // 3 months in

        vm.prank(alice);
        vesting.release();

        TokenVesting.VestingSchedule memory s = vesting.getSchedule(alice);
        assertApproxEqAbs(s.released, amount / 4, 1e18, "~25% released");
    }

    // Testing the revoke feature (unvested tokens go back to treasury)
    function test_15_RevokeReturnsUnvestedAndVestedStillClaimable() public {
        (uint256 amount, uint256 startTime) = _createAliceSchedule();

        vm.warp(startTime + 365 days / 4); // 3 months in

        uint256 treasuryBefore = token.balanceOf(treasury);

        vm.prank(deployer);
        vesting.revoke(alice);

        // Treasury gets the 75% that wasn't earned yet
        uint256 returned = token.balanceOf(treasury) - treasuryBefore;
        assertApproxEqAbs(returned, (amount * 3) / 4, 1e18, "~75% returned to treasury");

        // Alice should still be able to take the 25% she earned before the revoke
        uint256 aliceBefore = token.balanceOf(alice);
        vm.prank(alice);
        vesting.release(); 
        assertApproxEqAbs(token.balanceOf(alice) - aliceBefore, amount / 4, 1e18);
    }
}