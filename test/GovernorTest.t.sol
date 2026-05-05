// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {
    TimelockController
} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";

import {GovernanceToken} from "../src/GovernanceToken.sol";
import {MyGovernor} from "../src/MyGovernor.sol";
import {Box} from "../src/Box.sol";
import {Treasury} from "../src/Treasury.sol";

// Tests for the Governor and Timelock logic
contract GovernorTest is Test {
    GovernanceToken token;
    TimelockController timelock;
    MyGovernor governor;
    Box box;
    Treasury treasury;

    // Test addresses
    address deployer = makeAddr("deployer");
    address alice = makeAddr("alice"); // Proposer and main voter
    address bob = makeAddr("bob"); // Delegator
    address carol = makeAddr("carol"); // Against voter
    address recipient = makeAddr("recipient");

    // Governance parameters
    uint256 constant VOTING_DELAY = 7_200;
    uint256 constant VOTING_PERIOD = 50_400;
    uint256 constant TIMELOCK_DELAY = 2 days;
    uint256 constant TOTAL_SUPPLY = 100_000_000e18;
    uint256 constant PROPOSAL_THRESHOLD = 1_000_000e18;
    uint256 constant QUORUM_FRACTION = 4;

    // ─── Setup ────────────────────────────────────────────────────────────────
    function setUp() public {
        vm.startPrank(deployer);

        // 1. Deploy GovernanceToken (используем твой 4-аргументный конструктор)
        address vestingPlaceholder = deployer;
        address treasuryPlaceholder = makeAddr("treasuryPlaceholder");
        address communityPlaceholder = makeAddr("communityPlaceholder");
        address liquidityPlaceholder = makeAddr("liquidityPlaceholder");

        token = new GovernanceToken(
            vestingPlaceholder,
            treasuryPlaceholder,
            communityPlaceholder,
            liquidityPlaceholder
        );

        // 2. Deploy Timelock
        address[] memory empty = new address[](0);
        timelock = new TimelockController(
            TIMELOCK_DELAY,
            empty,
            empty,
            deployer
        );

        // 3. Deploy Governor
        governor = new MyGovernor(token, timelock);

        // 4. Grant roles
        bytes32 PROPOSER_ROLE = timelock.PROPOSER_ROLE();
        bytes32 EXECUTOR_ROLE = timelock.EXECUTOR_ROLE();
        bytes32 CANCELLER_ROLE = timelock.CANCELLER_ROLE();

        timelock.grantRole(PROPOSER_ROLE, address(governor));
        timelock.grantRole(EXECUTOR_ROLE, address(0));
        timelock.grantRole(CANCELLER_ROLE, address(governor));

        // 5. Revoke admin
        timelock.revokeRole(timelock.DEFAULT_ADMIN_ROLE(), deployer);

        // 6. Deploy Box и Treasury
        box = new Box(address(timelock));
        treasury = new Treasury(address(timelock));

        // 7. Раздаём тестовые токены
        uint256 aliceAmt = (TOTAL_SUPPLY * 5) / 100; // 5M GOV
        uint256 bobAmt = (TOTAL_SUPPLY * 3) / 100; // 3M GOV
        uint256 carolAmt = (TOTAL_SUPPLY * 2) / 100; // 2M GOV
        uint256 treasuryAmt = (TOTAL_SUPPLY * 10) / 100;

        token.transfer(alice, aliceAmt);
        token.transfer(bob, bobAmt);
        token.transfer(carol, carolAmt);
        token.transfer(address(treasury), treasuryAmt);

        vm.stopPrank();

        // 8. Fund treasury ETH
        vm.deal(address(treasury), 10 ether);

        // 9. Самоделегирование (ОБЯЗАТЕЛЬНО!)
        vm.prank(alice);
        token.delegate(alice);
        vm.prank(bob);
        token.delegate(bob);
        vm.prank(carol);
        token.delegate(carol);

        // КРИТИЧНО: делаем так, чтобы чекпоинт делегирования стал видимым
        vm.roll(block.number + 1);

        console.log("=== SETUP COMPLETED ===");
        console.log("Alice votes:", token.getVotes(alice) / 1e18, "GOV");
    }

    //  Helper Functions

    function _buildBoxProposal(
        uint256 value,
        string memory description
    )
        internal
        view
        returns (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,
            string memory desc
        )
    {
        targets = new address[](1);
        values = new uint256[](1);
        calldatas = new bytes[](1);
        targets[0] = address(box);
        values[0] = 0;
        calldatas[0] = abi.encodeWithSignature("store(uint256)", value);
        desc = description;
    }

    function _runFullLifecycle(
        address proposer,
        address voter,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory desc
    ) internal returns (uint256 proposalId) {
        vm.prank(proposer);
        proposalId = governor.propose(targets, values, calldatas, desc);

        vm.roll(block.number + VOTING_DELAY + 1);

        vm.prank(voter);
        governor.castVote(proposalId, 1); // Vote For

        vm.roll(block.number + VOTING_PERIOD + 1);

        bytes32 descHash = keccak256(bytes(desc));
        governor.queue(targets, values, calldatas, descHash);

        vm.warp(block.timestamp + TIMELOCK_DELAY + 1);
        governor.execute(targets, values, calldatas, descHash);
    }

    //  Tests

    function test_InitialParameters() public view {
        assertEq(governor.votingDelay(), VOTING_DELAY);
        assertEq(governor.votingPeriod(), VOTING_PERIOD);
        assertEq(governor.proposalThreshold(), PROPOSAL_THRESHOLD);
        assertEq(timelock.getMinDelay(), TIMELOCK_DELAY);
    }

    function test_VotingPowerRequiresDelegation() public {
        address newUser = makeAddr("newUser");
        vm.prank(deployer);
        token.transfer(newUser, 1000e18);

        assertEq(
            token.getVotes(newUser),
            0,
            "Should have 0 votes before delegation"
        );

        vm.prank(newUser);
        token.delegate(newUser);
        assertEq(
            token.getVotes(newUser),
            1000e18,
            "Should have votes after self-delegation"
        );
    }

    function test_GovernanceUpdatesBoxValue() public {
        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,
            string memory desc
        ) = _buildBoxProposal(42, "Store 42");

        _runFullLifecycle(alice, alice, targets, values, calldatas, desc);
        assertEq(box.retrieve(), 42);
    }

