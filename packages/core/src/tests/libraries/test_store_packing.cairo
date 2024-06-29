// Core lib imports.
use starknet::syscalls::deploy_syscall;
use starknet::contract_address::contract_address_const;

// Local imports.
use haiko_solver_core::types::MarketState;
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
/// 
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
