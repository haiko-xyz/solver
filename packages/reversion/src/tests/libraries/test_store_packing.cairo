// Core lib imports.
use starknet::syscalls::deploy_syscall;
use starknet::contract_address::contract_address_const;

// Local imports.
use haiko_solver_reversion::types::{MarketParams, ModelParams, Trend};
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
        fee_rate: 15,
        base_currency_id: 12893128793123,
        quote_currency_id: 128931287,
        min_sources: 12,
        max_age: 3123712,
    };

    store_packing_contract.set_market_params(1, market_params);
    let unpacked = store_packing_contract.get_market_params(1);

    assert(unpacked.fee_rate == market_params.fee_rate, 'Market params: fee rate');
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
fn test_store_packing_model_params() {
    let store_packing_contract = before();

    let model_params = ModelParams {
        cached_price: 1000, cached_decimals: 8, range: 15000, trend: Trend::Up
    };

    store_packing_contract.set_model_params(1, model_params);
    let unpacked = store_packing_contract.get_model_params(1);

    assert(unpacked.cached_price == model_params.cached_price, 'Trend state: range');
    assert(unpacked.cached_decimals == model_params.cached_decimals, 'Trend state: base curr id');
    assert(unpacked.range == model_params.range, 'Trend state: range');
    assert(unpacked.trend == model_params.trend, 'Trend state: spread');
}
