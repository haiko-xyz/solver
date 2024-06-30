// Core lib imports.
use starknet::contract_address_const;

// Local imports.
use haiko_solver_core::{
    interfaces::{
        ISolver::{ISolverDispatcher, ISolverDispatcherTrait},
        IVaultToken::{IVaultTokenDispatcher, IVaultTokenDispatcherTrait},
    },
    types::MarketInfo,
};
use haiko_solver_replicating::{
    interfaces::{
        IReplicatingSolver::{IReplicatingSolverDispatcher, IReplicatingSolverDispatcherTrait},
    },
    types::MarketParams,
    tests::{
        helpers::{actions::{deploy_replicating_solver, deploy_mock_pragma_oracle}, utils::before,},
    },
};

// Haiko imports.
use haiko_lib::helpers::params::owner;

// External imports.
use snforge_std::{declare, start_prank, CheatTarget};
use openzeppelin::token::erc20::interface::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};

////////////////////////////////
// TESTS
////////////////////////////////

#[test]
fn test_deploy_replicating_solver_initialises_immutables() {
    let (
        _base_token, _quote_token, oracle, vault_token_class, solver, _market_id, _vault_token_opt
    ) =
        before(
        true
    );

    let repl_solver = IReplicatingSolverDispatcher { contract_address: solver.contract_address };

    assert(solver.owner() == owner(), 'Owner');
    assert(solver.queued_owner() == contract_address_const::<0x0>(), 'Queued owner');
    assert(solver.vault_token_class() == vault_token_class, 'Vault token class');
    assert(repl_solver.oracle() == oracle.contract_address, 'Oracle');
}
