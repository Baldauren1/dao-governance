# Part 5 Security Audit Report

## Scope

This report covers the DAO security portion of Part 5 for the following contracts:

- `GovernanceToken.sol`
- `TokenVesting.sol`
- `MyGovernor.sol`
- `Treasury.sol`
- `Box.sol`

The review focuses on governance safety, token concentration risk, treasury control, vesting logic, and the specific assignment topics:

- Slither findings
- whale attack analysis
- flash-loan attack analysis
- recommendations

## Methodology

The review used two layers:

- manual review of the Solidity source and Foundry tests
- tool-assisted checks from the local Foundry build and lint output

Slither status:

- direct `slither .` execution was attempted, but the `slither` binary is not installed in the current environment
- Docker-based `Slither` execution was also attempted, but the local Docker daemon was not running
- because of that, the final report records the static-analysis categories that were still visible from the available tooling and confirms all conclusions with manual code review

This limitation should be stated honestly in the submission if the instructor expects a literal Slither console screenshot.

## Architecture Summary

The project uses a fairly standard OpenZeppelin governance stack:

- `GovernanceToken` is an `ERC20Votes` token with a fixed `100,000,000 GOV` total supply
- `MyGovernor` uses `GovernorSettings`, `GovernorVotesQuorumFraction`, and `GovernorTimelockControl`
- `TimelockController` enforces a `2 day` execution delay
- `Treasury` holds ETH and ERC20 assets and is owned by the timelock
- `Box` is a simple timelock-owned target contract
- `TokenVesting` holds the team allocation and releases it linearly over `365 days`

This is a good baseline design for an educational DAO because privileged actions are routed through governance plus timelock rather than through a single EOA.

## Findings Summary

Overall conclusion:

- no critical smart-contract bug was found that allows arbitrary minting, unauthorized treasury transfer, or bypass of timelock ownership
- the biggest practical risk is governance centralization through token concentration rather than a low-level Solidity exploit

### Finding 1: Whale Governance Risk From Concentrated Voting Power

Severity: Medium

Relevant code:

- `GovernanceToken.sol` mints fixed allocations at lines `15-18` and `50-53`
- `MyGovernor.sol` sets `proposalThreshold = 1,000,000 GOV` and `quorum = 4%` at lines `37-43`

Why it matters:

- governance security depends on who controls the token supply
- a holder with a very large delegated balance can both create proposals and pass them with limited participation from others
- quorum is only `4%` of total supply, which is low enough that a large delegate can dominate governance if turnout is weak

Why this is realistic here:

- token distribution is fixed and concentrated into large buckets
- `40%` goes to the team vesting contract
- `30%` goes to the treasury
- `20%` goes to the community airdrop wallet
- `10%` goes to the liquidity wallet

In the actual Sepolia deployment used for Part 5, the same wallet was used for:

- `COMMUNITY_AIRDROP`
- `LIQUIDITY_POOL`
- `TEAM_BENEFICIARY`
- `VESTING_ADMIN`

That means one address immediately controlled `30%` of the liquid token supply and also became the beneficiary of the `40%` team vesting allocation over time. Even though the vested tokens are not instantly liquid, this configuration is still highly centralized and should be treated as a governance risk.

Impact:

- a whale can propose treasury transfers, parameter changes, or other privileged actions
- the timelock delays execution but does not stop a successful proposal
- if the whale also controls off-chain social coordination or low voter turnout, governance becomes effectively centralized

### Finding 2: Timestamp Dependence In Vesting Logic

Severity: Low

Relevant code:

- `TokenVesting.sol` line `47`
- `TokenVesting.sol` lines `119-135`

Why it matters:

- vesting uses `block.timestamp` to validate the start time and to calculate released amounts
- timestamp dependence is a common static-analysis warning category because validators can manipulate timestamps slightly

Assessment:

- in this contract, timestamp usage is expected and functionally correct because vesting is inherently time-based
- the risk is limited to small timestamp drift, not to complete theft of funds
- there is no evidence that a user can exploit this to release vastly more tokens than intended

Impact:

- low practical risk
- mainly an informational finding that should still be acknowledged in the audit

### Finding 3: External ETH Call In Treasury

Severity: Low

Relevant code:

- `Treasury.sol` lines `26-30`

Why it matters:

- `transferETH` uses a low-level `.call{value: amount}("")`
- static analyzers often flag external calls because they may trigger arbitrary code execution in the recipient

Assessment:

- the function is protected by `onlyOwner`
- the owner is the timelock, not a regular user wallet
- the treasury does not update internal accounting after the call, so classical reentrancy damage is limited
- the code pattern is acceptable for an owner-controlled treasury, but it still deserves explicit mention

