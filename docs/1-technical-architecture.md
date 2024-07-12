# Technical Architecture

This document provides a technical overview of Solvers and the core smart contract functions. It describes the internal call logic of the core `SolverComponent` contract and the `ReplicatingSolver` implementation.

## Solvers vs AMM Strategies

Solvers are standalone smart contracts that accept deposits from liquidity providers (LPs), generate swap quotes based on a quoting strategy, and execute swaps with traders. Unlike Haiko's Strategies which interact with its AMM, Solvers never deposit to interact with an underlying AMM protocol. Rather, solvers directly compute swap amounts on the fly and execute trades atomatically against depositors' positions.

By using a stateless architecture, Solvers are simpler and significantly more gas efficient as compared to strategies.

## Contracts

### `SolverComponent`

The `SolverComponent` contract is a Cairo component that implements the core functionality of solvers. It is responsible for:

1. Creating and managing new solver markets (which comprise of a `base_token` and `quote_token` pair and an `owner`)
2. Managing deposits and withdrawals from solver markets, which are tracked using ERC20 vault tokens for
3. Swapping assets through a solver market
4. Managing and collecting withdraw fees (if enabled)
5. Admin actions such as pausing and unpausing, upgrading and transferring ownership of the contract

### Solver implementations

To be a valid implementation, a Solver contract must:

1. Inherit the base functionality of `SolverComponent`
2. Implement `SolverHooks` which contains methods for generating quotes, minting initial liquidity for new markets, and executing custom logic or state updates after a swap

```rust
#[starknet::interface]
pub trait ISolverHooks<TContractState> {
  // Obtain quote for swap through a market.
  //
  // # Arguments
  // * `market_id` - market id
  // * `swap_params` - swap parameters
  //
  // # Returns
  // * `amount_in` - amount in
  // * `amount_out` - amount out
  fn quote(self: @TContractState, market_id: felt252, swap_params: SwapParams,) -> (u256, u256);

  // Get the initial token supply to mint when first depositing to a market.
  //
  // # Arguments
  // * `market_id` - market id
  //
  // # Returns
  // * `initial_supply` - initial supply
  fn initial_supply(self: @TContractState, market_id: felt252) -> u256;

  // Callback function to execute any state updates after a swap is completed.
  //
  // # Arguments
  // * `market_id` - market id
  // * `swap_params` - swap parameters
  fn after_swap(ref self: TContractState, market_id: felt252, swap_params: SwapParams);
}
```

### `ReplicatingSolver`

The Replicating Solver is a simple Solver that replicates an oracle price feed, plus a spread, to generate bid / ask quotes for a given token pair.

It allows setting a number of configurable parameters for each solver market, including:

1. `min_spread`: a fixed spread added to the oracle price to generate the bid and ask quote
2. `range` : the range of the virtual liquidity position (denominated in number of limits or ticks) used to construct the swap quote, based on Uniswap liquidity formulae
3. `max_delta` : inventory delta, or the single-sided spread applied to an imbalanced portfolio, with the aim of incentivising swappers to rebalance the solver market back to a 50/50 ratio
4. `max_skew` : the maximum allowable skew of base / quote reserves in the solver market, beyond which the solver will not allow swaps unless they improve skew

## Contract interactions

### Creating a solver market

Each solver is a singleton contract that allows for creation of multiple solver markets, all managed by the same contract. A solver market is created by calling `create_market()` through the `ISolver` interface.

```rust
// Create market for solver.
// At the moment, only callable by contract owner to prevent unwanted claiming of markets.
// Each market must be unique in `market_info`.
//
// # Arguments
// * `market_info` - market info
//
// # Returns
// * `market_id` - market id
// * `vault_token` (optional) - vault token address (if public market)
fn create_market(
    ref self: TContractState, market_info: MarketInfo
) -> (felt252, Option<ContractAddress>);

// Identifying information for a solver market.
//
// * `base_token` - base token address
// * `quote_token` - quote token address
// * `owner` - solver market owner address
// * `is_public` - whether market is open to public deposits
struct MarketInfo {
    base_token: ContractAddress,
    quote_token: ContractAddress,
    owner: ContractAddress,
    is_public: bool,
}
```

This creates a market with the provided parameters and assigns a `market_id`, which is simply the Poseidon chain hash of the members of the `MarketInfo `struct.

Duplicate markets are disallowed.

### Depositing or withdrawing

Public solver markets (with `is_public` in `MarketInfo` set to `true`) allow for deposits and withdrawals from multiple third party depositors permissionlessly. Deposits and withdrawals must be made at the same ratio as the current reserve ratio. The distribution of user deposits is tracked using ERC20 vault tokens.

Private solver markets (which have the `is_public` flag set to `false`) only allow the owner to deposit and withdraw. The owner can deposit and withdraw assets at any ratio, as no other depositors are involved and it is not necessary to mint and burn vault tokens to track user shares of deposits.

Liquidity providers can deposit to a solver market by calling `deposit()` (or `deposit_initial()` if no deposits have been made yet), and passing in the relevant `market_id`. Deposits will be capped at the available balance of the caller and coerced to the existing reserve ratio of the vault.

