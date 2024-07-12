# Events

This document describes the key events emitted by solver smart contracts for off-chain indexing and querying.

## `Solver`

The following events are emitted by all solver implementations.

### `CreateMarket`

This event is emitted when a new pool / market is created. Markets are identified by `market_id`.`CreateMarket` events should be indexed to track the active markets in a solver.

```rust
pub struct CreateMarket {
    #[key]
    pub market_id: felt252,
    pub base_token: ContractAddress,
    pub quote_token: ContractAddress,
    pub owner: ContractAddress,
    pub is_public: bool,
    pub vault_token: ContractAddress,
}
```

- `market_id` is the Poseidon chain hash of the market parameters below (`base_token`, `quote_token`, `owner`, `is_public`, `vault_token`)
- `base_token` is the address of the base token for the market
- `quote_token` is the address of the quote token for the market
- `owner` is the address of the market owner
- `is_public` is a boolean indicating if the market is open to third party LPs / depositors
- `vault_token` is the address of the token used to track LP shares in the market

### `Swap`

This event is emitted when a swap is executed through a solver market. These events can be indexed along with `Deposit` and `Withdraw` events to track the total liquidity in a solver market.

```rust
pub struct Swap {
  #[key]
  pub market_id: felt252,
  #[key]
  pub caller: ContractAddress,
  pub is_buy: bool,
  pub exact_input: bool,
  pub amount_in: u256,
  pub amount_out: u256,
}
```

- `market_id` is the unique id of the market (see `CreateMarket` above)
- `caller` is the address of the user executing the swap
- `is_buy` is a boolean indicating if the swap is a buy or sell
- `exact_input` is a boolean indicating if the swap amount was specified as input or output
- `amount_in` is the amount of the input token swapped in
- `amount_out` is the amount of the output token swapped out

### `Deposit` / `Withdraw`

These events are emitted whenever a user / LP deposits or withdraws liquidity from a solver market. These events can be indexed along with `Swap` events to track the total liquidity in a solver market.

```rust
pub struct Deposit {
    #[key]
    pub caller: ContractAddress,
    #[key]
    pub market_id: felt252,
    pub base_amount: u256,
    pub quote_amount: u256,
    pub shares: u256,
}
```

- `caller` is the address of the user / LP depositing liquidity
- `market_id` is the unique id of the market (see `CreateMarket` above)
- `base_amount` is the amount of base tokens deposited
- `quote_amount` is the amount of quote tokens deposited
- `shares` is the amount of LP shares minted or burned

### `Pause` / `Unpause`

These events are emitted when a market is paused and unpaused. Paused markets should not accrue rewards as they will reject incoming swaps. These events can be indexed to track the paused state of solver markets.

```rust
pub struct Pause {
    #[key]
    pub market_id: felt252,
}
```

```rust
pub struct Unpause {
    #[key]
    pub market_id: felt252,
}
```

## `ReplicatingSolver`

The following events are unique to the `ReplicatingSolver` implementation.

### `SetMarketParams`

This event is emitted when a solver market's parameters are updated by its owner. These market parameters are used to query the relevant oracle price feed from Pragma and transform this price into (virtual) bid and ask liquidity positions, against which incoming swaps are executed.

[This](../packages/replicating/src/libraries/spread_math.cairo) file contains the core logic for transforming market parameters into virtual bid and ask positions.

`SetMarketParams` events should be indexed to track the active market parameters of a solver market and reconstruct the quote price for the solver market.

```rust
pub(crate) struct SetMarketParams {
    #[key]
    pub market_id: felt252,
    pub min_spread: u32,
    pub range: u32,
    pub max_delta: u32,
    pub max_skew: u16,
    pub base_currency_id: felt252,
    pub quote_currency_id: felt252,
    pub min_sources: u32,
    pub max_age: u64,
}
```

- `market_id` is the unique id of the market (see `CreateMarket` above)
- `min_spread` is the spread, denominated in limits (1.00001 or 0.001% tick) added to the oracle price to arrive at the bid upper or ask lower price
- `range` is the range, denominated in limits, of the virtual liquidity position that the swap is executed over (we apply the same calculations as Uniswap liquidity positions). The bid lower price is calculated by as `bid_upper - range`, and the ask upper price is calculated as `ask_lower + range`
- `max_delta` is a dynamic shift applied to the bid and ask prices in the event of a skew in the composition of the pool (e.g. if the pool is 90% ETH and 10% DAI, the price of ETH will be shifted by `skew * max_delta` to incentivise swappers to move the pool back to 50/50 ratio)
- `max_skew` is a hard cap applied to the skew of the pool, above which swaps are rejected
- `base_currency_id` is the Pragma ID of the base token
- `quote_currency_id` is the Pragma ID of the quote token
- `min_sources` is the minimum number of oracle sources for the oracle price to be considered valid, below which swaps are rejected
- `max_age` is the maximum age of the oracle price, above which swaps are rejected
