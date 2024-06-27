# Haiko Replicating Solver

The Replicating Solver creates a market for any token pair by providing bid and ask quotes based on a Pragma oracle price feed. It allows liquidity providers to provide liquidity programmatically, without having to actively manage their positions.

## Solvers vs Strategies

Solvers are a new product from Haiko. They are similar to strategies, but are simpler and significantly more gas efficient.

Unlike Strategies, Solvers are standalone smart contracts that generate quotes and execute swaps on demand, without ever depositing to or interacting with an underlying AMM. Rather than executing position updates before swaps, solvers directly compute and quote swap amounts, and execute trades atomatically against the depositors' positions.

By using a stateless architecture, Solvers are significantly more gas efficient compared to strategies.

## Architecture

### Solvers

The `SolverComponent` is a implements most of the base functionality of a Solver contract. To create a new Solver, a smart contract must:

1. Use `SolverComponent` to inherit the base functionality
2. Implement `SolverQuoter` which contains methods for generating quotes and constructing the virtual positions over which swaps are executed

The core `SolverComponent` contract will later be moved to its own package to be reused across multiple Solvers.

### Replicating Solver

The Replicating Solver accepts deposits and executes swap orders based on the the virtual bid and ask positions placed by each market. These positions are 'virtual' in that they are calculated on the fly and never stored in state.

It is designed as a singleton contract supporting multiple markets, each with their own configuration and (optionally) owners, which can perform operations such as setting market parameters and pausing / unpausing the contract:

1. Owner: address that controls market configurations, pausing, and ownership transfers
2. Min spread: spread applied to the oracle price to calculate the bid and ask prices
3. Range: the range of the virtual liquidity position, which affects the execution slippage of the swap
4. Max delta: the delta (or offset) applied to bid and ask prices to correct for inventory skew
5. Max skew: the maximum portfolio skew of the market, above which swaps will be rejected

As with Strategies, LPs can deposit to Solvers to have their liquidity automatically managed.

The Replicating Solver currently support two markets types, a private market that offers more granular control, and a public market that is open to multiple 3rd party depositors. Public deposits are tracked using ERC20 vault tokens for composability.

## Docs

1. [Test Cases](./docs/1-test-cases.md)
2. [Aggregator Integration](./docs/2-aggregator-integration.md)

## Getting started

```shell
# Run the tests
snforge test

# Build contracts
scarb build
```

## Version control

- [Scarb](https://github.com/software-mansion/scarb) 2.6.3
- [Cairo](https://github.com/starkware-libs/cairo) 2.6.3
- [Starknet Foundry](https://github.com/foundry-rs/starknet-foundry) 0.21.0
- [OpenZeppelin Contracts](https://github.com/OpenZeppelin/cairo-contracts/) 0.11.0
