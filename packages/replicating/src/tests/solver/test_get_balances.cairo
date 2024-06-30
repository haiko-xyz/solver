// Core lib imports.
use starknet::contract_address_const;

// Local imports.
use haiko_solver_core::{
    contracts::solver::SolverComponent,
    interfaces::{
        ISolver::{ISolverDispatcher, ISolverDispatcherTrait},
        IVaultToken::{IVaultTokenDispatcher, IVaultTokenDispatcherTrait},
    },
    types::MarketInfo,
};
use haiko_solver_replicating::{
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
            params::default_market_params,
            utils::{before, before_custom_decimals, before_skip_approve, snapshot},
        },
    },
};

// Haiko imports.
use haiko_lib::helpers::params::{owner, alice, bob};
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
fn test_get_balances() {
    let (
        _base_token, _quote_token, _oracle, _vault_token_class, solver, market_id, _vault_token_opt
    ) =
        before(
        true
    );

    // Deposit initial.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let base_owner = to_e18(100);
    let quote_owner = to_e18(500);
    solver.deposit_initial(market_id, base_owner, quote_owner);

    // Get balances.
    let (base, quote) = solver.get_balances(market_id);
    assert(base == base_owner, 'Base amount');
    assert(quote == quote_owner, 'Quote amount');
}

#[test]
fn test_get_balances_array() {
    let (
        _base_token, _quote_token, _oracle, _vault_token_class, solver, market_id, _vault_token_opt
    ) =
        before(
        true
    );

    // Deposit initial.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let base_owner = to_e18(100);
    let quote_owner = to_e18(500);
    solver.deposit_initial(market_id, base_owner, quote_owner);

    // Get balances.
    let balances = solver.get_balances_array(array![market_id].span());
    let (base, quote) = *balances.at(0);
    assert(base == base_owner, 'Base amount');
    assert(quote == quote_owner, 'Quote amount');
}

#[test]
fn test_get_user_balances_array() {
    let (
        _base_token, _quote_token, _oracle, _vault_token_class, solver, market_id, _vault_token_opt
    ) =
        before(
        true
    );

    // Deposit initial.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let base_owner = to_e18(100);
    let quote_owner = to_e18(500);
    let (_, _, shares_owner) = solver.deposit_initial(market_id, base_owner, quote_owner);

    // Deposit.
    start_prank(CheatTarget::One(solver.contract_address), alice());
    let base_alice = to_e18(50);
    let quote_alice = to_e18(250);
    let (_, _, shares_alice) = solver.deposit(market_id, base_alice, quote_alice);

    // Get balances.
    let balances = solver
        .get_user_balances_array(
            array![owner(), alice()].span(), array![market_id, market_id].span(),
        );
    let (base_owner_, quote_owner_, shares_owner_, shares_total_owner) = *balances.at(0);
    let (base_alice_, quote_alice_, shares_alice_, shares_total_alice) = *balances.at(1);

    // Run checks.
    assert(base_owner == base_owner_, 'Base owner');
    assert(quote_owner == quote_owner_, 'Quote owner');
    assert(shares_owner == shares_owner_, 'Shares owner');
    assert(shares_total_owner == shares_owner + shares_alice, 'Shares total owner');
    assert(approx_eq(base_alice, base_alice_, 10), 'Base alice');
    assert(approx_eq(quote_alice, quote_alice_, 10), 'Quote alice');
    assert(shares_alice == shares_alice_, 'Shares alice');
    assert(shares_total_alice == shares_owner + shares_alice, 'Shares total alice');
}

////////////////////////////////
// TESTS - Fail cases
////////////////////////////////

#[test]
#[should_panic(expected: ('LengthMismatch',))]
fn test_get_user_balances_array_length_mismatch() {
    let (
        _base_token, _quote_token, _oracle, _vault_token_class, solver, market_id, _vault_token_opt
    ) =
        before(
        true
    );

    solver
        .get_user_balances_array(
            array![owner(), alice(), bob()].span(), array![market_id, market_id].span(),
        );
}
