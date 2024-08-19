// Core lib imports.
use starknet::contract_address_const;

// Local imports.
use haiko_solver_core::interfaces::ISolver::{ISolverDispatcher, ISolverDispatcherTrait};
use haiko_solver_replicating::{
    contracts::replicating_solver::ReplicatingSolver,
    contracts::mocks::mock_pragma_oracle::{
        IMockPragmaOracleDispatcher, IMockPragmaOracleDispatcherTrait
    },
    interfaces::IReplicatingSolver::{
        IReplicatingSolverDispatcher, IReplicatingSolverDispatcherTrait
    },
    types::MarketParams,
    tests::{
        helpers::{
            actions::{deploy_replicating_solver, deploy_mock_pragma_oracle},
            params::{default_market_params, new_market_params},
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
fn test_queue_and_set_market_params_no_delay() {
    let (
        _base_token, _quote_token, _oracle, _vault_token_class, solver, market_id, _vault_token_opt
    ) =
        before(
        true
    );

    // Set market params.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let repl_solver = IReplicatingSolverDispatcher { contract_address: solver.contract_address };
    let params = new_market_params();
    repl_solver.queue_market_params(market_id, params);
    repl_solver.set_market_params(market_id);

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

#[test]
fn test_queue_and_set_market_params_with_delay() {
    let (
        _base_token, _quote_token, _oracle, _vault_token_class, solver, market_id, _vault_token_opt
    ) =
        before(
        true
    );

    // Set delay.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let delay = 86400; // 24 hours
    let repl_solver = IReplicatingSolverDispatcher { contract_address: solver.contract_address };
    repl_solver.set_delay(delay);

    // Queue market params.
    start_warp(CheatTarget::One(solver.contract_address), 1000);
    let params = new_market_params();
    repl_solver.queue_market_params(market_id, params);

    // Set market params.
    start_warp(CheatTarget::One(solver.contract_address), 100000);
    repl_solver.set_market_params(market_id);

    // Get market params.
    let market_params = repl_solver.market_params(market_id);
    let queued_params = repl_solver.queued_market_params(market_id);

    // Run checks.
    assert(market_params.min_spread == params.min_spread, 'Min spread');
    assert(market_params.range == params.range, 'Range');
    assert(market_params.max_delta == params.max_delta, 'Max delta');
    assert(market_params.max_skew == params.max_skew, 'Max skew');
    assert(market_params.base_currency_id == params.base_currency_id, 'Base currency ID');
    assert(market_params.quote_currency_id == params.quote_currency_id, 'Quote currency ID');
    assert(market_params.min_sources == params.min_sources, 'Min sources');
    assert(market_params.max_age == params.max_age, 'Max age');
    assert(queued_params == Default::default(), 'Queued params');
}

#[test]
fn test_queue_and_set_market_params_with_delay_first_initialisation() {
    let (
        _base_token, _quote_token, _oracle, _vault_token_class, solver, market_id, _vault_token_opt
    ) =
        before(
        true
    );

    // Set delay.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let repl_solver = IReplicatingSolverDispatcher { contract_address: solver.contract_address };
    repl_solver.set_delay(86400);

    // Get market params.
    // Note market params are already set in the `before` fn.
    let market_params = repl_solver.market_params(market_id);
    let queued_params = repl_solver.queued_market_params(market_id);

    // Run checks.
    let params = default_market_params();
    assert(market_params.min_spread == params.min_spread, 'Min spread');
    assert(market_params.range == params.range, 'Range');
    assert(market_params.max_delta == params.max_delta, 'Max delta');
    assert(market_params.max_skew == params.max_skew, 'Max skew');
    assert(market_params.base_currency_id == params.base_currency_id, 'Base currency ID');
    assert(market_params.quote_currency_id == params.quote_currency_id, 'Quote currency ID');
    assert(market_params.min_sources == params.min_sources, 'Min sources');
    assert(market_params.max_age == params.max_age, 'Max age');
    assert(queued_params == Default::default(), 'Queued params');
}

#[test]
fn test_set_delay() {
    let (
        _base_token, _quote_token, _oracle, _vault_token_class, solver, _market_id, _vault_token_opt
    ) =
        before(
        true
    );

    // Set delay.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let delay = 86400; // 24 hours
    let repl_solver = IReplicatingSolverDispatcher { contract_address: solver.contract_address };
    repl_solver.set_delay(delay);

    // Run checks.
    let fetched_delay = repl_solver.delay();
    assert(fetched_delay == delay, 'Delay');
}

#[test]
fn test_unset_delay() {
    let (
        _base_token, _quote_token, _oracle, _vault_token_class, solver, _market_id, _vault_token_opt
    ) =
        before(
        true
    );

    // Set delay.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let delay = 86400; // 24 hours
    let repl_solver = IReplicatingSolverDispatcher { contract_address: solver.contract_address };
    repl_solver.set_delay(delay);

    // Unset delay.
    let delay_null = 0;
    repl_solver.set_delay(delay_null);

    // Run checks.
    let fetched_delay = repl_solver.delay();
    assert(fetched_delay == delay_null, 'Delay');
}

#[test]
fn test_update_queued_market_params() {
    let (
        _base_token, _quote_token, _oracle, _vault_token_class, solver, market_id, _vault_token_opt
    ) =
        before(
        true
    );

    // Queue market params.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let repl_solver = IReplicatingSolverDispatcher { contract_address: solver.contract_address };
    let params = new_market_params();
    repl_solver.queue_market_params(market_id, params);

    // Update queued market params.
    let updated_params = MarketParams {
        min_spread: 123,
        range: 456,
        max_delta: 789,
        max_skew: 987,
        base_currency_id: 654321,
        quote_currency_id: 210987,
        min_sources: 20,
        max_age: 400,
    };
    repl_solver.queue_market_params(market_id, updated_params);

    // Run checks.
    let queued_params = repl_solver.queued_market_params(market_id);
    assert(queued_params.min_spread == updated_params.min_spread, 'Min spread');
    assert(queued_params.range == updated_params.range, 'Range');
    assert(queued_params.max_delta == updated_params.max_delta, 'Max delta');
    assert(queued_params.max_skew == updated_params.max_skew, 'Max skew');
    assert(queued_params.base_currency_id == updated_params.base_currency_id, 'Base currency ID');
    assert(
        queued_params.quote_currency_id == updated_params.quote_currency_id, 'Quote currency ID'
    );
    assert(queued_params.min_sources == updated_params.min_sources, 'Min sources');
    assert(queued_params.max_age == updated_params.max_age, 'Max age');
}

#[test]
fn test_cancel_queued_market_params() {
    let (
        _base_token, _quote_token, _oracle, _vault_token_class, solver, market_id, _vault_token_opt
    ) =
        before(
        true
    );

    // Queue market params.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let repl_solver = IReplicatingSolverDispatcher { contract_address: solver.contract_address };
    let params = new_market_params();
    repl_solver.queue_market_params(market_id, params);

    // Cancel queued market params.
    repl_solver.queue_market_params(market_id, Default::default());

    // Run checks.
    let queued_params = repl_solver.queued_market_params(market_id);
    assert(queued_params.min_spread == 0, 'Min spread');
    assert(queued_params.range == 0, 'Range');
    assert(queued_params.max_delta == 0, 'Max delta');
    assert(queued_params.max_skew == 0, 'Max skew');
    assert(queued_params.base_currency_id == 0, 'Base currency ID');
    assert(queued_params.quote_currency_id == 0, 'Quote currency ID');
    assert(queued_params.min_sources == 0, 'Min sources');
    assert(queued_params.max_age == 0, 'Max age');
}

////////////////////////////////
// TESTS - Events
////////////////////////////////

#[test]
fn test_queue_market_params_emits_event() {
    let (
        _base_token, _quote_token, _oracle, _vault_token_class, solver, market_id, _vault_token_opt
    ) =
        before(
        true
    );

    // Spy on events.
    let mut spy = spy_events(SpyOn::One(solver.contract_address));

    // Queue market params.
    let repl_solver = IReplicatingSolverDispatcher { contract_address: solver.contract_address };
    let params = new_market_params();
    repl_solver.queue_market_params(market_id, params);

    // Check events emitted.
    spy
        .assert_emitted(
            @array![
                (
                    solver.contract_address,
                    ReplicatingSolver::Event::QueueMarketParams(
                        ReplicatingSolver::QueueMarketParams {
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

#[test]
fn test_set_delay_emits_event() {
    let (
        _base_token, _quote_token, _oracle, _vault_token_class, solver, _market_id, _vault_token_opt
    ) =
        before(
        true
    );

    // Spy on events.
    let mut spy = spy_events(SpyOn::One(solver.contract_address));

    // Set delay.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let repl_solver = IReplicatingSolverDispatcher { contract_address: solver.contract_address };
    let delay = 86400; // 24 hours
    repl_solver.set_delay(delay);

    // Check events emitted.
    spy
        .assert_emitted(
            @array![
                (
                    solver.contract_address,
                    ReplicatingSolver::Event::SetDelay(ReplicatingSolver::SetDelay { delay })
                )
            ]
        );
}

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
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let repl_solver = IReplicatingSolverDispatcher { contract_address: solver.contract_address };
    let params = new_market_params();
    repl_solver.queue_market_params(market_id, params);
    repl_solver.set_market_params(market_id);

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
#[should_panic(expected: ('OnlyMarketOwner',))]
fn test_queue_market_params_fails_if_not_market_owner() {
    let (
        _base_token, _quote_token, _oracle, _vault_token_class, solver, market_id, _vault_token_opt
    ) =
        before(
        true
    );

    // Queue market params.
    start_prank(CheatTarget::One(solver.contract_address), alice());
    let repl_solver = IReplicatingSolverDispatcher { contract_address: solver.contract_address };
    let params = repl_solver.market_params(market_id);
    repl_solver.queue_market_params(market_id, params);
}

#[test]
#[should_panic(expected: ('ParamsUnchanged',))]
fn test_queue_market_params_fails_if_params_unchanged() {
    let (
        _base_token, _quote_token, _oracle, _vault_token_class, solver, market_id, _vault_token_opt
    ) =
        before(
        true
    );

    // Queue market params.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let repl_solver = IReplicatingSolverDispatcher { contract_address: solver.contract_address };
    let params = repl_solver.market_params(market_id);
    repl_solver.queue_market_params(market_id, params);
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

    // Queue market params.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let repl_solver = IReplicatingSolverDispatcher { contract_address: solver.contract_address };
    let mut params = repl_solver.market_params(market_id);
    params.range = 0;
    repl_solver.queue_market_params(market_id, params);

    // Set market params.
    repl_solver.set_market_params(market_id);
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

    // Queue market params.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let repl_solver = IReplicatingSolverDispatcher { contract_address: solver.contract_address };
    let mut params = repl_solver.market_params(market_id);
    params.min_sources = 0;
    repl_solver.queue_market_params(market_id, params);

    // Set market params.
    repl_solver.set_market_params(market_id);
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

    // Queue market params.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let repl_solver = IReplicatingSolverDispatcher { contract_address: solver.contract_address };
    let mut params = repl_solver.market_params(market_id);
    params.max_age = 0;
    repl_solver.queue_market_params(market_id, params);

    // Set market params.
    repl_solver.set_market_params(market_id);
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

    // Queue market params.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let repl_solver = IReplicatingSolverDispatcher { contract_address: solver.contract_address };
    let mut params = repl_solver.market_params(market_id);
    params.base_currency_id = 0;
    repl_solver.queue_market_params(market_id, params);

    // Set market params.
    repl_solver.set_market_params(market_id);
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

    // Queue market params.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let repl_solver = IReplicatingSolverDispatcher { contract_address: solver.contract_address };
    let mut params = repl_solver.market_params(market_id);
    params.quote_currency_id = 0;
    repl_solver.queue_market_params(market_id, params);

    // Set market params.
    repl_solver.set_market_params(market_id);
}

#[test]
#[should_panic(expected: ('OnlyMarketOwner',))]
fn test_set_market_params_fails_if_not_owner() {
    let (
        _base_token, _quote_token, _oracle, _vault_token_class, solver, market_id, _vault_token_opt
    ) =
        before(
        true
    );

    // Queue market params.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let repl_solver = IReplicatingSolverDispatcher { contract_address: solver.contract_address };
    let mut params = repl_solver.market_params(market_id);
    params.min_spread = 987;
    repl_solver.queue_market_params(market_id, params);

    // Set market params.
    start_prank(CheatTarget::One(solver.contract_address), alice());
    repl_solver.set_market_params(market_id);
}

#[test]
#[should_panic(expected: ('DelayNotPassed',))]
fn test_set_market_params_fails_before_delay_complete() {
    let (
        _base_token, _quote_token, _oracle, _vault_token_class, solver, market_id, _vault_token_opt
    ) =
        before(
        true
    );

    // Set delay.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let delay = 86400; // 24 hours
    let repl_solver = IReplicatingSolverDispatcher { contract_address: solver.contract_address };
    repl_solver.set_delay(delay);

    // Queue new market params.
    start_warp(CheatTarget::One(solver.contract_address), 1000);
    let mut params = default_market_params();
    params.min_spread = 987;
    repl_solver.queue_market_params(market_id, params);

    // Set new market params.
    start_warp(CheatTarget::One(solver.contract_address), 2000);
    repl_solver.set_market_params(market_id);
}

#[test]
#[should_panic(expected: ('NotQueued',))]
fn test_set_market_params_fails_none_queued() {
    let (
        _base_token, _quote_token, _oracle, _vault_token_class, solver, market_id, _vault_token_opt
    ) =
        before(
        true
    );

    // Set delay.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let delay = 86400; // 24 hours
    let repl_solver = IReplicatingSolverDispatcher { contract_address: solver.contract_address };
    repl_solver.set_delay(delay);

    // Set market params without queuing.
    start_warp(CheatTarget::One(solver.contract_address), 100000);
    repl_solver.set_market_params(market_id);
}

#[test]
#[should_panic(expected: ('NotQueued',))]
fn test_set_market_params_fails_none_queued_null_params() {
    let (
        _base_token, _quote_token, _oracle, _vault_token_class, solver, market_id, _vault_token_opt
    ) =
        before(
        true
    );

    // Set delay.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let delay = 86400; // 24 hours
    let repl_solver = IReplicatingSolverDispatcher { contract_address: solver.contract_address };
    repl_solver.set_delay(delay);

    // Queue market params.
    start_warp(CheatTarget::One(solver.contract_address), 1000);
    let mut params = default_market_params();
    params.min_spread = 987;
    repl_solver.queue_market_params(market_id, params);

    // Update queued market params to zero.
    repl_solver.queue_market_params(market_id, Default::default());

    // Set market params.
    start_warp(CheatTarget::One(solver.contract_address), 100000);
    repl_solver.set_market_params(market_id);
}

#[test]
#[should_panic(expected: ('ParamsUnchanged',))]
fn test_set_market_params_fails_if_unchanged() {
    let (
        _base_token, _quote_token, _oracle, _vault_token_class, solver, market_id, _vault_token_opt
    ) =
        before(
        true
    );

    // Set delay.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let delay = 86400; // 24 hours
    let repl_solver = IReplicatingSolverDispatcher { contract_address: solver.contract_address };
    repl_solver.set_delay(delay);

    // Queue market params.
    start_warp(CheatTarget::One(solver.contract_address), 1000);
    let mut params = repl_solver.market_params(market_id);
    repl_solver.queue_market_params(market_id, params);

    // Set market params.
    start_warp(CheatTarget::One(solver.contract_address), 100000);
    repl_solver.set_market_params(market_id);

    // Queue market params again.
    repl_solver.queue_market_params(market_id, params);

    // Set market params again.
    start_warp(CheatTarget::One(solver.contract_address), 200000);
    repl_solver.set_market_params(market_id);
}
