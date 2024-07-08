// Core lib imports.
use starknet::contract_address_const;

// Local imports.
use haiko_solver_core::{
    contracts::solver::SolverComponent,
    interfaces::{
        ISolver::{ISolverDispatcher, ISolverDispatcherTrait},
        IVaultToken::{IVaultTokenDispatcher, IVaultTokenDispatcherTrait},
    },
    tests::helpers::{actions::deploy_mock_solver, utils::before,},
};

// Haiko imports.
use haiko_lib::helpers::params::{owner, alice};
use haiko_lib::helpers::utils::{to_e18, approx_eq};
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
fn test_pause_allows_withdraws() {
    let (_base_token, _quote_token, _vault_token_class, solver, market_id, _vault_token_opt) =
        before(
        true
    );

    // Deposit initial.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    solver.deposit_initial(market_id, to_e18(100), to_e18(500));

    // Deposit.
    start_prank(CheatTarget::One(solver.contract_address), alice());
    let (_, _, shares) = solver.deposit(market_id, to_e18(100), to_e18(500));

    // Pause.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    solver.pause(market_id);

    // Withdraw.
    start_prank(CheatTarget::One(solver.contract_address), alice());
    solver.withdraw_public(market_id, shares);
}

#[test]
fn test_unpause_after_pause_reenables_deposits() {
    let (_base_token, _quote_token, _vault_token_class, solver, market_id, _vault_token_opt) =
        before(
        true
    );

    // Pause.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    solver.pause(market_id);

    // Unpause.
    solver.unpause(market_id);

    // Deposit initial.
    solver.deposit_initial(market_id, to_e18(100), to_e18(500));
}

////////////////////////////////
// TESTS - Events
////////////////////////////////

#[test]
fn test_pause_emits_event() {
    let (_base_token, _quote_token, _vault_token_class, solver, market_id, _vault_token_opt) =
        before(
        true
    );

    // Spy on events.
    let mut spy = spy_events(SpyOn::One(solver.contract_address));

    // Pause.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    solver.pause(market_id);

    // Check events emitted.
    spy
        .assert_emitted(
            @array![
                (
                    solver.contract_address,
                    SolverComponent::Event::Pause(SolverComponent::Pause { market_id })
                )
            ]
        );
}

#[test]
fn test_unpause_emits_event() {
    let (_base_token, _quote_token, _vault_token_class, solver, market_id, _vault_token_opt) =
        before(
        true
    );

    // Pause.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    solver.pause(market_id);

    // Spy on events.
    let mut spy = spy_events(SpyOn::One(solver.contract_address));

    // Pause.
    solver.unpause(market_id);

    // Check events emitted.
    spy
        .assert_emitted(
            @array![
                (
                    solver.contract_address,
                    SolverComponent::Event::Unpause(SolverComponent::Unpause { market_id })
                )
            ]
        );
}

////////////////////////////////
// TESTS - Failure cases
////////////////////////////////

#[test]
#[should_panic(expected: ('Paused',))]
fn test_pause_prevents_non_owner_deposits() {
    let (_base_token, _quote_token, _vault_token_class, solver, market_id, _vault_token_opt) =
        before(
        true
    );

    // Deposit initial.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    solver.deposit_initial(market_id, to_e18(100), to_e18(500));

    // Pause.
    solver.pause(market_id);

    // Deposit.
    start_prank(CheatTarget::One(solver.contract_address), alice());
    solver.deposit(market_id, to_e18(100), to_e18(500));
}

#[test]
#[should_panic(expected: ('Paused',))]
fn test_pause_prevents_owner_deposits() {
    let (_base_token, _quote_token, _vault_token_class, solver, market_id, _vault_token_opt) =
        before(
        true
    );

    // Pause.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    solver.pause(market_id);

    // Deposit.
    solver.deposit(market_id, to_e18(100), to_e18(500));
}

#[test]
#[should_panic(expected: ('AlreadyPaused',))]
fn test_pause_fails_if_already_paused() {
    let (_base_token, _quote_token, _vault_token_class, solver, market_id, _vault_token_opt) =
        before(
        true
    );

    // Pause.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    solver.pause(market_id);

    // Pause again.
    solver.pause(market_id);
}

#[test]
#[should_panic(expected: ('AlreadyUnpaused',))]
fn test_pause_fails_if_already_unpaused() {
    let (_base_token, _quote_token, _vault_token_class, solver, market_id, _vault_token_opt) =
        before(
        true
    );

    // Unpause.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    solver.unpause(market_id);
}
