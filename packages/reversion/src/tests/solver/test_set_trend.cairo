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
fn test_new_solver_market_has_ranging_trend_by_default() {
    let (
        _base_token, _quote_token, _oracle, _vault_token_class, solver, market_id, _vault_token_opt
    ) =
        before(
        true
    );

    // Get trend.
    let rev_solver = IReversionSolverDispatcher { contract_address: solver.contract_address };
    let trend = rev_solver.trend(market_id);

    // Run checks.
    assert(trend == Trend::Range, 'Default trend');
}

#[test]
fn test_set_trend_for_solver_market_updates_state() {
    let (
        _base_token, _quote_token, _oracle, _vault_token_class, solver, market_id, _vault_token_opt
    ) =
        before(
        true
    );

    // Set trend.
    let rev_solver = IReversionSolverDispatcher { contract_address: solver.contract_address };
    rev_solver.set_trend(market_id, Trend::Up);

    // Get trend and run check.
    let trend = rev_solver.trend(market_id);
    assert(trend == Trend::Up, 'Trend');
}

#[test]
fn test_set_trend_is_callable_by_market_owner() {
    let (
        _base_token, _quote_token, _oracle, _vault_token_class, solver, market_id, _vault_token_opt
    ) =
        before(
        true
    );

    // Set trend.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let rev_solver = IReversionSolverDispatcher { contract_address: solver.contract_address };
    rev_solver.set_trend(market_id, Trend::Up);
}

#[test]
fn test_set_trend_is_callable_by_trend_setter() {
    let (
        _base_token, _quote_token, _oracle, _vault_token_class, solver, market_id, _vault_token_opt
    ) =
        before(
        true
    );

    // Change trend setter.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let rev_solver = IReversionSolverDispatcher { contract_address: solver.contract_address };
    rev_solver.change_trend_setter(alice());
    
    // Set trend.
    start_prank(CheatTarget::One(solver.contract_address), alice());
    rev_solver.set_trend(market_id, Trend::Up);
    let trend = rev_solver.trend(market_id);
    assert(trend == Trend::Up, 'Trend');
}

////////////////////////////////
// TESTS - Events
////////////////////////////////

#[test]
fn test_set_trend_emits_event() {
    let (
        _base_token, _quote_token, _oracle, _vault_token_class, solver, market_id, _vault_token_opt
    ) =
        before(
        true
    );

    // Spy on events.
    let mut spy = spy_events(SpyOn::One(solver.contract_address));

    // Set trend.
    let rev_solver = IReversionSolverDispatcher { contract_address: solver.contract_address };
    rev_solver.set_trend(market_id, Trend::Up);

    // Check events emitted.
    spy
        .assert_emitted(
            @array![
                (
                    solver.contract_address,
                    ReversionSolver::Event::SetTrend(
                        ReversionSolver::SetTrend {
                            market_id,
                            trend: Trend::Up
                        }
                    )
                )
            ]
        );
}

////////////////////////////////
// TESTS - Failure cases
////////////////////////////////

#[test]
#[should_panic(expected: ('MarketNull',))]
fn test_set_trend_fails_if_market_does_not_exist() {
    let (
        _base_token, _quote_token, _oracle, _vault_token_class, solver, _market_id, _vault_token_opt
    ) =
        before(
        true
    );

    // Set trend.
    let rev_solver = IReversionSolverDispatcher { contract_address: solver.contract_address };
    rev_solver.set_trend(1, Trend::Up);
}

#[test]
#[should_panic(expected: ('TrendUnchanged',))]
fn test_set_trend_fails_if_trend_unchanged() {
    let (
        _base_token, _quote_token, _oracle, _vault_token_class, solver, market_id, _vault_token_opt
    ) =
        before(
        true
    );

    // Set trend.
    let rev_solver = IReversionSolverDispatcher { contract_address: solver.contract_address };
    rev_solver.set_trend(market_id, Trend::Range);
}

#[test]
#[should_panic(expected: ('NotApproved',))]
fn test_set_trend_fails_if_caller_is_not_market_owner() {
    let (
        _base_token, _quote_token, _oracle, _vault_token_class, solver, market_id, _vault_token_opt
    ) =
        before(
        true
    );

    // Set trend.
    start_prank(CheatTarget::One(solver.contract_address), alice());
    let rev_solver = IReversionSolverDispatcher { contract_address: solver.contract_address };
    rev_solver.set_trend(market_id, Trend::Range);
}