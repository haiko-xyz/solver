// Core lib imports.
use starknet::syscalls::deploy_syscall;
use starknet::contract_address::contract_address_const;

// Local imports.
use haiko_solver_reversion::types::{MarketParams, TrendState, Trend};
use haiko_solver_reversion::contracts::mocks::store_packing_contract::{
    StorePackingContract, IStorePackingContractDispatcher, IStorePackingContractDispatcherTrait
};

// External imports.
use snforge_std::{declare, ContractClass, ContractClassTrait};

////////////////////////////////
// SETUP
////////////////////////////////

fn before() -> IStorePackingContractDispatcher {
    // Deploy store packing contract.
    let class = declare("StorePackingContract");
    let contract_address = class.deploy(@array![]).unwrap();
    IStorePackingContractDispatcher { contract_address }
}

////////////////////////////////
// TESTS
////////////////////////////////

#[test]
fn test_store_packing_market_params() {
    let store_packing_contract = before();

    let market_params = MarketParams {
        spread: 15,
        range: 15000,
        base_currency_id: 12893128793123,
        quote_currency_id: 128931287,
        min_sources: 12,
        max_age: 3123712,
    };

    store_packing_contract.set_market_params(1, market_params);
    let unpacked = store_packing_contract.get_market_params(1);

    assert(unpacked.spread == market_params.spread, 'Market params: spread');
    assert(unpacked.range == market_params.range, 'Market params: range');
    assert(
        unpacked.base_currency_id == market_params.base_currency_id, 'Market params: base curr id'
    );
    assert(
        unpacked.quote_currency_id == market_params.quote_currency_id,
        'Market params: quote curr id'
    );
    assert(unpacked.min_sources == market_params.min_sources, 'Market params: min sources');
    assert(unpacked.max_age == market_params.max_age, 'Market params: max age');
}

#[test]
fn test_store_packing_trend_state() {
    let store_packing_contract = before();

    let trend_state = TrendState { trend: Trend::Up, cached_price: 1000, cached_decimals: 8, };

    store_packing_contract.set_trend_state(1, trend_state);
    let unpacked = store_packing_contract.get_trend_state(1);

    assert(unpacked.trend == trend_state.trend, 'Trend state: spread');
    assert(unpacked.cached_price == trend_state.cached_price, 'Trend state: range');
    assert(unpacked.cached_decimals == trend_state.cached_decimals, 'Trend state: base curr id');
}