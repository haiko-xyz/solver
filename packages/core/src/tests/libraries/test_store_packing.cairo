// Core lib imports.
use starknet::syscalls::deploy_syscall;
use starknet::contract_address::contract_address_const;

// Local imports.
use haiko_solver_core::types::{MarketState, FeesPerShare};
use haiko_solver_core::contracts::mocks::store_packing_contract::{
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
fn test_store_packing_market_state() {
    let store_packing_contract = before();

    let market_state = MarketState {
        base_reserves: 1389123122000000000000000000000,
        quote_reserves: 2401299999999999999999999999999,
        base_fees: 381289131303000000,
        quote_fees: 1000000000000000000,
        is_paused: false,
        vault_token: contract_address_const::<0x123>(),
    };

    store_packing_contract.set_market_state(1, market_state);
    let unpacked = store_packing_contract.get_market_state(1);

    assert(unpacked.base_reserves == market_state.base_reserves, 'Market state: base reserves');
    assert(unpacked.quote_reserves == market_state.quote_reserves, 'Market state: quote reserves');
    assert(unpacked.base_fees == market_state.base_fees, 'Market state: base fees');
    assert(unpacked.quote_fees == market_state.quote_fees, 'Market state: quote fees');
    assert(unpacked.is_paused == market_state.is_paused, 'Market state: is paused');
    assert(unpacked.vault_token == market_state.vault_token, 'Market state: vault token');
}

#[test]
fn test_store_packing_fees_per_share() {
    let store_packing_contract = before();

    let fees_per_share = FeesPerShare {
        base_fps: 1389123122000000000, quote_fps: 240129999999999999,
    };

    store_packing_contract.set_fees_per_share(1, fees_per_share);
    let unpacked = store_packing_contract.get_fees_per_share(1);

    assert(unpacked.base_fps == fees_per_share.base_fps, 'Fees per share: base fps');
    assert(unpacked.quote_fps == fees_per_share.quote_fps, 'Fees per share: quote fps');
}
