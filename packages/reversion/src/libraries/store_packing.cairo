// Core lib imports.
use starknet::storage_access::StorePacking;

// Local imports.
use haiko_solver_reversion::types::{
    Trend, MarketParams, ModelParams, PackedMarketParams, PackedModelParams
};

////////////////////////////////
// CONSTANTS
////////////////////////////////

const TWO_POW_16: felt252 = 0x10000;
const TWO_POW_48: felt252 = 0x1000000000000;
const TWO_POW_128: felt252 = 0x100000000000000000000000000000000;
const TWO_POW_160: u256 = 0x10000000000000000000000000000000000000000;
const TWO_POW_192: u256 = 0x1000000000000000000000000000000000000000000000000;


const MASK_1: u256 = 0x1;
const MASK_2: u256 = 0x3;
const MASK_16: u256 = 0xffff;
const MASK_32: u256 = 0xffffffff;
const MASK_64: u256 = 0xffffffffffffffff;
const MASK_128: u256 = 0xffffffffffffffffffffffffffffffff;

////////////////////////////////
// IMPLS
////////////////////////////////

pub impl MarketParamsStorePacking of StorePacking<MarketParams, PackedMarketParams> {
    fn pack(value: MarketParams) -> PackedMarketParams {
        let mut slab2: u256 = value.fee_rate.into();
        slab2 += value.min_sources.into() * TWO_POW_16.into();
        slab2 += value.max_age.into() * TWO_POW_48.into();

        PackedMarketParams {
            slab0: value.base_currency_id,
            slab1: value.quote_currency_id,
            slab2: slab2.try_into().unwrap(),
        }
    }

    fn unpack(value: PackedMarketParams) -> MarketParams {
        let slab2: u256 = value.slab2.into();
        let fee_rate: u16 = (slab2 & MASK_16).try_into().unwrap();
        let min_sources: u32 = ((slab2 / TWO_POW_16.into()) & MASK_32).try_into().unwrap();
        let max_age: u64 = ((slab2 / TWO_POW_48.into()) & MASK_32).try_into().unwrap();

        MarketParams {
            fee_rate,
            base_currency_id: value.slab0,
            quote_currency_id: value.slab1,
            min_sources,
            max_age
        }
    }
}

pub impl ModelParamsStorePacking of StorePacking<ModelParams, PackedModelParams> {
    fn pack(value: ModelParams) -> PackedModelParams {
        let mut slab0: u256 = value.cached_price.into();
        slab0 += value.cached_decimals.into() * TWO_POW_128.into();
        slab0 += value.range.into() * TWO_POW_160.into();
        slab0 += trend_to_u256(value.trend) * TWO_POW_192.into();

        PackedModelParams { slab0: slab0.try_into().unwrap() }
    }

    fn unpack(value: PackedModelParams) -> ModelParams {
        let slab0: u256 = value.slab0.into();
        let cached_price: u128 = (slab0 & MASK_128).try_into().unwrap();
        let cached_decimals: u32 = ((slab0 / TWO_POW_128.into()) & MASK_32).try_into().unwrap();
        let range: u32 = ((slab0 / TWO_POW_160.into()) & MASK_32).try_into().unwrap();
        let trend: Trend = u256_to_trend((value.slab0.into() / TWO_POW_192.into()) & MASK_2);

        ModelParams { cached_price, cached_decimals, range, trend }
    }
}

////////////////////////////////
// HELPERS
////////////////////////////////

fn trend_to_u256(trend: Trend) -> u256 {
    match trend {
        Trend::Range => 0,
        Trend::Up => 1,
        Trend::Down => 2,
    }
}

fn u256_to_trend(value: u256) -> Trend {
    if value == 1 {
        return Trend::Up(());
    }
    if value == 2 {
        return Trend::Down(());
    }
    Trend::Range(())
}
