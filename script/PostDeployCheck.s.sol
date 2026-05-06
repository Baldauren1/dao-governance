// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {GovernanceToken} from "../src/GovernanceToken.sol";
import {TokenVesting} from "../src/TokenVesting.sol";
import {MyGovernor} from "../src/MyGovernor.sol";
import {Box} from "../src/Box.sol";
import {Treasury} from "../src/Treasury.sol";

contract PostDeployCheck is Script {
    uint256 internal constant EXPECTED_TIMELOCK_DELAY = 2 days;
    uint256 internal constant EXPECTED_VOTING_DELAY = 7_200;
    uint256 internal constant EXPECTED_VOTING_PERIOD = 50_400;
    uint256 internal constant EXPECTED_PROPOSAL_THRESHOLD = 1_000_000e18;
    uint256 internal constant EXPECTED_QUORUM = 4_000_000e18;

    struct DeploymentAddresses {
        address token;
        address vesting;
        address timelock;
        address governor;
        address box;
        address treasury;
        address deployer;
        address vestingAdmin;
    }

    function run() external view {
        DeploymentAddresses memory addrs = _loadAddresses();

        _checkTimelockAndOwnership(addrs);
        _checkGovernorParameters(addrs);
        _checkVestingOwner(addrs);
        _logSummary(addrs);
    }

    function _loadAddresses() internal view returns (DeploymentAddresses memory addrs) {
        addrs.token = vm.envAddress("TOKEN_ADDRESS");
        addrs.vesting = vm.envAddress("VESTING_ADDRESS");
        addrs.timelock = vm.envAddress("TIMELOCK_ADDRESS");
        addrs.governor = vm.envAddress("GOVERNOR_ADDRESS");
        addrs.box = vm.envAddress("BOX_ADDRESS");
        addrs.treasury = vm.envAddress("TREASURY_ADDRESS");
        addrs.deployer = vm.envOr("DEPLOYER_ADDRESS", address(0));
        addrs.vestingAdmin = vm.envOr("VESTING_ADMIN", addrs.deployer);
    }

    function _checkTimelockAndOwnership(DeploymentAddresses memory addrs) internal view {
        TimelockController timelock = TimelockController(payable(addrs.timelock));
        Box box = Box(addrs.box);
        Treasury treasury = Treasury(payable(addrs.treasury));

        _assertEqUint(timelock.getMinDelay(), EXPECTED_TIMELOCK_DELAY, "Unexpected timelock delay");
        _assertTrue(timelock.hasRole(timelock.PROPOSER_ROLE(), addrs.governor), "Governor missing PROPOSER_ROLE");
        _assertTrue(timelock.hasRole(timelock.CANCELLER_ROLE(), addrs.governor), "Governor missing CANCELLER_ROLE");
        _assertTrue(timelock.hasRole(timelock.EXECUTOR_ROLE(), address(0)), "Open executor role is missing");

        if (addrs.deployer != address(0)) {
            _assertTrue(
                !timelock.hasRole(timelock.DEFAULT_ADMIN_ROLE(), addrs.deployer),
                "Deployer still has timelock admin role"
            );
        }

        _assertEqAddress(box.owner(), addrs.timelock, "Box owner must be timelock");
        _assertEqAddress(treasury.owner(), addrs.timelock, "Treasury owner must be timelock");
    }

    function _checkGovernorParameters(DeploymentAddresses memory addrs) internal view {
        GovernanceToken token = GovernanceToken(addrs.token);
        MyGovernor governor = MyGovernor(payable(addrs.governor));

        _assertEqUint(governor.votingDelay(), EXPECTED_VOTING_DELAY, "Unexpected voting delay");
        _assertEqUint(governor.votingPeriod(), EXPECTED_VOTING_PERIOD, "Unexpected voting period");
        _assertEqUint(governor.proposalThreshold(), EXPECTED_PROPOSAL_THRESHOLD, "Unexpected proposal threshold");
        _assertEqUint(governor.quorumNumerator(), 4, "Unexpected quorum numerator");
        _assertEqUint(
            (token.totalSupply() * governor.quorumNumerator()) / governor.quorumDenominator(),
            EXPECTED_QUORUM,
            "Unexpected quorum"
        );
    }

    function _checkVestingOwner(DeploymentAddresses memory addrs) internal view {
        if (addrs.vestingAdmin == address(0)) {
            return;
        }

        TokenVesting vesting = TokenVesting(addrs.vesting);
        _assertEqAddress(vesting.owner(), addrs.vestingAdmin, "Unexpected vesting owner");
    }

    function _logSummary(DeploymentAddresses memory addrs) internal view {
        GovernanceToken token = GovernanceToken(addrs.token);
        MyGovernor governor = MyGovernor(payable(addrs.governor));
        TimelockController timelock = TimelockController(payable(addrs.timelock));
        uint256 computedQuorum = (token.totalSupply() * governor.quorumNumerator()) / governor.quorumDenominator();

        console.log("Post-deployment checks passed.");
        console.log("Token total supply:", token.totalSupply());
        console.log("Team tokens in vesting:", token.balanceOf(addrs.vesting));
        console.log("Treasury GOV balance:", token.balanceOf(addrs.treasury));
        console.log("Timelock delay:", timelock.getMinDelay());
        console.log("Governor quorum numerator:", governor.quorumNumerator());
        console.log("Computed quorum:", computedQuorum);
    }

    function _assertTrue(bool condition, string memory message) internal pure {
        require(condition, message);
    }

    function _assertEqUint(uint256 actual, uint256 expected, string memory message) internal pure {
        require(actual == expected, message);
    }

    function _assertEqAddress(address actual, address expected, string memory message) internal pure {
        require(actual == expected, message);
    }
}
