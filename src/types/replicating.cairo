// Core lib imports.
use starknet::ContractAddress;

////////////////////////////////
// TYPES
////////////////////////////////

// Identifying market information.
//
// * `base_token` - base token address
// * `quote_token` - quote token address
// * `owner` - solver market owner address
// * `is_public` - whether market is open to public deposits
#[derive(Copy, Drop, Serde, starknet::Store)]
pub struct MarketInfo {
    pub base_token: ContractAddress,
    pub quote_token: ContractAddress,
    pub owner: ContractAddress,
    pub is_public: bool,
}

// Solver market parameters.
//
// * `min_spread` - default spread between reference price and bid/ask price
// * `range` - default range of spread applied on an imbalanced portfolio
// * `max_delta` - inventory delta, or the max additional single-sided spread applied on an imbalanced portfolio
// * `max_skew` - max skew of the portfolio (out of 10000)
// * `base_currency_id` - Pragma oracle base currency id
// * `quote_currency_id` - Pragma oracle quote currency id
// * `min_sources` - minimum number of oracle data sources aggregated
// * `max_age` - maximum age of quoted oracle price
#[derive(Drop, Copy, Serde, PartialEq)]
pub struct MarketParams {
    pub min_spread: u32,
    pub range: u32,
    pub max_delta: u32,
    pub max_skew: u16,
    // Oracle params
    pub base_currency_id: felt252,
    pub quote_currency_id: felt252,
    pub min_sources: u32,
    pub max_age: u64,
}

// Solver market state.
//
// * `base_reserves` - base reserves
// * `quote_reserves` - quote reserves
// * `is_paused` - whether market is paused
// * `vault_token` - vault token (or 0 if unset)
#[derive(Drop, Copy, Serde)]
pub struct MarketState {
    pub base_reserves: u256,
    pub quote_reserves: u256,
    pub is_paused: bool,
    pub vault_token: ContractAddress,
}

// Virtual liquidity position.
//
// * `lower_sqrt_price` - lower limit of position
// * `upper_sqrt_price` - upper limit of position
// * `liquidity` - liquidity of position
#[derive(Drop, Copy, Serde, Default, PartialEq)]
pub struct PositionInfo {
    pub lower_sqrt_price: u256,
    pub upper_sqrt_price: u256,
    pub liquidity: u128,
}

////////////////////////////////
// PACKED TYPES
////////////////////////////////

// Packed market parameters.
//
// * `slab0` - base currency id
// * `slab1` - quote currency id
// * `slab2` - `min_spread` + `range` + `max_delta` + `max_skew` + `min_sources` + `max_age`
#[derive(starknet::Store)]
pub struct PackedMarketParams {
    pub slab0: felt252,
    pub slab1: felt252,
    pub slab2: felt252
}

// Packed market state.
//
// * `slab0` - base reserves (coerced to felt252)
// * `slab1` - quote reserves (coerced to felt252)
// * `slab2` - vault_token
// * `slab3` - is_paused
#[derive(starknet::Store)]
pub struct PackedMarketState {
    pub slab0: felt252,
    pub slab1: felt252,
    pub slab2: felt252,
    pub slab3: felt252
}
