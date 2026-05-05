// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {GovernanceToken} from "../src/GovernanceToken.sol";
import {MyGovernor} from "../src/MyGovernor.sol";
import {Box} from "../src/Box.sol";
import {Treasury} from "../src/Treasury.sol";

contract Deploy is Script {
    uint256 constant TIMELOCK_MIN_DELAY = 2 days;

    // Placeholder addresses for initial distribution
    address constant COMMUNITY_AIRDROP = address(0xCAFE);
    address constant LIQUIDITY_POOL = address(0xBEEF);

    GovernanceToken public token;
    TimelockController public timelock;
    MyGovernor public governor;
    Box public box;
    Treasury public treasury;

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        vm.startBroadcast(deployerKey);

        // 1. Deploy GovernanceToken with initial supply distribution
        token = new GovernanceToken(
            deployer, // Team vesting placeholder
            deployer, // Initial treasury holder
            COMMUNITY_AIRDROP,
            LIQUIDITY_POOL
        );
        console.log("GovernanceToken deployed:", address(token));

        // 2. Deploy TimelockController (manages proposal execution delay)
        address[] memory empty = new address[](0);
        timelock = new TimelockController(
            TIMELOCK_MIN_DELAY,
            empty,
            empty,
            deployer // Temporary admin for setup
        );
        console.log("Timelock deployed:", address(timelock));

        // 3. Deploy the Governor contract
        governor = new MyGovernor(token, timelock);
        console.log("MyGovernor deployed:", address(governor));

        // 4. Setup Roles within the Timelock
        bytes32 PROPOSER_ROLE = timelock.PROPOSER_ROLE();
        bytes32 EXECUTOR_ROLE = timelock.EXECUTOR_ROLE();
        bytes32 CANCELLER_ROLE = timelock.CANCELLER_ROLE();

        // Grant Governor the ability to propose and cancel
        timelock.grantRole(PROPOSER_ROLE, address(governor));
        timelock.grantRole(CANCELLER_ROLE, address(governor));

        // Setting EXECUTOR_ROLE to address(0) allows anyone to execute successful proposals
        timelock.grantRole(EXECUTOR_ROLE, address(0));

        // 5. Revoke admin role from deployer to ensure decentralization
        timelock.revokeRole(timelock.DEFAULT_ADMIN_ROLE(), deployer);
        console.log("Admin role revoked from deployer");

        // 6. Deploy target contracts owned by the Timelock
        box = new Box(address(timelock));
        treasury = new Treasury(address(timelock));
        console.log("Box deployed:", address(box));
        console.log("Treasury deployed:", address(treasury));

        // 7. Activate voting power for the deployer to enable immediate proposing
        token.delegate(deployer);

        vm.stopBroadcast();

        console.log("\n--- Deployment Summary ---");
        console.log("GovernanceToken :", address(token));
        console.log("Timelock :", address(timelock));
        console.log("MyGovernor :", address(governor));
        console.log("Box :", address(box));
        console.log("Treasury :", address(treasury));
        console.log("--------------------------\n");
    }
}
