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
$env:REVOKE_RECEIVER="0x..."
$env:TEAM_VESTING_START="1767225600"
$env:TREASURY_ETH_SEED="0"
```

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

## Verified Contract Links

Fill these after the real Sepolia deployment:

| Contract | Address | Etherscan Link |
|---|---|---|
| GovernanceToken | `...` | `https://sepolia.etherscan.io/address/...` |
| TokenVesting | `...` | `https://sepolia.etherscan.io/address/...` |
| TimelockController | `...` | `https://sepolia.etherscan.io/address/...` |
| MyGovernor | `...` | `https://sepolia.etherscan.io/address/...` |
| Box | `...` | `https://sepolia.etherscan.io/address/...` |
| Treasury | `...` | `https://sepolia.etherscan.io/address/...` |

## Post-Deployment Verification

Set the deployed addresses as env vars:

```powershell
$env:TOKEN_ADDRESS="0x..."
$env:VESTING_ADDRESS="0x..."
$env:TIMELOCK_ADDRESS="0x..."
$env:GOVERNOR_ADDRESS="0x..."
$env:BOX_ADDRESS="0x..."
$env:TREASURY_ADDRESS="0x..."
$env:DEPLOYER_ADDRESS="0x..."
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

This repository can now prepare the deployment flow, but these deliverables still require a real Sepolia deployment:

- actual verified Etherscan links
- final deployed addresses
- screenshots or logs from the real verification run
