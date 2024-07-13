![solver-banner](https://github.com/user-attachments/assets/e9db3d1f-089a-42fa-9a4f-ebb33815140a)

# Solver

Solvers are the new, improved version of Haiko [Strategies](https://haiko-docs.gitbook.io/docs/protocol/strategy-vaults). They take the best parts of Strategies (e.g. convenience, 1-click automation) and make them simpler, more efficient, and less error-prone.

## Docs

1. [Technical Architecture](./docs/1-technical-architecture.md)
2. [Solver Implementations](./docs/2-solver-implementations.md)
3. [Events](./docs/3-events.md)
4. [Aggregator Integration](./docs/4-aggregator-integration.md)

## Solvers vs Strategies

Unlike Strategies, Solvers are standalone smart contracts that generate quotes and execute swaps on demand, without depositing to or interacting with an underlying AMM. Rather than managing and rebalancing static AMM positions, solvers directly compute swap amounts on the fly, executing trades against deposited reserves.

By using a stateless architecture, Solvers are:

1. **More gas efficient** for LPs and swappers, as they avoid the gas cost of on-chain position storage and rebalancing
2. **Less error-prone**, as they do not rely on external AMM state
3. **More flexible**, as they can be used to create markets based on any pricing formula, not just those adopting Uniswap-style liquidity

![solvers-vs-strategies](https://github.com/user-attachments/assets/c6d884d8-dab5-4030-b0a5-44d4a4ceea81)

There are some key differences between AMM markets and Solver markets. These are summarised in the table below.

| Feature     | AMM / Strategies                | Solver                                                                      |
| ----------- | ------------------------------- | --------------------------------------------------------------------------- |
| Swap fees   | Fixed swap fee rate per market  | Charges a dynamic spread on swaps instead of an explicit swap fee rate      |
| Tick width  | Fixed tick width per market     | Agnostic to pricing formula, can accomodate any tick width                  |
| Price       | Stores current price            | Stateless, does not need to store current price                             |
| Rebalancing | Uses swap hooks for rebalancing | No rebalancing needed, calculates positions on the fly at the point of swap |

## Contracts

This monorepo contains both the core solver libraries and contracts (in package `core`) and individual solver implementations (in remaining packages).

### Solver Core ([`core`](./packages/core/))

The `SolverComponent` in the `core` package implements most of the core functionality of a `Solver` contract, including:

1. Creating and managing new solver markets (which comprise of a `base_token` and `quote_token` pair and an `owner`)
2. Managing deposits and withdrawals from solver markets, which are tracked using ERC20 vault tokens for composability
3. Swapping assets through a solver market
4. Managing and collecting withdraw fees (if enabled)
5. Admin actions such as pausing and unpausing, upgrading and transferring ownership of the contract

Solvers currently support two market types: (1) Private Markets, which offer more granular control, and (2) Public Markets, which are open to 3rd party depositors and track ERC20 vault tokens for composability.

A Solver implementation must:

1. Inherit the base functionality of `SolverComponent`
2. Implement `SolverHooks` which contains methods for generating quotes and minting initial vault liquidity tokens

The core `SolverComponent` component will eventually be moved to its own repo to be reused across multiple Solvers. We currently store it as a package under a single monorepo for ease of development.

### Implementations

Solver implementations are standalone contracts that inherits from `SolverComponent` and implement the `SolverHooks` trait. You can read more about these implementations [here](./docs/4-solver-implementations.md).

| Solver      | Description                                                               | Package                                  |
| ----------- | ------------------------------------------------------------------------- | ---------------------------------------- |
| Replicating | Quotes based on Pragma oracle price feed                                  | [`replicating`](./packages/replicating/) |
| Reversion   | Uses a zkML trend classifier to capture fees / spreads on trend reversion | [`reversion`](./packages/reversion/)     |

## Getting started

```shell
# Build contracts
scarb build

# Run the tests
snforge test
```

## Version control

- [Scarb](https://github.com/software-mansion/scarb) 2.6.3
- [Cairo](https://github.com/starkware-libs/cairo) 2.6.3
- [Starknet Foundry](https://github.com/foundry-rs/starknet-foundry) 0.21.0
- [OpenZeppelin Contracts](https://github.com/OpenZeppelin/cairo-contracts/) 0.11.0
