// Core lib imports.
use starknet::contract_address_const;

// Local imports.
use haiko_solver::{
    contracts::core::solver::SolverComponent,
    contracts::mocks::mock_pragma_oracle::{
        IMockPragmaOracleDispatcher, IMockPragmaOracleDispatcherTrait
    },
    interfaces::{
        ISolver::{ISolverDispatcher, ISolverDispatcherTrait},
        IVaultToken::{IVaultTokenDispatcher, IVaultTokenDispatcherTrait},
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
fn test_transfer_ownership_works() {
    let (
        _base_token, _quote_token, _oracle, _vault_token_class, solver, _market_id, _vault_token_opt
    ) =
        before(
        true
    );

    // Transfer owner.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    solver.transfer_owner(alice());

    // Accept owner.
    start_prank(CheatTarget::One(solver.contract_address), alice());
    solver.accept_owner();

    // Check owner.
    assert(solver.owner() == alice(), 'Owner');
}

#[test]
fn test_transfer_then_update_owner_before_accepting_works() {
    let (
        _base_token, _quote_token, _oracle, _vault_token_class, solver, _market_id, _vault_token_opt
    ) =
        before(
        true
    );

    // Transfer owner.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    solver.transfer_owner(alice());

    // Transfer owner.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    solver.transfer_owner(bob());

    // Accept owner.
    start_prank(CheatTarget::One(solver.contract_address), bob());
    solver.accept_owner();

    // Check owner.
    assert(solver.owner() == bob(), 'Owner');
}

////////////////////////////////
// TESTS - Events
////////////////////////////////

#[test]
fn test_transfer_ownership_emits_event() {
    let (
        _base_token, _quote_token, _oracle, _vault_token_class, solver, _market_id, _vault_token_opt
    ) =
        before(
        true
    );

    // Spy on events.
    let mut spy = spy_events(SpyOn::One(solver.contract_address));

    // Transfer owner.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    solver.transfer_owner(alice());

    // Accept owner.
    start_prank(CheatTarget::One(solver.contract_address), alice());
    solver.accept_owner();

    // Check events emitted.
    spy
        .assert_emitted(
            @array![
                (
                    solver.contract_address,
                    SolverComponent::Event::ChangeOwner(
                        SolverComponent::ChangeOwner { old: owner(), new: alice() }
                    )
                )
            ]
        );
}

////////////////////////////////
// TESTS - Failure cases
////////////////////////////////

#[test]
#[should_panic(expected: ('SameOwner',))]
fn test_transfer_ownership_fails_if_unchanged() {
    let (
        _base_token, _quote_token, _oracle, _vault_token_class, solver, _market_id, _vault_token_opt
    ) =
        before(
        true
    );

    // Transfer owner.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    solver.transfer_owner(solver.owner());
}

#[test]
#[should_panic(expected: ('OnlyOwner',))]
fn test_transfer_ownership_fails_not_owner() {
    let (
        _base_token, _quote_token, _oracle, _vault_token_class, solver, _market_id, _vault_token_opt
    ) =
        before(
        true
    );

    // Transfer owner.
    start_prank(CheatTarget::One(solver.contract_address), alice());
    solver.transfer_owner(alice());
}

#[test]
#[should_panic(expected: ('OnlyNewOwner',))]
fn test_transfer_ownership_fails_if_accepting_from_non_owner_address() {
    let (
        _base_token, _quote_token, _oracle, _vault_token_class, solver, _market_id, _vault_token_opt
    ) =
        before(
        true
    );

    // Transfer owner.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    solver.transfer_owner(alice());

    // Accept owner.
    start_prank(CheatTarget::One(solver.contract_address), bob());
    solver.accept_owner();
}
