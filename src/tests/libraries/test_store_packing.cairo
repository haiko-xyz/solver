// Core lib imports.
use starknet::syscalls::deploy_syscall;
use starknet::contract_address::contract_address_const;

// Local imports.
use haiko_solver_replicating::contracts::mocks::store_packing_contract::{
    StorePackingContract, IStorePackingContractDispatcher, IStorePackingContractDispatcherTrait
};
use haiko_solver_replicating::types::{replicating::MarketParams, core::MarketState};

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
        min_spread: 15,
        range: 15000,
        max_delta: 2532,
        max_skew: 8888,
        base_currency_id: 12893128793123,
        quote_currency_id: 128931287,
        min_sources: 12,
        max_age: 3123712,
    };

    store_packing_contract.set_market_params(1, market_params);
    let unpacked = store_packing_contract.get_market_params(1);

    assert(unpacked.min_spread == market_params.min_spread, 'Market params: min spread');
    assert(unpacked.range == market_params.range, 'Market params: range');
    assert(unpacked.max_delta == market_params.max_delta, 'Market params: max delta');
    assert(unpacked.max_skew == market_params.max_skew, 'Market params: max skew');
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
fn test_store_packing_market_state() {
    let store_packing_contract = before();

    let market_state = MarketState {
        base_reserves: 1389123122000000000000000000000,
        quote_reserves: 2401299999999999999999999999999,
        is_paused: false,
        vault_token: contract_address_const::<0x123>(),
    };

    store_packing_contract.set_market_state(1, market_state);
    let unpacked = store_packing_contract.get_market_state(1);

    assert(unpacked.base_reserves == market_state.base_reserves, 'Market state: base reserves');
    assert(unpacked.quote_reserves == market_state.quote_reserves, 'Market state: quote reserves');
    assert(unpacked.is_paused == market_state.is_paused, 'Market state: is paused');
    assert(unpacked.vault_token == market_state.vault_token, 'Market state: vault token');
}
