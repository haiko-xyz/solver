// Core lib imports.
use starknet::contract_address_const;

// Local imports.
use haiko_solver::{
    interfaces::{
        ISolver::{ISolverDispatcher, ISolverDispatcherTrait},
        IVaultToken::{IVaultTokenDispatcher, IVaultTokenDispatcherTrait},
        IReplicatingSolver::{IReplicatingSolverDispatcher, IReplicatingSolverDispatcherTrait},
    },
    types::{core::MarketInfo, replicating::MarketParams},
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
fn test_deploy_solver_and_vault_token_initialises_immutables() {
    let (
        _base_token, _quote_token, oracle, vault_token_class, solver, _market_id, _vault_token_opt
    ) =
        before(
        true
    );

    let repl_solver = IReplicatingSolverDispatcher { contract_address: solver.contract_address };

    assert(solver.owner() == owner(), 'Solver: owner');
    assert(solver.queued_owner() == contract_address_const::<0x0>(), 'Solver: queued owner');
    assert(solver.vault_token_class() == vault_token_class, 'Solver: vault token class');
    assert(repl_solver.oracle() == oracle.contract_address, 'Solver: oracle');
}

#[test]
fn test_deploy_vault_token_initialises_immutables() {
    let (
        _base_token, _quote_token, _oracle, _vault_token_class, solver, _market_id, vault_token_opt
    ) =
        before(
        true
    );

    let vault_token = ERC20ABIDispatcher { contract_address: vault_token_opt.unwrap() };
    let vault_token_alt = IVaultTokenDispatcher { contract_address: vault_token_opt.unwrap() };

    assert(vault_token.name() == "Haiko Replicating ETH-USDC", 'Vault token: name');
    assert(vault_token.symbol() == "REPL-ETH-USDC", 'Vault token: name');
    assert(vault_token.decimals() == 18, 'Vault token: decimal');
    assert(vault_token_alt.owner() == solver.contract_address, 'Vault token: owner');
}
