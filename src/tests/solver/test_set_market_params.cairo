// Core lib imports.
use starknet::contract_address_const;

// Local imports.
use haiko_solver_replicating::{
    contracts::replicating::replicating_solver::ReplicatingSolver,
    contracts::mocks::mock_pragma_oracle::{
        IMockPragmaOracleDispatcher, IMockPragmaOracleDispatcherTrait
    },
    interfaces::{
        ISolver::{ISolverDispatcher, ISolverDispatcherTrait},
        IVaultToken::{IVaultTokenDispatcher, IVaultTokenDispatcherTrait},
        IReplicatingSolver::{IReplicatingSolverDispatcher, IReplicatingSolverDispatcherTrait},
    },
    types::{core::MarketInfo, replicating::MarketParams},
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
fn test_set_market_params() {
    let (
        _base_token, _quote_token, _oracle, _vault_token_class, solver, market_id, _vault_token_opt
    ) =
        before(
        true
    );

    // Set market params.
    let repl_solver = IReplicatingSolverDispatcher { contract_address: solver.contract_address };
    let params = MarketParams {
        min_spread: 987,
        range: 12345,
        max_delta: 676,
        max_skew: 9989,
        base_currency_id: 123456,
        quote_currency_id: 789012,
        min_sources: 10,
        max_age: 200,
    };
    repl_solver.set_market_params(market_id, params);

    // Get market params.
    let market_params = repl_solver.market_params(market_id);

    // Run checks.
    assert(market_params.min_spread == params.min_spread, 'Min spread');
    assert(market_params.range == params.range, 'Range');
    assert(market_params.max_delta == params.max_delta, 'Max delta');
    assert(market_params.max_skew == params.max_skew, 'Max skew');
    assert(market_params.base_currency_id == params.base_currency_id, 'Base currency ID');
    assert(market_params.quote_currency_id == params.quote_currency_id, 'Quote currency ID');
    assert(market_params.min_sources == params.min_sources, 'Min sources');
    assert(market_params.max_age == params.max_age, 'Max age');
}

////////////////////////////////
// TESTS - Events
////////////////////////////////

#[test]
fn test_set_market_params_emits_event() {
    let (
        _base_token, _quote_token, _oracle, _vault_token_class, solver, market_id, _vault_token_opt
    ) =
        before(
        true
    );

    // Spy on events.
    let mut spy = spy_events(SpyOn::One(solver.contract_address));

    // Set market params.
    let repl_solver = IReplicatingSolverDispatcher { contract_address: solver.contract_address };
    let params = MarketParams {
        min_spread: 987,
        range: 12345,
        max_delta: 676,
        max_skew: 9989,
        base_currency_id: 123456,
        quote_currency_id: 789012,
        min_sources: 10,
        max_age: 200,
    };
    repl_solver.set_market_params(market_id, params);

    // Check events emitted.
    spy
        .assert_emitted(
            @array![
                (
                    solver.contract_address,
                    ReplicatingSolver::Event::SetMarketParams(
                        ReplicatingSolver::SetMarketParams {
                            market_id,
                            min_spread: params.min_spread,
                            range: params.range,
                            max_delta: params.max_delta,
                            max_skew: params.max_skew,
                            base_currency_id: params.base_currency_id,
                            quote_currency_id: params.quote_currency_id,
                            min_sources: params.min_sources,
                            max_age: params.max_age
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
#[should_panic(expected: ('AmountsZero',))]
fn test_set_market_params_fails_if_not_market_owner() {
    let (
        _base_token, _quote_token, _oracle, _vault_token_class, solver, market_id, _vault_token_opt
    ) =
        before(
        true
    );

    // Deposit initial.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let base_amount = 0;
    let quote_amount = 0;
    solver.deposit_initial(market_id, base_amount, quote_amount);

    // Deposit.
    solver.deposit(market_id, 0, 0);
}

#[test]
#[should_panic(expected: ('ParamsUnchanged',))]
fn test_set_market_params_fails_if_params_unchanged() {
    let (
        _base_token, _quote_token, _oracle, _vault_token_class, solver, market_id, _vault_token_opt
    ) =
        before(
        true
    );

    // Set market params.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let repl_solver = IReplicatingSolverDispatcher { contract_address: solver.contract_address };
    let params = repl_solver.market_params(market_id);
    repl_solver.set_market_params(market_id, params);
}

#[test]
#[should_panic(expected: ('RangeZero',))]
fn test_set_market_params_fails_if_range_zero() {
    let (
        _base_token, _quote_token, _oracle, _vault_token_class, solver, market_id, _vault_token_opt
    ) =
        before(
        true
    );

    // Set market params.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let repl_solver = IReplicatingSolverDispatcher { contract_address: solver.contract_address };
    let mut params = repl_solver.market_params(market_id);
    params.range = 0;
    repl_solver.set_market_params(market_id, params);
}

#[test]
#[should_panic(expected: ('MinSourcesZero',))]
fn test_set_market_params_fails_if_min_sources_zero() {
    let (
        _base_token, _quote_token, _oracle, _vault_token_class, solver, market_id, _vault_token_opt
    ) =
        before(
        true
    );

    // Set market params.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let repl_solver = IReplicatingSolverDispatcher { contract_address: solver.contract_address };
    let mut params = repl_solver.market_params(market_id);
    params.min_sources = 0;
    repl_solver.set_market_params(market_id, params);
}

#[test]
#[should_panic(expected: ('MaxAgeZero',))]
fn test_set_market_params_fails_if_max_age_zero() {
    let (
        _base_token, _quote_token, _oracle, _vault_token_class, solver, market_id, _vault_token_opt
    ) =
        before(
        true
    );

    // Set market params.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let repl_solver = IReplicatingSolverDispatcher { contract_address: solver.contract_address };
    let mut params = repl_solver.market_params(market_id);
    params.max_age = 0;
    repl_solver.set_market_params(market_id, params);
}

#[test]
#[should_panic(expected: ('BaseIdZero',))]
fn test_set_market_params_fails_if_base_currency_id_zero() {
    let (
        _base_token, _quote_token, _oracle, _vault_token_class, solver, market_id, _vault_token_opt
    ) =
        before(
        true
    );

    // Set market params.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let repl_solver = IReplicatingSolverDispatcher { contract_address: solver.contract_address };
    let mut params = repl_solver.market_params(market_id);
    params.base_currency_id = 0;
    repl_solver.set_market_params(market_id, params);
}

#[test]
#[should_panic(expected: ('QuoteIdZero',))]
fn test_set_market_params_fails_if_quote_currency_id_zero() {
    let (
        _base_token, _quote_token, _oracle, _vault_token_class, solver, market_id, _vault_token_opt
    ) =
        before(
        true
    );

    // Set market params.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let repl_solver = IReplicatingSolverDispatcher { contract_address: solver.contract_address };
    let mut params = repl_solver.market_params(market_id);
    params.quote_currency_id = 0;
    repl_solver.set_market_params(market_id, params);
}
