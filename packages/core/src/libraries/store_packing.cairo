// Core lib imports.
use starknet::storage_access::StorePacking;

// Local imports.
use haiko_solver_core::types::{MarketState, PackedMarketState};

////////////////////////////////
// IMPLS
////////////////////////////////

pub(crate) impl MarketStateStorePacking of StorePacking<MarketState, PackedMarketState> {
    fn pack(value: MarketState) -> PackedMarketState {
        let slab0: felt252 = value.base_reserves.try_into().unwrap();
        let slab1: felt252 = value.quote_reserves.try_into().unwrap();
        let slab2: felt252 = value.vault_token.try_into().unwrap();
        let slab3: felt252 = bool_to_felt(value.is_paused);
        PackedMarketState { slab0, slab1, slab2, slab3 }
    }

    fn unpack(value: PackedMarketState) -> MarketState {
        MarketState {
            base_reserves: value.slab0.try_into().unwrap(),
            quote_reserves: value.slab1.try_into().unwrap(),
            vault_token: value.slab2.try_into().unwrap(),
            is_paused: felt_to_bool(value.slab3),
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
