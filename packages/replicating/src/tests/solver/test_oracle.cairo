// Core lib imports.
use starknet::contract_address_const;

// Local imports.
use haiko_solver_core::{
    contracts::solver::SolverComponent,
    interfaces::{IVaultToken::{IVaultTokenDispatcher, IVaultTokenDispatcherTrait},},
};
use haiko_solver_replicating::{
    contracts::replicating_solver::ReplicatingSolver,
    contracts::mocks::mock_pragma_oracle::{
        IMockPragmaOracleDispatcher, IMockPragmaOracleDispatcherTrait
    },
    interfaces::{
        IReplicatingSolver::{IReplicatingSolverDispatcher, IReplicatingSolverDispatcherTrait},
    },
    tests::{
        helpers::{
            actions::{deploy_replicating_solver, deploy_mock_pragma_oracle},
            params::default_market_params,
            utils::{before, before_custom_decimals, before_skip_approve, snapshot},
        },
    },
};

// Haiko imports.
use haiko_lib::helpers::params::{owner, alice};
use haiko_lib::helpers::utils::{to_e18, approx_eq, approx_eq_pct};
use haiko_lib::helpers::actions::token::{fund, approve};

// External imports.
use snforge_std::{
    start_prank, stop_prank, start_warp, declare, spy_events, SpyOn, EventSpy, EventAssertions,
    CheatTarget
};
use openzeppelin::token::erc20::interface::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};

////////////////////////////////
// TESTS - Success cases
////////////////////////////////

#[test]
fn test_change_oracle() {
    let (
        _base_token, _quote_token, _oracle, _vault_token_class, solver, _market_id, _vault_token_opt
    ) =
        before(
        true
    );

    let repl_solver = IReplicatingSolverDispatcher { contract_address: solver.contract_address };

    // Change oracle.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let new_oracle = contract_address_const::<0x123>();
    repl_solver.change_oracle(new_oracle);

    // Get oracle and run check.
    let oracle = repl_solver.oracle();
    assert(new_oracle == oracle, 'Oracle');
}

////////////////////////////////
// TESTS - Events
////////////////////////////////

#[test]
fn test_change_oracle_emits_event() {
    let (
        _base_token, _quote_token, _oracle, _vault_token_class, solver, _market_id, _vault_token_opt
    ) =
        before(
        true
    );

    let repl_solver = IReplicatingSolverDispatcher { contract_address: solver.contract_address };

    // Spy on events.
    let mut spy = spy_events(SpyOn::One(solver.contract_address));

    // Change oracle.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let new_oracle = contract_address_const::<0x123>();
    repl_solver.change_oracle(new_oracle);

    // Check events emitted.
    spy
        .assert_emitted(
            @array![
                (
                    solver.contract_address,
                    ReplicatingSolver::Event::ChangeOracle(
                        ReplicatingSolver::ChangeOracle { oracle: new_oracle }
                    )
                )
            ]
        );
}

////////////////////////////////
// TESTS - Failure cases
////////////////////////////////

#[test]
#[should_panic(expected: ('OnlyOwner',))]
fn test_change_oracle_not_owner() {
    let (
        _base_token, _quote_token, _oracle, _vault_token_class, solver, _market_id, _vault_token_opt
    ) =
        before(
        true
    );

    let repl_solver = IReplicatingSolverDispatcher { contract_address: solver.contract_address };

    // Change oracle.
    start_prank(CheatTarget::One(solver.contract_address), alice());
    let new_oracle = contract_address_const::<0x123>();
    repl_solver.change_oracle(new_oracle);
}

#[test]
#[should_panic(expected: ('OracleUnchanged',))]
fn test_change_oracle_unchanged() {
    let (
        _base_token, _quote_token, _oracle, _vault_token_class, solver, _market_id, _vault_token_opt
    ) =
        before(
        true
    );

    let repl_solver = IReplicatingSolverDispatcher { contract_address: solver.contract_address };

    // Change oracle.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let oracle = repl_solver.oracle();
    repl_solver.change_oracle(oracle);
}
