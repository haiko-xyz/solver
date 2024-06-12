# Aggregator Integration

This document provides an overview of the Replicating Solver and highlights some key points for integration with aggregators, focusing on differences as compared to Strategies.

## Overview: Solvers vs Strategies

Solvers are a new product from Haiko that takes the best parts of Strategies and makes them simpler and more gas efficient.

Unlike Strategies, Solvers are standalone smart contracts that generate quotes and execute swaps on demand, without ever depositing to or interacting with an underlying AMM. Rather than executing position updates before swaps, solvers directly compute and quote swap amounts.

By using a stateless architecture, Solvers are significantly more gas efficient compared to strategies.

## Virtual positions

The Replicating Solver accepts deposits and execute swap orders based on the the virtual bid and ask positions placed by each market. These positions are 'virtual' in the sense that they are calculated on the fly and never stored in state.

From an indexing perspective, virtual positions can be harder to track because they change whenever the oracle price changes. That said, as long as aggregators are able to: (1) index deposits and withdrawals, (2) fetch the latest oracle price, and (3) rerun the solver logic, they should be able to eccompute the virtual positions on the fly.

## Error handling

The Replicating Solver has a few error conditions that aggregators should be aware of. In all of the following cases, the solver will reject swaps by throwing an error:

1. Zero liquidity: the solver has zero liquidity on one or both sides of the market
2. Paused: the solver is paused
3. Max skew: an incoming swap or deposit would cause the solver to exceed the maximum skew

Aggregators should add logic to detect these errors and exclude the solver from the swap quote to prevent failed transactions.
