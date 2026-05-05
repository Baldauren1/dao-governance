# DAO & On-Chain Governance — Assignment 4

Blockchain Technologies 2 | Foundry | OpenZeppelin | Solidity 0.8.24

## Part 1 Tests

| # | Test | Category |
|---|------|----------|
| 1 | Initial distribution 40/30/20/10 | Distribution |
| 2 | Voting power = 0 before delegation | Delegation |
| 3 | Self-delegation activates voting power | Delegation |
| 4 | Delegate to another address | Delegation |
| 5 | Re-delegation moves voting power | Delegation |
| 6 | getPastVotes snapshot immutable | Snapshots |
| 7 | getPastTotalSupply at past block | Snapshots |
| 8 | permit() gasless approval (EIP-2612) | Permit |
| 9 | permit() reverts on expired deadline | Permit |
| 10 | Schedule created with correct params | Vesting |
| 11 | Nothing vested before startTime | Vesting |
| 12 | ~50% vested at 6 months | Vesting |
| 13 | Full release at end of vesting | Vesting |
| 14 | Partial release mid-vesting | Vesting |
| 15 | Revoke: unvested→treasury, vested claimable | Vesting |

## Run Tests

```bash
forge build
forge test --match-path test/Part1.t.sol -vv
```


## Foundry

**Foundry is a blazing fast, portable and modular toolkit for Ethereum application development written in Rust.**

Foundry consists of:

- **Forge**: Ethereum testing framework (like Truffle, Hardhat and DappTools).
- **Cast**: Swiss army knife for interacting with EVM smart contracts, sending transactions and getting chain data.
- **Anvil**: Local Ethereum node, akin to Ganache, Hardhat Network.
- **Chisel**: Fast, utilitarian, and verbose solidity REPL.

## Documentation

https://book.getfoundry.sh/

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

```shell
$ forge script script/Counter.s.sol:CounterScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```