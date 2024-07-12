# Haiko Solver

## Solvers vs Strategies

Solvers are an improved version of Haiko strategies. They take the best parts of strategies and make them simpler, more efficient, and less error-prone.

Unlike Strategies, Solvers are standalone smart contracts that generate quotes and execute swaps on demand, without ever depositing to or interacting with an underlying AMM. Rather than rebalancing positions on an AMM, solvers directly compute swap amounts on the fly and execute trades against depositors' positions.

By using a stateless architecture, Solvers are:

- Significantly more gas efficient for LPs and swappers, avoiding the gas cost of position storage and rebalancing
- Less error-prone, as they do not rely on external AMM state
- More flexible, as they can be used to create markets based on any pricing formula, not just those adopting Uniswap-style liquidity

AMM liquidity positions earn fees by charging a swap fee rate on swaps. Solvers earn fees by adding a spread to the amount quoted for swaps. Given the same spread and swap fee rate, the two approaches are approximately equivalent.

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
2. Implement `SolverQuoter` which contains methods for generating quotes and minting initial vault liquidity tokens

The core `SolverComponent` component will eventually be moved to its own repo to be reused across multiple Solvers. We currently store it as a package under a single monorepo for ease of development.

### Replicating Solver ([`replicating`](./packages/replicating/))

The Replicating Solver, under the `replicating` package, is the first Solver in development. It creates a market for any token pair by providing bid and ask quotes based on a Pragma oracle price feed. It allows liquidity providers to provide liquidity programmatically, without having to actively manage their positions.

The Solver executes swap orders based on the the virtual bid and ask positions placed by each market. These positions are 'virtual' in that they are calculated on the fly and never stored in state.

It is designed as a singleton contract supporting multiple solver markets, each with their own configuration. Solver markets can also be optionally owned. Market owners gain access to enhanced functionality, such as setting market parameters and pausing / unpausing the contract.

The solver market configs are as follows:

1. Owner: address that controls market configurations, pausing, and ownership transfers
2. Min spread: spread applied to the oracle price to calculate the bid and ask prices
3. Range: the range of the virtual liquidity position, which affects the execution slippage of the swap
4. Max delta: the delta (or offset) applied to bid and ask prices to correct for inventory skew
5. Max skew: the maximum portfolio skew of the market, above which swaps will be rejected

Max skew is a new parameter that did not exist in the Replicating Strategy. It is a hard cap applied to the skew of the pool, above which swaps are rejected. This explicitly prevents the pool from becoming overly imbalanced.

In addition, Solvers now support two market types: (1) Private Markets, a new market type which offer more granular control for a single depositor, and (2) Public Markets, which are open to 3rd party depositors and track ERC20 vault tokens for composability.

### Reversion Solver ([`reversion`](./packages/reversion/))

The Reversion Solver, under the `reversion` package, is the second Solver in development. It operates on a trend classification model (`Up`, `Down` or `Ranging`) to provide liquidity against the trend, capturing fees on trend reversion.

Positions automatically follow the price of an asset, updated on either single or double-sided price action, depending on the prevailing trend. It is inspired by [Maverick Protocol](https://www.mav.xyz/)'s Left and Right modes and enables liquidity provision in both volatile and stable market conditions.

The trend classification is determined by an off-chain zkML model executed trustlessly and brough on-chain via [Giza](https://www.gizatech.xyz/) Agents.

Like the Replicating Solver, the Reversion solver can create a market for any token pair by providing bid and ask quotes based on a Pragma oracle price feed. It is designed as a singleton contract, and allows liquidity providers to provide liquidity programmatically, without having to actively manage their positions.

## Docs

1. [Technical Architecture](./docs/1-technical-architecture.md)
2. [Aggregator Integration](./docs/2-aggregator-integration.md)

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
