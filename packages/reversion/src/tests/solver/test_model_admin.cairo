// Core lib imports.
use starknet::contract_address_const;

// Local imports.
use haiko_solver_core::interfaces::ISolver::{ISolverDispatcher, ISolverDispatcherTrait};
use haiko_solver_reversion::{
    contracts::reversion_solver::ReversionSolver,
    contracts::mocks::mock_pragma_oracle::{
        IMockPragmaOracleDispatcher, IMockPragmaOracleDispatcherTrait
    },
    interfaces::IReversionSolver::{IReversionSolverDispatcher, IReversionSolverDispatcherTrait},
    types::{Trend, MarketParams},
    tests::{
        helpers::{
            actions::{deploy_reversion_solver, deploy_mock_pragma_oracle},
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
fn test_change_model_admin_works() {
    let (
        _base_token, _quote_token, _oracle, _vault_token_class, solver, _market_id, _vault_token_opt
    ) =
        before(
        true
    );

    // Set model admin.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let rev_solver = IReversionSolverDispatcher { contract_address: solver.contract_address };
    rev_solver.change_model_admin(alice());

    // Get model admin.
    let model_admin = rev_solver.model_admin();

    // Run checks.
    assert(model_admin == alice(), 'Trend setter');
}

////////////////////////////////
// TESTS - Events
////////////////////////////////

#[test]
fn test_change_model_admin_emits_event() {
    let (
        _base_token, _quote_token, _oracle, _vault_token_class, solver, _market_id, _vault_token_opt
    ) =
        before(
        true
    );

    // Spy on events.
    let mut spy = spy_events(SpyOn::One(solver.contract_address));

    // Set trend.
    let rev_solver = IReversionSolverDispatcher { contract_address: solver.contract_address };
    rev_solver.change_model_admin(alice());

    // Check events emitted.
    spy
        .assert_emitted(
            @array![
                (
                    solver.contract_address,
                    ReversionSolver::Event::ChangeModelAdmin(
                        ReversionSolver::ChangeModelAdmin { admin: alice() }
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
fn test_change_model_admin_fails_if_not_owner() {
    let (
        _base_token, _quote_token, _oracle, _vault_token_class, solver, _market_id, _vault_token_opt
    ) =
        before(
        true
    );

    // Change model admin.
    start_prank(CheatTarget::One(solver.contract_address), alice());
    let rev_solver = IReversionSolverDispatcher { contract_address: solver.contract_address };
    rev_solver.change_model_admin(alice());
}

#[test]
#[should_panic(expected: ('TrendSetterUnchanged',))]
fn test_change_model_admin_fails_if_model_admin_unchanged() {
    let (
        _base_token, _quote_token, _oracle, _vault_token_class, solver, _market_id, _vault_token_opt
    ) =
        before(
        true
    );

    // Change model admin.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let rev_solver = IReversionSolverDispatcher { contract_address: solver.contract_address };
    rev_solver.change_model_admin(alice());

    // Change again to same setter.
    rev_solver.change_model_admin(alice());
}
