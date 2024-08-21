![solver-banner](https://github.com/user-attachments/assets/e9db3d1f-089a-42fa-9a4f-ebb33815140a)

# Solver

Solvers are a new, improved framework for building Haiko Vaults. They take the best parts of [Strategies](https://haiko-docs.gitbook.io/docs/protocol/strategy-vaults) (e.g. convenience, 1-click automation) and make them simpler, more powerful, and less error-prone.

## Docs

1. [Technical Architecture](./docs/1-technical-architecture.md)
2. [Solver Implementations](./docs/2-solver-implementations.md)
3. [Events](./docs/3-events.md)
4. [Aggregator Integration](./docs/4-aggregator-integration.md)

## Solvers vs Strategies

Whereas Strategies place and update liquidity positions on Haiko's AMM, Solvers are stateless, meaning they never mint any liquidity positions or interact with any AMM. Instead, traders swap directly against liquidity deposited to Solver contracts. Swap quotes are generated on the fly based on an oracle price feed and a set of market configurations.

By using a stateless architecture, Solvers are:

1. **More gas efficient** for LPs and swappers, as they avoid the gas cost of on-chain position storage and rebalancing
2. **Less error-prone**, as they do not rely on external AMM state
3. **More flexible**, as they can be used to create markets based on any pricing formula, not just those adopting Uniswap-style liquidity

In addition, our first [Replicating Solver](./packages/replicating/) introduces powerful new features for LPs:

1. **Zero cost Rebalancing**: Solvers are now constant rebalanced at zero gas cost to swappers and LPs 
2. **Impermanent Loss Caps**: pools can apply a hard cap on impermanent loss by rejecting swaps that bring the pool above its maximum allowed level portfolio skew
3. **Private Vaults**: liquidity providers can now create Private Vaults that are closed to third party depositors and offer greater flexibility over deposit / withdrawals and other admin actions, enabling new use cases such as protocol-owned or liquidity bootstrapping pools
4. **Pool-level Governance**: pool ownership is now tracked via an ERC20 token, enabling micro-governance amongst pool depositors to better optimise pool parameters

![solvers-vs-strategies](https://github.com/user-attachments/assets/c6d884d8-dab5-4030-b0a5-44d4a4ceea81)

There are some key differences between AMM markets and Solver markets. These are summarised in the table below.

| Feature     | AMM / Strategies                | Solver                                                                                                          |
| ----------- | ------------------------------- | --------------------------------------------------------------------------------------------------------------- |
| Swap fees   | Fixed swap fee rate per market  | Agnostic to fee formula, can charge a swap fee, add a dynamic spread on swap quotes, or use another fee formula |
| Tick width  | Fixed tick width per market     | Can accomodate any tick width                                                                                   |
| Price       | Stores current price            | Stateless, does not need to store current price                                                                 |
| Rebalancing | Uses swap hooks for rebalancing | Constantly rebalanced, as positions are calculated on the fly at the point of swap                              |

## Contracts

This monorepo contains both the core solver libraries and contracts (in package `core`) and individual solver implementations (in remaining packages).

### Solver Core ([`core`](./packages/core/))

The `SolverComponent` in the `core` package implements most of the core functionality of a `Solver` contract, including:

1. Creating and managing new solver markets (which comprise of a `base_token` and `quote_token` pair and an `owner`)
2. Managing deposits and withdrawals from solver markets, which are tracked using ERC20 vault tokens for composability
3. Swapping assets through a solver market
4. Managing and collecting withdraw fees (if enabled)
5. Admin actions such as pausing and unpausing, upgrading and transferring ownership of the contract

Solvers currently support two market types:
2. Public Markets, which are open to 3rd party depositors and track ERC20 vault tokens for composability
1. Private Markets, which offer more granular control and flexible access to admin functions

A Solver implementation must:

1. Inherit the base functionality of `SolverComponent`
2. Implement `SolverHooks` which contains methods for generating quotes, minting initial vault liquidity tokens and other callbacks
3. Implement hooks for other components used (e.g. `GovernorHooks` for the `Governor` component used for decentralised governance of pool parameters)

The core `SolverComponent` component will eventually be moved to its own repo to be reused across multiple Solvers. We currently store it as a package under a single monorepo for ease of development.

### Implementations

Solver implementations are standalone contracts that inherits from `SolverComponent` and implement the `SolverHooks` and other trait. You can read more about these implementations [here](./docs/4-solver-implementations.md).

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
