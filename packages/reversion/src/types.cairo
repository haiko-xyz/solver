// Core lib imports.
use starknet::ContractAddress;

////////////////////////////////
// TYPES
////////////////////////////////

// Classification of price trend.
//
// * `Range` - price is ranging
// * `Up` - price is trending up
// * `Down` - price is trending down
#[derive(Drop, Copy, Serde, Default, PartialEq)]
pub enum Trend {
    #[default]
    Range,
    Up,
    Down,
}

// Solver market parameters.
//
// * `fee_rate` - swap fee rate applied to swap amounts
// * `range` - default range of spread applied on an imbalanced portfolio
// * `base_currency_id` - Pragma oracle base currency id
// * `quote_currency_id` - Pragma oracle quote currency id
// * `min_sources` - minimum number of oracle data sources aggregated
// * `max_age` - maximum age of quoted oracle price
#[derive(Drop, Copy, Serde, PartialEq)]
pub struct MarketParams {
    pub fee_rate: u16,
    pub range: u32,
    // Oracle params
    pub base_currency_id: felt252,
    pub quote_currency_id: felt252,
    pub min_sources: u32,
    pub max_age: u64,
}

// Trend state.
//
// * `trend` - trend classification
// * `cached_price` - last cached oracle price, used in combination with trend to decide whether to quote for bid, ask or both
//    1. if price trends up and price > cached price, quote for bids only (and update cached price)
//    2. if price trends down and price < cached price, quote for asks only (and update cached price)
//    3. otherwise, quote for both
// * `cached_decimals` - decimals of cached oracle price
#[derive(Drop, Copy, Serde, PartialEq)]
pub struct TrendState {
    pub trend: Trend,
    pub cached_price: u128,
    pub cached_decimals: u32,
}

////////////////////////////////
// PACKED TYPES
////////////////////////////////

// Packed market parameters.
//
// * `slab0` - base currency id
// * `slab1` - quote currency id
// * `slab2` - `fee_rate` + `range` + `min_sources` + `max_age`
#[derive(starknet::Store)]
pub struct PackedMarketParams {
    pub slab0: felt252,
    pub slab1: felt252,
    pub slab2: felt252
}

// Packed trend state.
//
// * `slab0` - `cached_price` (128) + `cached_decimals` (32) + `trend` (2)
//             where `trend` is encoded as: `0` (Range), `1` (Up), `2` (Down) 
#[derive(starknet::Store)]
pub struct PackedTrendState {
    pub slab0: felt252,
}
