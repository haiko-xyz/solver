// Core lib imports.
use starknet::ContractAddress;
use core::fmt::{Display, Formatter, Error};

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

pub impl TrendDisplay of Display<Trend> {
    fn fmt(self: @Trend, ref f: Formatter) -> Result<(), Error> {
        let str: ByteArray = match self {
            Trend::Range => "Range",
            Trend::Up => "Up",
            Trend::Down => "Down",
        };
        f.buffer.append(@str);
        Result::Ok(())
    }
}

// Solver market parameters.
//
// * `fee_rate` - swap fee rate applied to swap amounts
// * `base_currency_id` - Pragma oracle base currency id
// * `quote_currency_id` - Pragma oracle quote currency id
// * `min_sources` - minimum number of oracle data sources aggregated
// * `max_age` - maximum age of quoted oracle price
#[derive(Drop, Copy, Serde, PartialEq, Default)]
pub struct MarketParams {
    pub fee_rate: u16,
    // Oracle params
    pub base_currency_id: felt252,
    pub quote_currency_id: felt252,
    pub min_sources: u32,
    pub max_age: u64,
}

// Trend state.
//
// * `cached_price` - last cached oracle price, used in combination with trend to decide whether to quote for bid, ask or both
//    1. if price trends up and price > cached price, quote for bids only (and update cached price)
//    2. if price trends down and price < cached price, quote for asks only (and update cached price)
//    3. otherwise, quote for both
// * `cached_decimals` - decimals of cached oracle price
// * `range` - range of virtual liquidity position
// * `trend` - trend classification
#[derive(Drop, Copy, Serde, PartialEq)]
pub struct ModelParams {
    pub cached_price: u128,
    pub cached_decimals: u32,
    pub range: u32,
    pub trend: Trend,
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
// * `slab0` - `cached_price` (128) + `cached_decimals` (32) + range (32) + `trend` (2)
//             where `trend` is encoded as: `0` (Range), `1` (Up), `2` (Down) 
#[derive(starknet::Store)]
pub struct PackedModelParams {
    pub slab0: felt252,
}
