// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

import {GovernanceToken} from "../src/GovernanceToken.sol";
import {MyGovernor} from "../src/MyGovernor.sol";
import {Treasury} from "../src/Treasury.sol";
import {Box} from "../src/Box.sol";

contract Part3Test is Test {
    GovernanceToken internal token;
    TimelockController internal timelock;
    MyGovernor internal governor;
    Treasury internal treasury;
    Box internal box;

    address internal deployer = makeAddr("deployer");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");
    address internal recipient = makeAddr("recipient");

    uint256 internal constant VOTING_DELAY = 7_200;
    uint256 internal constant VOTING_PERIOD = 50_400;
    uint256 internal constant TIMELOCK_DELAY = 2 days;
    uint256 internal constant TOTAL_SUPPLY = 100_000_000e18;
    uint256 internal constant TREASURY_GOV_ALLOCATION = 10_000_000e18;
    uint256 internal constant TREASURY_ETH_BALANCE = 10 ether;

    function setUp() public {
        vm.startPrank(deployer);

        token = new GovernanceToken(
            deployer,
            makeAddr("treasuryPlaceholder"),
            makeAddr("communityPlaceholder"),
            makeAddr("liquidityPlaceholder")
        );

        address[] memory empty = new address[](0);
        timelock = new TimelockController(
            TIMELOCK_DELAY,
            empty,
            empty,
            deployer
        );

        governor = new MyGovernor(token, timelock);
        treasury = new Treasury(address(timelock));
        box = new Box(address(timelock));

        timelock.grantRole(timelock.PROPOSER_ROLE(), address(governor));
        timelock.grantRole(timelock.CANCELLER_ROLE(), address(governor));
        timelock.grantRole(timelock.EXECUTOR_ROLE(), address(0));
        timelock.revokeRole(timelock.DEFAULT_ADMIN_ROLE(), deployer);

        token.transfer(alice, (TOTAL_SUPPLY * 5) / 100);
        token.transfer(bob, (TOTAL_SUPPLY * 3) / 100);
        token.transfer(carol, (TOTAL_SUPPLY * 2) / 100);
        token.transfer(address(treasury), TREASURY_GOV_ALLOCATION);

        vm.stopPrank();

        vm.deal(address(treasury), TREASURY_ETH_BALANCE);

        vm.prank(alice);
        token.delegate(alice);
        vm.prank(bob);
        token.delegate(bob);
        vm.prank(carol);
        token.delegate(carol);

        vm.roll(block.number + 1);
    }

    function test_TreasuryAndBoxStartUnderTimelockControl() public view {
        assertEq(treasury.owner(), address(timelock), "treasury owner should be timelock");
        assertEq(box.owner(), address(timelock), "box owner should be timelock");
        assertEq(treasury.ethBalance(), TREASURY_ETH_BALANCE, "treasury should hold ETH");
        assertEq(
            treasury.tokenBalance(address(token)),
            TREASURY_GOV_ALLOCATION,
            "treasury should hold GOV"
        );
    }

    function test_NonOwnersCannotCallTreasuryOrBoxDirectly() public {
        vm.startPrank(alice);

        vm.expectRevert();
        treasury.transferETH(payable(recipient), 1 ether);

        vm.expectRevert();
        treasury.transferERC20(address(token), recipient, 1e18);

        vm.expectRevert();
        box.store(42);

        vm.expectRevert();
        box.setFeePercentage(250);

        vm.stopPrank();
    }

    function test_EndToEnd_BoxStore42Proposal() public {
        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,
            string memory description
        ) = _singleCallProposal(
            address(box),
            0,
            abi.encodeCall(Box.store, (42)),
            "Part 3: Box.store(42)"
        );

        _runLifecycleWithLogs(targets, values, calldatas, description);
        uint256 storedValue = box.retrieve();
        console.log("7. Verified Box value:");
        console.log(storedValue);

        assertEq(
            storedValue,
            42,
            "governance should update the Box value"
        );
    }

    function test_EndToEnd_TreasuryTransfersETH() public {
        uint256 transferAmount = 2 ether;
        uint256 recipientBefore = recipient.balance;
        uint256 treasuryBefore = address(treasury).balance;

        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,
            string memory description
        ) = _singleCallProposal(
            address(treasury),
            0,
            abi.encodeCall(
                Treasury.transferETH,
                (payable(recipient), transferAmount)
            ),
            "Part 3: Treasury transfer ETH"
        );

        _runLifecycleWithLogs(targets, values, calldatas, description);

        assertEq(
            recipient.balance - recipientBefore,
            transferAmount,
            "recipient should receive ETH from treasury"
        );
        assertEq(
            treasuryBefore - address(treasury).balance,
            transferAmount,
            "treasury ETH should decrease"
        );
    }

    function test_EndToEnd_TreasuryTransfersERC20() public {
        uint256 transferAmount = 1_250_000e18;
        uint256 recipientBefore = token.balanceOf(recipient);
        uint256 treasuryBefore = token.balanceOf(address(treasury));

        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,
            string memory description
        ) = _singleCallProposal(
            address(treasury),
            0,
            abi.encodeCall(
                Treasury.transferERC20,
                (address(token), recipient, transferAmount)
            ),
            "Part 3: Treasury transfer GOV"
        );

        _runLifecycleWithLogs(targets, values, calldatas, description);

        assertEq(
            token.balanceOf(recipient) - recipientBefore,
            transferAmount,
            "recipient should receive GOV from treasury"
        );
        assertEq(
            treasuryBefore - token.balanceOf(address(treasury)),
            transferAmount,
            "treasury GOV should decrease"
        );
    }

    function test_EndToEnd_BoxFeeParameterChange() public {
        uint256 newFee = 250;

        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,
            string memory description
        ) = _singleCallProposal(
            address(box),
            0,
            abi.encodeCall(Box.setFeePercentage, (newFee)),
            "Part 3: Box fee change"
        );

        _runLifecycleWithLogs(targets, values, calldatas, description);

        assertEq(
            box.feePercentage(),
            newFee,
            "governance should update the controlled parameter"
        );
    }

    function _singleCallProposal(
        address target,
        uint256 value,
        bytes memory calldata_,
        string memory description
    )
        internal
        pure
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

        targets[0] = target;
        values[0] = value;
        calldatas[0] = calldata_;
        desc = description;
    }

    function _runLifecycleWithLogs(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) internal returns (uint256 proposalId) {
        console.log("");
        console.log("=== PART 3 GOVERNANCE LIFECYCLE ===");
        console.log(description);

        vm.prank(alice);
        proposalId = governor.propose(targets, values, calldatas, description);
        assertEq(
            uint256(governor.state(proposalId)),
            uint256(IGovernor.ProposalState.Pending),
            "proposal should start pending"
        );
        console.log("1. Proposed. Proposal ID:");
        console.log(proposalId);

        vm.roll(block.number + VOTING_DELAY + 1);
        assertEq(
            uint256(governor.state(proposalId)),
            uint256(IGovernor.ProposalState.Active),
            "proposal should become active"
        );
        console.log("2. Voting started at block:");
        console.log(block.number);

        vm.prank(alice);
        governor.castVote(proposalId, 1);
        (, uint256 forVotes,) = governor.proposalVotes(proposalId);
        console.log("3. Vote cast. For votes:");
        console.log(forVotes / 1e18);

        vm.roll(block.number + VOTING_PERIOD + 1);
        assertEq(
            uint256(governor.state(proposalId)),
            uint256(IGovernor.ProposalState.Succeeded),
            "proposal should succeed after voting"
        );
        console.log("4. Voting finished successfully.");

        bytes32 descriptionHash = keccak256(bytes(description));
        governor.queue(targets, values, calldatas, descriptionHash);
        assertEq(
            uint256(governor.state(proposalId)),
            uint256(IGovernor.ProposalState.Queued),
            "proposal should be queued in timelock"
        );
        console.log("5. Proposal queued in timelock.");

        vm.warp(block.timestamp + TIMELOCK_DELAY + 1);
        governor.execute(targets, values, calldatas, descriptionHash);
        assertEq(
            uint256(governor.state(proposalId)),
            uint256(IGovernor.ProposalState.Executed),
            "proposal should be executed"
        );
        console.log("6. Proposal executed.");
    }
}