```rust
// Deposit initial liquidity to market.
// Should be used whenever total deposits in a market are zero. This can happen both
// when a market is first initialised, or subsequently whenever all deposits are withdrawn.
//
// # Arguments
// * `market_id` - market id
// * `base_requested` - base asset requested to be deposited
// * `quote_requested` - quote asset requested to be deposited
//
// # Returns
// * `base_deposit` - base asset deposited
// * `quote_deposit` - quote asset deposited
// * `shares` - pool shares minted in the form of liquidity
fn deposit_initial(
    ref self: TContractState, market_id: felt252, base_amount: u256, quote_amount: u256
) -> (u256, u256, u256);

// Deposit liquidity to market.
//
// # Arguments
// * `market_id` - market id
// * `base_requested` - base asset requested to be deposited
// * `quote_requested` - quote asset requested to be deposited
//
// # Returns
// * `base_deposit` - base asset deposited
// * `quote_deposit` - quote asset deposited
// * `shares` - pool shares minted
fn deposit(
    ref self: TContractState, market_id: felt252, base_amount: u256, quote_amount: u256
) -> (u256, u256, u256);
```

Withdrawals can be made either by calling `withdraw_public()` to withdraw from a public vault, or `withdraw_private()` to withdraw an arbitrary amounts from a private vault (available to the vault owner only).

```rust
// Burn pool shares and withdraw funds from market.
// Called for public vaults. For private vaults, use `withdraw_private`.
//
// # Arguments
// * `market_id` - market id
// * `shares` - pool shares to burn
//
// # Returns
// * `base_amount` - base asset withdrawn
// * `quote_amount` - quote asset withdrawn
fn withdraw_public(
    ref self: TContractState, market_id: felt252, shares: u256
) -> (u256, u256);

// Withdraw exact token amounts from market.
// Called for private vaults. For public vaults, use `withdraw_public`.
//
// # Arguments
// * `market_id` - market id
// * `base_amount` - base amount requested
// * `quote_amount` - quote amount requested
//
// # Returns
// * `base_amount` - base asset withdrawn
// * `quote_amount` - quote asset withdrawn
fn withdraw_private(
    ref self: TContractState, market_id: felt252, base_amount: u256, quote_amount: u256
) -> (u256, u256);
```

### Swapping and quoting

A swap is executed when a swapper calls `swap()` in the `MarketManager` contract. Under the hood, this will call `quote()` to obtain a quote for the swap, and then execute the swap.

The `quote()` function is part of the `SolverHooks` interface and should be implemented by each `Solver` contract based on its desried quoting logic and strategy. The `quote()` function returns the amount of input and output tokens for a given swap, which will be fulfilled by the `swap()` function, applying checks for available token amounts.

```rust
// Obtain quote for swap through a market.
//
// # Arguments
// * `market_id` - market id
// * `swap_params` - swap parameters
//
// # Returns
// * `amount_in` - amount in
// * `amount_out` - amount out
fn quote(self: @TContractState, market_id: felt252, swap_params: SwapParams,) -> (u256, u256);

// Swap through a market.
  //
  // # Arguments
  // * `market_id` - market id
  // * `swap_params` - swap parameters
  //
  // # Returns
  // * `amount_in` - amount in
  // * `amount_out` - amount out
  fn swap(ref self: TContractState, market_id: felt252, swap_params: SwapParams,) -> (u256, u256);

// Information about a swap.
//
// * `is_buy` - whether swap is buy or sell
// * `amount` - amount swapped in or out
// * `exact_input` - whether amount is exact input or exact output
struct SwapParams {
    is_buy: bool,
    amount: u256,
    exact_input: bool,
    threshold_sqrt_price: Option<u256>,
    threshold_amount: Option<u256>,
}
```

### Setting and collecting withdraw fees

Solvers are deployed with a contract `owner` that has permission to set and collect withdraw fees for each solver market. Fees are set as a percentage of the withdrawn amount, and can be set and collected by calling `set_withdraw_fee()` and `collect_withdraw_fees()` respectively.

```rust
// Collect withdrawal fees.
// Only callable by contract owner.
//
// # Arguments
// * `receiver` - address to receive fees
// * `token` - token to collect fees for
fn collect_withdraw_fees(
    ref self: TContractState, receiver: ContractAddress, token: ContractAddress
) -> u256;

// Set withdraw fee for a given market.
// Only callable by contract owner.
//
// # Arguments
// * `market_id` - market id
// * `fee_rate` - fee rate
fn set_withdraw_fee(ref self: TContractState, market_id: felt252, fee_rate: u16);
```

### Pausing and unpausing

Similarly, the contract `owner` can pause and unpause the contract by calling `pause()` and `unpause()` respectively.

Pausing is meant to be used in emergency situations to prevent swaps and new deposits from being executed. It does not prevent existing deposits from withdrawing their funds from the contract.

### Contract upgrades

The `Solver` contract can be upgraded by the contract `owner` via the `upgrade()` function, which replaces the class hash of the contract.
