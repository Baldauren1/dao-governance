// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
//part 2
import {Test, console} from "forge-std/Test.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";

import {GovernanceToken} from "../src/GovernanceToken.sol";
import {MyGovernor} from "../src/MyGovernor.sol";
import {Box} from "../src/Box.sol";
import {Treasury} from "../src/Treasury.sol";

contract GovernorTest is Test {
    GovernanceToken token;
    TimelockController timelock;
    MyGovernor governor;
    Box box;
    Treasury treasury;

    address deployer = makeAddr("deployer");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address carol = makeAddr("carol");
    address recipient = makeAddr("recipient");

    uint256 constant VOTING_DELAY = 7_200;
    uint256 constant VOTING_PERIOD = 50_400;
    uint256 constant TIMELOCK_DELAY = 2 days;
    uint256 constant TOTAL_SUPPLY = 100_000_000e18;
    uint256 constant PROPOSAL_THRESHOLD = 1_000_000e18;

    function setUp() public {
        vm.startPrank(deployer);

        token = new GovernanceToken(
            deployer, makeAddr("treasuryPlaceholder"), makeAddr("community"), makeAddr("liquidity")
        );

        address[] memory empty = new address[](0);
        timelock = new TimelockController(TIMELOCK_DELAY, empty, empty, deployer);

        governor = new MyGovernor(token, timelock);

        timelock.grantRole(timelock.PROPOSER_ROLE(), address(governor));
        timelock.grantRole(timelock.EXECUTOR_ROLE(), address(0));
        timelock.grantRole(timelock.CANCELLER_ROLE(), address(governor));

        timelock.revokeRole(timelock.DEFAULT_ADMIN_ROLE(), deployer);

        box = new Box(address(timelock));
        treasury = new Treasury(address(timelock));

        token.transfer(alice, 5_000_000e18);
        token.transfer(bob, 3_000_000e18);
        token.transfer(carol, 2_000_000e18);
        token.transfer(address(treasury), 10_000_000e18);

        vm.stopPrank();

        vm.deal(address(treasury), 10 ether);

        vm.prank(alice);
        token.delegate(alice);
        vm.prank(bob);
        token.delegate(bob);
        vm.prank(carol);
        token.delegate(carol);

        vm.roll(block.number + 1);
    }

    //  HELPERS

    function _buildBoxProposal(uint256 value, string memory desc)
        internal
        view
        returns (address[] memory, uint256[] memory, bytes[] memory, string memory)
    {
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        targets[0] = address(box);
        calldatas[0] = abi.encodeWithSignature("store(uint256)", value);
        return (targets, values, calldatas, desc);
    }

    function _buildFeeProposal(uint256 fee, string memory desc)
        internal
        view
        returns (address[] memory, uint256[] memory, bytes[] memory, string memory)
    {
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        targets[0] = address(box);
        calldatas[0] = abi.encodeWithSignature("setFeePercentage(uint256)", fee);
        return (targets, values, calldatas, desc);
    }

    function _buildTransferProposal(address to, uint256 amount, string memory desc)
        internal
        view
        returns (address[] memory, uint256[] memory, bytes[] memory, string memory)
    {
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        targets[0] = address(treasury);
        calldatas[0] = abi.encodeWithSignature("transferERC20(address,address,uint256)", address(token), to, amount);
        return (targets, values, calldatas, desc);
    }

    function _runFullLifecycle(
        address proposer,
        address voter,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory desc
    ) internal {
        vm.prank(proposer);
        uint256 pid = governor.propose(targets, values, calldatas, desc);

        vm.roll(block.number + VOTING_DELAY + 1);
        vm.prank(voter);
        governor.castVote(pid, 1);

        vm.roll(block.number + VOTING_PERIOD + 1);

        bytes32 descHash = keccak256(bytes(desc));
        governor.queue(targets, values, calldatas, descHash);

        vm.warp(block.timestamp + TIMELOCK_DELAY + 1);
        governor.execute(targets, values, calldatas, descHash);
    }

    //  TESTS (13 тестов)

    function test_InitialParameters() public view {
        assertEq(governor.votingDelay(), VOTING_DELAY);
        assertEq(governor.votingPeriod(), VOTING_PERIOD);
        assertEq(governor.proposalThreshold(), PROPOSAL_THRESHOLD);
        assertEq(governor.quorumNumerator(), 4);
        assertEq(timelock.getMinDelay(), TIMELOCK_DELAY);
    }

    function test_VotingPowerRequiresDelegation() public {
        address user = makeAddr("user");
        vm.prank(deployer);
        token.transfer(user, 1000e18);
        assertEq(token.getVotes(user), 0);

        vm.prank(user);
        token.delegate(user);
        assertEq(token.getVotes(user), 1000e18);
    }

    function test_DelegatedVotingPower() public {
        vm.prank(bob);
        token.delegate(alice);
        vm.roll(block.number + 1);
        assertEq(token.getVotes(alice), 8_000_000e18);
        assertEq(token.getVotes(bob), 0);
    }

    function test_GovernanceUpdatesBoxValue() public {
        (address[] memory t, uint256[] memory v, bytes[] memory c, string memory d) =
            _buildBoxProposal(42, "Update Box");
        _runFullLifecycle(alice, alice, t, v, c, d);
        assertEq(box.retrieve(), 42);
    }

    function test_TreasuryERC20Transfer() public {
        uint256 amount = 1_000_000e18;
        uint256 before = token.balanceOf(recipient);

        (address[] memory t, uint256[] memory v, bytes[] memory c, string memory d) =
            _buildTransferProposal(recipient, amount, "Treasury transfer");
        _runFullLifecycle(alice, alice, t, v, c, d);

        assertEq(token.balanceOf(recipient), before + amount);
    }

    function test_ChangeFeeParameter() public {
        (address[] memory t, uint256[] memory v, bytes[] memory c, string memory d) =
            _buildFeeProposal(250, "Change fee");
        _runFullLifecycle(alice, alice, t, v, c, d);
        assertEq(box.feePercentage(), 250);
    }

    function test_ProposalFailsIfQuorumNotMet() public {
        address small = makeAddr("small");
        vm.prank(deployer);
        token.transfer(small, PROPOSAL_THRESHOLD + 1e18);

        vm.prank(small);
        token.delegate(small);
        vm.roll(block.number + 1);

        (address[] memory t, uint256[] memory v, bytes[] memory c, string memory d) =
            _buildBoxProposal(99, "Quorum fail");
        vm.prank(small);
        uint256 pid = governor.propose(t, v, c, d);

        vm.roll(block.number + VOTING_DELAY + 1);
        vm.prank(small);
        governor.castVote(pid, 1);

        vm.roll(block.number + VOTING_PERIOD + 1);
        assertEq(uint256(governor.state(pid)), uint256(IGovernor.ProposalState.Defeated));
    }

    function test_ProposeRevertsIfBelowThreshold() public {
        address poor = makeAddr("poor");
        vm.prank(deployer);
        token.transfer(poor, PROPOSAL_THRESHOLD - 1);
        vm.prank(poor);
        token.delegate(poor);

        (address[] memory t, uint256[] memory v, bytes[] memory c, string memory d) =
            _buildBoxProposal(1, "Below threshold");
        vm.prank(poor);
        vm.expectRevert();
        governor.propose(t, v, c, d);
    }

    function test_TimelockExecutionEnforcement() public {
        (address[] memory t, uint256[] memory v, bytes[] memory c, string memory d) =
            _buildBoxProposal(100, "Timelock test");
        vm.prank(alice);
        uint256 pid = governor.propose(t, v, c, d);

        vm.roll(block.number + VOTING_DELAY + 1);
        vm.prank(alice);
        governor.castVote(pid, 1);
        vm.roll(block.number + VOTING_PERIOD + 1);

        bytes32 descHash = keccak256(bytes(d));
        governor.queue(t, v, c, descHash);

        vm.warp(block.timestamp + TIMELOCK_DELAY - 1);
        vm.expectRevert();
        governor.execute(t, v, c, descHash);
    }

    function test_ProposalStateTransitions() public {
        (address[] memory t, uint256[] memory v, bytes[] memory c, string memory d) =
            _buildBoxProposal(777, "State test");
        vm.prank(alice);
        uint256 pid = governor.propose(t, v, c, d);

        assertEq(uint256(governor.state(pid)), uint256(IGovernor.ProposalState.Pending));

        vm.roll(block.number + VOTING_DELAY + 1);
        assertEq(uint256(governor.state(pid)), uint256(IGovernor.ProposalState.Active));

        vm.prank(alice);
        governor.castVote(pid, 1);

        vm.roll(block.number + VOTING_PERIOD + 1);
        assertEq(uint256(governor.state(pid)), uint256(IGovernor.ProposalState.Succeeded));
    }

    function test_MultiActionProposal() public {
        address[] memory targets = new address[](2);
        uint256[] memory values = new uint256[](2);
        bytes[] memory calldatas = new bytes[](2);

        targets[0] = address(box);
        calldatas[0] = abi.encodeWithSignature("store(uint256)", 999);

        targets[1] = address(box);
        calldatas[1] = abi.encodeWithSignature("setFeePercentage(uint256)", 500);

        string memory desc = "Multi action proposal";

        vm.prank(alice);
        uint256 pid = governor.propose(targets, values, calldatas, desc);

        vm.roll(block.number + VOTING_DELAY + 1);
        vm.prank(alice);
        governor.castVote(pid, 1);

        vm.roll(block.number + VOTING_PERIOD + 1);

        bytes32 descHash = keccak256(bytes(desc));
        governor.queue(targets, values, calldatas, descHash);
        vm.warp(block.timestamp + TIMELOCK_DELAY + 1);
        governor.execute(targets, values, calldatas, descHash);

        assertEq(box.retrieve(), 999);
        assertEq(box.feePercentage(), 500);
    }

    function test_TimelockIsOwnerOfBoxAndTreasury() public view {
        assertEq(box.owner(), address(timelock));
        assertEq(treasury.owner(), address(timelock));
    }
}