// =========================================================================
// T07 - Proposal Failure: Quorum Not Reached
// =========================================================================
function test_ProposalFailsIfQuorumNotMet() public {
    console.log("=== T07: Proposal Failure - Quorum Not Met ===");

    // Give a small voter just enough to propose (1% threshold)
    address smallProposer = makeAddr("smallProposer");
    vm.prank(deployer);
    token.transfer(smallProposer, PROPOSAL_THRESHOLD + 1e18);

    vm.prank(smallProposer);
    token.delegate(smallProposer);

    // КРИТИЧНО: продвигаем блок, чтобы чекпоинт делегирования стал видимым
    vm.roll(block.number + 1);

    (
        address[] memory targets,
        uint256[] memory values,
        bytes[]   memory calldatas,
        string    memory desc
    ) = _buildBoxProposal(99, "Proposal #4: Should fail - quorum not met");

    vm.prank(smallProposer);
    uint256 proposalId = governor.propose(targets, values, calldatas, desc);

    // Advance past voting delay
    vm.roll(block.number + VOTING_DELAY + 1);
    assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Active));

    // smallProposer votes For - but only ~1% voting power
    vm.prank(smallProposer);
    governor.castVote(proposalId, 1);

    // Advance past voting period
    vm.roll(block.number + VOTING_PERIOD + 1);

    IGovernor.ProposalState finalState = governor.state(proposalId);
    assertEq(
        uint256(finalState),
        uint256(IGovernor.ProposalState.Defeated),
        "Proposal should be Defeated (quorum not met)"
    );

    console.log("  smallProposer votes:", (PROPOSAL_THRESHOLD + 1e18) / 1e18, "GOV");
    console.log("  proposal state: Defeated (quorum not met)");
    console.log("PASS");
}

    function test_ProposeRevertsIfBelowThreshold() public {
        address poorUser = makeAddr("poor");
        vm.prank(deployer);
        token.transfer(poorUser, PROPOSAL_THRESHOLD - 1);
        vm.prank(poorUser);
        token.delegate(poorUser);

        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,
            string memory desc
        ) = _buildBoxProposal(1, "Below threshold");

        vm.prank(poorUser);
        vm.expectRevert();
        governor.propose(targets, values, calldatas, desc);
    }

    function test_DelegatedVotingPower() public {
        // Bob delegates to Alice
        vm.prank(bob);
        token.delegate(alice);
        vm.roll(block.number + 1);

        uint256 aliceVotes = token.getVotes(alice);
        // Alice should now have her 5M + Bob's 3M
        assertEq(aliceVotes, 8_000_000e18);
        assertEq(token.getVotes(bob), 0);
    }

    function test_TimelockExecutionEnforcement() public {
        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,
            string memory desc
        ) = _buildBoxProposal(100, "Timelock test");

        vm.prank(alice);
        uint256 pId = governor.propose(targets, values, calldatas, desc);

        vm.roll(block.number + VOTING_DELAY + 1);
        vm.prank(alice);
        governor.castVote(pId, 1);
        vm.roll(block.number + VOTING_PERIOD + 1);

        bytes32 descHash = keccak256(bytes(desc));
        governor.queue(targets, values, calldatas, descHash);

        // Try to execute before 2 days have passed
        vm.warp(block.timestamp + TIMELOCK_DELAY - 1);
        vm.expectRevert();
        governor.execute(targets, values, calldatas, descHash);
    }
}
