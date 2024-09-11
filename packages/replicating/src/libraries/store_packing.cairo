// Core lib imports.
use starknet::storage_access::StorePacking;

// Local imports.
use haiko_solver_replicating::types::{MarketParams, PackedMarketParams};

////////////////////////////////
// CONSTANTS
////////////////////////////////

const TWO_POW_32: felt252 = 0x100000000;
const TWO_POW_64: felt252 = 0x10000000000000000;
const TWO_POW_96: felt252 = 0x1000000000000000000000000;
const TWO_POW_112: felt252 = 0x10000000000000000000000000000;
const TWO_POW_144: felt252 = 0x1000000000000000000000000000000000000;

const MASK_1: u256 = 0x1;
const MASK_16: u256 = 0xffff;
const MASK_32: u256 = 0xffffffff;
const MASK_64: u256 = 0xffffffffffffffff;

////////////////////////////////
// IMPLS
////////////////////////////////

pub(crate) impl MarketParamsStorePacking of StorePacking<MarketParams, PackedMarketParams> {
    fn pack(value: MarketParams) -> PackedMarketParams {
        let mut slab2: u256 = value.fee_rate.into();
        slab2 += value.range.into() * TWO_POW_32.into();
        slab2 += value.max_delta.into() * TWO_POW_64.into();
        slab2 += value.max_skew.into() * TWO_POW_96.into();
        slab2 += value.min_sources.into() * TWO_POW_112.into();
        slab2 += value.max_age.into() * TWO_POW_144.into();

        PackedMarketParams {
            slab0: value.base_currency_id,
            slab1: value.quote_currency_id,
            slab2: slab2.try_into().unwrap(),
        }
    }

    fn unpack(value: PackedMarketParams) -> MarketParams {
        let slab2: u256 = value.slab2.into();
        let fee_rate: u16 = (slab2 & MASK_16).try_into().unwrap();
        let range: u32 = ((slab2 / TWO_POW_32.into()) & MASK_32).try_into().unwrap();
        let max_delta: u32 = ((slab2 / TWO_POW_64.into()) & MASK_32).try_into().unwrap();
        let max_skew: u16 = ((slab2 / TWO_POW_96.into()) & MASK_16).try_into().unwrap();
        let min_sources: u32 = ((slab2 / TWO_POW_112.into()) & MASK_32).try_into().unwrap();
        let max_age: u64 = ((slab2 / TWO_POW_144.into()) & MASK_64).try_into().unwrap();

        MarketParams {
            fee_rate,
            range,
            max_delta,
            max_skew,
            base_currency_id: value.slab0,
            quote_currency_id: value.slab1,
            min_sources,
            max_age
        }
    }
}
