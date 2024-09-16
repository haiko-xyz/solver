// Core lib imports.
use starknet::ContractAddress;

////////////////////////////////
// TYPES
////////////////////////////////

// Solver market parameters.
//
// * `fee_rate` - swap fee rate (base 10000)
// * `range` - default range of spread applied on an imbalanced portfolio
// * `max_delta` - inventory delta, or the max additional single-sided spread applied on an imbalanced portfolio
// * `max_skew` - max skew of the portfolio (out of 10000)
// * `base_currency_id` - Pragma oracle base currency id
// * `quote_currency_id` - Pragma oracle quote currency id
// * `min_sources` - minimum number of oracle data sources aggregated
// * `max_age` - maximum age of quoted oracle price
#[derive(Drop, Copy, Serde, PartialEq, Default)]
pub struct MarketParams {
    pub fee_rate: u16,
    pub range: u32,
    pub max_delta: u32,
    pub max_skew: u16,
    // Oracle params
    pub base_currency_id: felt252,
    pub quote_currency_id: felt252,
    pub min_sources: u32,
    pub max_age: u64,
}

////////////////////////////////
// PACKED TYPES
////////////////////////////////

// Packed market parameters.
//
// * `slab0` - base currency id
// * `slab1` - quote currency id
// * `slab2` - `fee_rate` + `range` + `max_delta` + `max_skew` + `min_sources` + `max_age`
#[derive(starknet::Store)]
pub struct PackedMarketParams {
    pub slab0: felt252,
    pub slab1: felt252,
    pub slab2: felt252
}
