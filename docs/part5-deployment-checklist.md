# Part 5 Deployment Checklist

This document covers the deployment half of Part 5 from the assignment PDF:
- deploy all contracts in the correct order with proper permissions
- verify contracts on Etherscan testnet
- document post-deployment verification steps
- define a simple monitoring plan

## Files

- [script/Deploy.s.sol](/C:/Users/Admin/Desktop/uni docx/BC2/assignment4(2)/script/Deploy.s.sol)
- [script/PostDeployCheck.s.sol](/C:/Users/Admin/Desktop/uni docx/BC2/assignment4(2)/script/PostDeployCheck.s.sol)
- [.env.example](/C:/Users/Admin/Desktop/uni docx/BC2/assignment4(2)/.env.example)
- [docs/part5-security-audit-report.md](/C:/Users/Admin/Desktop/uni docx/BC2/assignment4(2)/docs/part5-security-audit-report.md)

## Required Environment Variables

Fill these values before a real testnet deployment:

- `PRIVATE_KEY`
- `SEPOLIA_RPC_URL`
- `ETHERSCAN_API_KEY`
- `COMMUNITY_AIRDROP`
- `LIQUIDITY_POOL`
- `TEAM_BENEFICIARY`

Optional but recommended:

- `VESTING_ADMIN`
- `REVOKE_RECEIVER`
- `TEAM_VESTING_START`
- `TREASURY_ETH_SEED`

## PowerShell Setup

```powershell
$env:PRIVATE_KEY="0x..."
$env:SEPOLIA_RPC_URL="https://sepolia.infura.io/v3/..."
$env:ETHERSCAN_API_KEY="..."

$env:COMMUNITY_AIRDROP="0x..."
$env:LIQUIDITY_POOL="0x..."
$env:TEAM_BENEFICIARY="0x..."

$env:VESTING_ADMIN="0x..."
$env:TREASURY_ETH_SEED="0"
```

Note:
- If `REVOKE_RECEIVER` is omitted, the deploy script defaults it to the deployed `Treasury` address.
- If `TEAM_VESTING_START` is omitted, the deploy script defaults it to `block.timestamp + 1 day`.

## Deploy Command

Use Foundry broadcast plus automatic Etherscan verification:

```powershell
forge script script/Deploy.s.sol:Deploy `
  --rpc-url $env:SEPOLIA_RPC_URL `
  --broadcast `
  --verify `
  --etherscan-api-key $env:ETHERSCAN_API_KEY `
  -vvvv
```

Expected deployed contracts:

- `GovernanceToken`
- `TokenVesting`
- `TimelockController`
- `MyGovernor`
- `Box`
- `Treasury`

## Actual Sepolia Deployment

Real Sepolia deployment was completed from deployer `0x11801B9bD2639e7b3bC0C910dd5D18c0119E8750`.

| Contract | Address | Etherscan Link |
|---|---|---|
| GovernanceToken | `0x666382244BEF2A76D436B0B76aBb20e728404Bb9` | [Open](https://sepolia.etherscan.io/address/0x666382244BEF2A76D436B0B76aBb20e728404Bb9) |
| TokenVesting | `0xBb08f966B7fB2Cad5081b5a82Dc936a4a0e2094d` | [Open](https://sepolia.etherscan.io/address/0xBb08f966B7fB2Cad5081b5a82Dc936a4a0e2094d) |
| TimelockController | `0x730e9d3E9150E5eBED49f567D32246c304d0e4Fb` | [Open](https://sepolia.etherscan.io/address/0x730e9d3E9150E5eBED49f567D32246c304d0e4Fb) |
| MyGovernor | `0x84dA489D261F48b559B1B928F43821a1B3EFab9D` | [Open](https://sepolia.etherscan.io/address/0x84dA489D261F48b559B1B928F43821a1B3EFab9D) |
| Box | `0xfe7772C35924295801dca5522eA12B34EC442A3b` | [Open](https://sepolia.etherscan.io/address/0xfe7772C35924295801dca5522eA12B34EC442A3b) |
| Treasury | `0x24c39Bf255ce889F7728991ee58c7c7A289734F3` | [Open](https://sepolia.etherscan.io/address/0x24c39Bf255ce889F7728991ee58c7c7A289734F3) |

Verification note:
- Deployment to Sepolia succeeded.
- Post-deployment verification script succeeded.
- Etherscan source verification should be confirmed on each explorer page because the local `.env` still used a placeholder `ETHERSCAN_API_KEY` during the user run shown in chat.

## Post-Deployment Verification

Set the deployed addresses as env vars:

```powershell
$env:TOKEN_ADDRESS="0x666382244BEF2A76D436B0B76aBb20e728404Bb9"
$env:VESTING_ADDRESS="0xBb08f966B7fB2Cad5081b5a82Dc936a4a0e2094d"
$env:TIMELOCK_ADDRESS="0x730e9d3E9150E5eBED49f567D32246c304d0e4Fb"
$env:GOVERNOR_ADDRESS="0x84dA489D261F48b559B1B928F43821a1B3EFab9D"
$env:BOX_ADDRESS="0xfe7772C35924295801dca5522eA12B34EC442A3b"
$env:TREASURY_ADDRESS="0x24c39Bf255ce889F7728991ee58c7c7A289734F3"
$env:DEPLOYER_ADDRESS="0x11801B9bD2639e7b3bC0C910dd5D18c0119E8750"
```

Run the check script:

```powershell
forge script script/PostDeployCheck.s.sol:PostDeployCheck `
  --rpc-url $env:SEPOLIA_RPC_URL `
  -vvvv
```

Manual checklist:

- `TimelockController.getMinDelay()` is `2 days`
- `Governor` has `PROPOSER_ROLE`
- `Governor` has `CANCELLER_ROLE`
- `address(0)` has `EXECUTOR_ROLE`
- deployer no longer has `DEFAULT_ADMIN_ROLE`
- `Treasury.owner()` is the timelock
- `Box.owner()` is the timelock
- `Governor.votingDelay()` is `7200`
- `Governor.votingPeriod()` is `50400`
- `Governor.proposalThreshold()` is `1,000,000 GOV`
- `Governor.quorumNumerator()` is `4`
- computed quorum from total supply is `4,000,000 GOV`
- `TokenVesting.owner()` is the expected admin
- team allocation is held by `TokenVesting`
- treasury allocation is held by `Treasury`

Observed successful post-check results from the real Sepolia run:

- `Post-deployment checks passed`
- token total supply = `100,000,000 GOV`
- team tokens in vesting = `40,000,000 GOV`
- treasury GOV balance = `30,000,000 GOV`
- timelock delay = `172800`
- governor quorum numerator = `4`
- computed quorum = `4,000,000 GOV`

## Monitoring Plan

Watch these events:

- `ProposalCreated`
- `VoteCast`
- `ProposalQueued`
- `ProposalExecuted`
- `CallScheduled`
- `CallExecuted`
- `RoleGranted`
- `RoleRevoked`
- `ScheduleCreated`
- `TokensReleased`
- `ScheduleRevoked`
- `ETHTransferred`
- `ERC20Transferred`
- `ValueChanged`
- `FeeChanged`

Track these metrics:

- total proposals created per week
- voter participation rate
- quorum success rate
- timelock queue backlog
- treasury ETH balance
- treasury GOV balance
- vesting releases over time
- parameter changes in `Box`

## What Still Requires a Real Testnet Run

This repository now includes a real Sepolia deployment and a successful post-check. Remaining external proof items are:

- confirming "Contract Source Code Verified" on each Etherscan page
- screenshots or logs showing the real verification result on Etherscan
