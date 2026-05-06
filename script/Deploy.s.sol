// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {GovernanceToken} from "../src/GovernanceToken.sol";
import {TokenVesting} from "../src/TokenVesting.sol";
import {MyGovernor} from "../src/MyGovernor.sol";
import {Box} from "../src/Box.sol";
import {Treasury} from "../src/Treasury.sol";

contract Deploy is Script {
    uint256 internal constant TIMELOCK_MIN_DELAY = 2 days;
    uint256 internal constant DEFAULT_VESTING_OFFSET = 1 days;

    struct DeploymentConfig {
        uint256 deployerKey;
        address communityAirdrop;
        address liquidityPool;
        address teamBeneficiary;
        address vestingAdmin;
        address revokeReceiver;
        uint256 teamVestingStart;
        uint256 treasuryEthSeed;
    }

    GovernanceToken public token;
    TokenVesting public vesting;
    TimelockController public timelock;
    MyGovernor public governor;
    Box public box;
    Treasury public treasury;

    function run() external {
        DeploymentConfig memory cfg = _loadConfig();
        address deployer = vm.rememberKey(cfg.deployerKey);

        uint256 currentNonce = vm.getNonce(deployer);
        address predictedToken = vm.computeCreateAddress(deployer, currentNonce);
        address predictedVesting = vm.computeCreateAddress(deployer, currentNonce + 1);
        address predictedTimelock = vm.computeCreateAddress(deployer, currentNonce + 2);
        address predictedGovernor = vm.computeCreateAddress(deployer, currentNonce + 3);
        address predictedBox = vm.computeCreateAddress(deployer, currentNonce + 4);
        address predictedTreasury = vm.computeCreateAddress(deployer, currentNonce + 5);

        if (cfg.revokeReceiver == address(0)) {
            cfg.revokeReceiver = predictedTreasury;
        }

        if (cfg.teamVestingStart == 0) {
            cfg.teamVestingStart = block.timestamp + DEFAULT_VESTING_OFFSET;
        }

        console.log("Deployer:", deployer);
        console.log("Predicted token:", predictedToken);
        console.log("Predicted vesting:", predictedVesting);
        console.log("Predicted timelock:", predictedTimelock);
        console.log("Predicted governor:", predictedGovernor);
        console.log("Predicted box:", predictedBox);
        console.log("Predicted treasury:", predictedTreasury);

        vm.startBroadcast(cfg.deployerKey);

        token = new GovernanceToken(predictedVesting, predictedTreasury, cfg.communityAirdrop, cfg.liquidityPool);
        vesting = new TokenVesting(predictedToken, cfg.revokeReceiver);

        address[] memory empty = new address[](0);
        timelock = new TimelockController(TIMELOCK_MIN_DELAY, empty, empty, deployer);

        governor = new MyGovernor(token, timelock);
        box = new Box(address(timelock));
        treasury = new Treasury(address(timelock));

        _assertPredictedAddress(address(token), predictedToken, "token");
        _assertPredictedAddress(address(vesting), predictedVesting, "vesting");
        _assertPredictedAddress(address(timelock), predictedTimelock, "timelock");
        _assertPredictedAddress(address(governor), predictedGovernor, "governor");
        _assertPredictedAddress(address(box), predictedBox, "box");
        _assertPredictedAddress(address(treasury), predictedTreasury, "treasury");

        uint256 teamAllocation = token.balanceOf(address(vesting));
        vesting.createSchedule(cfg.teamBeneficiary, teamAllocation, cfg.teamVestingStart);

        if (cfg.vestingAdmin != deployer) {
            vesting.transferOwnership(cfg.vestingAdmin);
        }

        bytes32 proposerRole = timelock.PROPOSER_ROLE();
        bytes32 executorRole = timelock.EXECUTOR_ROLE();
        bytes32 cancellerRole = timelock.CANCELLER_ROLE();

        timelock.grantRole(proposerRole, address(governor));
        timelock.grantRole(cancellerRole, address(governor));
        timelock.grantRole(executorRole, address(0));
        timelock.revokeRole(timelock.DEFAULT_ADMIN_ROLE(), deployer);

        if (cfg.treasuryEthSeed > 0) {
            (bool success,) = address(treasury).call{value: cfg.treasuryEthSeed}("");
            require(success, "Treasury seed failed");
        }

        vm.stopBroadcast();

        console.log("\n--- Deployment Summary ---");
        console.log("GovernanceToken :", address(token));
        console.log("TokenVesting    :", address(vesting));
        console.log("Timelock        :", address(timelock));
        console.log("MyGovernor      :", address(governor));
        console.log("Box             :", address(box));
        console.log("Treasury        :", address(treasury));
        console.log("Team beneficiary:", cfg.teamBeneficiary);
        console.log("Vesting admin   :", vesting.owner());
        console.log("Revoke receiver :", cfg.revokeReceiver);
        console.log("Vesting start   :", cfg.teamVestingStart);
        console.log("Treasury ETH    :", address(treasury).balance);
        console.log("--------------------------\n");
    }

    function _loadConfig() internal view returns (DeploymentConfig memory cfg) {
        cfg.deployerKey = vm.envUint("PRIVATE_KEY");
        cfg.communityAirdrop = vm.envAddress("COMMUNITY_AIRDROP");
        cfg.liquidityPool = vm.envAddress("LIQUIDITY_POOL");
        cfg.teamBeneficiary = vm.envAddress("TEAM_BENEFICIARY");
        cfg.vestingAdmin = vm.envOr("VESTING_ADMIN", vm.addr(cfg.deployerKey));
        cfg.revokeReceiver = vm.envOr("REVOKE_RECEIVER", address(0));
        cfg.teamVestingStart = vm.envOr("TEAM_VESTING_START", uint256(0));
        cfg.treasuryEthSeed = vm.envOr("TREASURY_ETH_SEED", uint256(0));
    }

    function _assertPredictedAddress(address actual, address predicted, string memory label) internal pure {
        require(actual == predicted, string.concat("Unexpected ", label, " address"));
    }
}
