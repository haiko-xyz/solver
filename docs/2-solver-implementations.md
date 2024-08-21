# Solver Implementations

This document describes the solver implementations currently in development.

## Replicating Solver ([`replicating`](../packages/replicating/))

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

## Reversion Solver ([`reversion`](../packages/reversion/))

The Reversion Solver, under the `reversion` package, is the second Solver in development. It operates on a trend classification model (`Up`, `Down` or `Ranging`) to provide liquidity against the trend, capturing fees on trend reversion.

Positions automatically follow the price of an asset, updated on either single or double-sided price action, depending on the prevailing trend. It is inspired by [Maverick Protocol](https://www.mav.xyz/)'s Left and Right modes and enables liquidity provision in both volatile and stable market conditions.

The trend classification is determined by an off-chain zkML model executed trustlessly and brough on-chain via [Giza](https://www.gizatech.xyz/) Agents.

Like the Replicating Solver, the Reversion solver can create a market for any token pair by providing bid and ask quotes based on a Pragma oracle price feed. It is designed as a singleton contract, and allows liquidity providers to provide liquidity programmatically, without having to actively manage their positions.
