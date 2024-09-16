// Core lib imports.
use starknet::storage_access::StorePacking;

// Local imports.
use haiko_solver_core::types::{MarketState, FeesPerShare, PackedMarketState, PackedFeesPerShare};

////////////////////////////////
// IMPLS
////////////////////////////////

pub(crate) impl MarketStateStorePacking of StorePacking<MarketState, PackedMarketState> {
    fn pack(value: MarketState) -> PackedMarketState {
        let slab0: felt252 = value.base_reserves.try_into().unwrap();
        let slab1: felt252 = value.quote_reserves.try_into().unwrap();
        let slab2: felt252 = value.base_fees.try_into().unwrap();
        let slab3: felt252 = value.quote_fees.try_into().unwrap();
        let slab4: felt252 = value.vault_token.try_into().unwrap();
        let slab5: felt252 = bool_to_felt(value.is_paused);
        PackedMarketState { slab0, slab1, slab2, slab3, slab4, slab5 }
    }

    fn unpack(value: PackedMarketState) -> MarketState {
        MarketState {
            base_reserves: value.slab0.try_into().unwrap(),
            quote_reserves: value.slab1.try_into().unwrap(),
            base_fees: value.slab2.try_into().unwrap(),
            quote_fees: value.slab3.try_into().unwrap(),
            vault_token: value.slab4.try_into().unwrap(),
            is_paused: felt_to_bool(value.slab5),
        }
    }
}

pub(crate) impl FeesPerShareStorePacking of StorePacking<FeesPerShare, PackedFeesPerShare> {
    fn pack(value: FeesPerShare) -> PackedFeesPerShare {
        let slab0: felt252 = value.base_fps.try_into().unwrap();
        let slab1: felt252 = value.quote_fps.try_into().unwrap();
        PackedFeesPerShare { slab0, slab1 }
    }

    fn unpack(value: PackedFeesPerShare) -> FeesPerShare {
        FeesPerShare {
            base_fps: value.slab0.try_into().unwrap(), quote_fps: value.slab1.try_into().unwrap(),
        }
    }
}

////////////////////////////////
// INTERNAL HELPERS
////////////////////////////////

fn bool_to_felt(value: bool) -> felt252 {
    if value {
        1
    } else {
        0
    }
}

fn felt_to_bool(value: felt252) -> bool {
    value == 1
}