Impact:

- not a critical exploit path in the current architecture
- still worth documenting as an external-call surface

### Finding 4: Centralized Vesting Administration

Severity: Low to Medium

Relevant code:

- `TokenVesting.sol` lines `63-88`

Why it matters:

- the vesting owner can revoke schedules
- the owner can also change `revokeReceiver`
- this is not a bug, but it gives strong administrative control over team vesting

Assessment:

- for a classroom project, this is acceptable
- for a production DAO, vesting administration should usually be moved to a multisig or governance itself
- otherwise the vesting admin becomes a trusted party who can redirect unvested team tokens

Impact:

- governance trust assumptions are higher than they look from the UI alone

## Whale Attack Analysis

A whale attack means one holder or a coordinated group controls enough delegated votes to dominate DAO decisions.

In this project, the main factors are:

- `proposalThreshold = 1,000,000 GOV`, which is `1%` of supply
- `quorum = 4%` of total supply
- voting power is activated through delegation

Attack scenario:

- a whale accumulates or already owns a very large amount of GOV
- the whale self-delegates or gathers delegated votes from passive holders
- the whale proposes an action such as:
- treasury token transfer
- treasury ETH transfer
- `Box` parameter change
- any future governance-controlled upgrade or action

If voter participation is low, the whale can pass proposals almost alone. A holder with more than `50%` of delegated supply is especially dangerous because:

- they can reliably cross quorum
- they can outvote every other participant
- they can control proposal outcome regardless of minority opposition

Important nuance:

- the timelock still slows the attack down by `2 days`
- observers can react, discuss, or exit during that window
- however, timelock delay is a monitoring and response feature, not a prevention mechanism

Risk level for this project:

- medium in the abstract design
- higher in the specific Sepolia deployment because community and liquidity allocations were intentionally pointed to the same wallet for simplicity

Mitigations:

- distribute large allocations across separate wallets or multisigs
- avoid using the same address for community, liquidity, and team-admin roles in any non-demo environment
- consider increasing quorum above `4%` if the token remains concentrated
- consider adding a guardian or emergency veto during early bootstrap stages

## Flash-Loan Attack Analysis

The important question is whether an attacker can temporarily borrow governance tokens, vote in the same proposal, then return them immediately.

This project is protected well against classic flash-loan governance attacks because it uses `ERC20Votes`.

Why the protection works:

- `ERC20Votes` uses historical vote checkpoints rather than current balance only
- the governor reads voting power from the proposal snapshot block
- the project also uses a non-zero `votingDelay = 7200`, so voting does not start immediately after proposal creation

This matters because a flash loan is atomic:

- the attacker borrows and returns funds in one transaction
- they cannot keep those borrowed votes across thousands of blocks until the snapshot used by the governor

So the classic exploit pattern fails:

- borrow GOV in one transaction
- create proposal or vote immediately
- return GOV before the transaction ends

That pattern does not defeat `ERC20Votes` snapshots.

Residual risk:

- if an attacker can obtain large voting power across multiple blocks, that is no longer a flash-loan attack but a temporary accumulation attack
- for example, borrowing from a protocol with multi-block collateralized positions would still create governance risk if the votes remain delegated through the snapshot block

Conclusion:

- classic single-transaction flash-loan governance attacks are well mitigated here
- temporary multi-block vote accumulation remains a general governance risk, but that is different from a pure flash-loan exploit

## Recommendations

Priority recommendations:

- add a real `Slither` run to CI once the environment has either Python or a working Docker daemon
- split community, liquidity, and vesting-admin roles across separate wallets or multisigs
- keep the `2 day` timelock and consider increasing it if the treasury grows
- review whether `4%` quorum is sufficient for the expected token distribution
- use a multisig for `VESTING_ADMIN` and any treasury-adjacent operational roles

Secondary recommendations:

- document operational monitoring for `ProposalCreated`, `ProposalQueued`, `ProposalExecuted`, `RoleGranted`, and treasury transfer events
- consider a bootstrap guardian or veto role for early-stage deployments if the DAO is not yet widely distributed
- keep treasury-facing target contracts small and simple, as done with `Box` and `Treasury`

## Final Assessment

The contracts are reasonably safe for an academic DAO project and correctly use OpenZeppelin governance primitives. No critical exploit allowing direct unauthorized asset theft was identified during manual review.

The dominant security concern is not a Solidity memory or arithmetic bug. It is governance centralization:

- concentrated token ownership
- low quorum relative to large holders
- strong operational power in the vesting admin

The design is resilient against classic flash-loan voting attacks because `ERC20Votes` snapshots past voting power. The main production hardening step would be better role separation plus real automated static analysis in CI.
