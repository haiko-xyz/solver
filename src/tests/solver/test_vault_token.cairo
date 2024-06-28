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
fn test_change_vault_token_class_works() {
    let (
        _base_token, _quote_token, _oracle, _vault_token_class, solver, _market_id, _vault_token_opt
    ) =
        before(
        true
    );

    // Change vault token class.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    solver.change_vault_token_class(0x12345678.try_into().unwrap());
}

////////////////////////////////
// TESTS - Events
////////////////////////////////

#[test]
fn test_change_vault_token_class_emits_event() {
    let (
        _base_token, _quote_token, _oracle, _vault_token_class, solver, _market_id, _vault_token_opt
    ) =
        before(
        true
    );

    // Spy on events.
    let mut spy = spy_events(SpyOn::One(solver.contract_address));

    // Change vault token class.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let class_hash = 0x12345678.try_into().unwrap();
    solver.change_vault_token_class(class_hash);

    // Check events emitted.
    spy
        .assert_emitted(
            @array![
                (
                    solver.contract_address,
                    SolverComponent::Event::ChangeVaultTokenClass(
                        SolverComponent::ChangeVaultTokenClass { class_hash }
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
fn test_change_vault_token_class_fails_if_not_owner() {
    let (
        _base_token, _quote_token, _oracle, _vault_token_class, solver, _market_id, _vault_token_opt
    ) =
        before(
        true
    );

    // Change vault token class.
    start_prank(CheatTarget::One(solver.contract_address), alice());
    let class_hash = 0x12345678.try_into().unwrap();
    solver.change_vault_token_class(class_hash);
}

#[test]
#[should_panic(expected: ('ClassHashUnchanged',))]
fn test_change_vault_token_class_fails_if_unchanged() {
    let (
        _base_token, _quote_token, _oracle, vault_token_class, solver, _market_id, _vault_token_opt
    ) =
        before(
        true
    );

    // Change vault token class.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    solver.change_vault_token_class(vault_token_class);
}

#[test]
#[should_panic(expected: ('ClassHashZero',))]
fn test_change_vault_token_class_fails_if_zero_address() {
    let (
        _base_token, _quote_token, _oracle, _vault_token_class, solver, _market_id, _vault_token_opt
    ) =
        before(
        true
    );

    // Change vault token class.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    solver.change_vault_token_class(0.try_into().unwrap());
}

#[test]
#[should_panic(expected: ('OnlyOwner',))]
fn test_mint_vault_token_fails_for_non_owner() {
    let (
        _base_token, _quote_token, _oracle, _vault_token_class, solver, _market_id, vault_token_opt
    ) =
        before(
        true
    );

    // Try to mint vault tokens.
    start_prank(CheatTarget::One(solver.contract_address), alice());
    let vault_token = vault_token_opt.unwrap();
    IVaultTokenDispatcher { contract_address: vault_token }.mint(alice(), 10);
}

#[test]
#[should_panic(expected: ('OnlyOwner',))]
fn test_burn_vault_token_fails_for_non_owner() {
    let (
        _base_token, _quote_token, _oracle, _vault_token_class, solver, _market_id, vault_token_opt
    ) =
        before(
        true
    );

    // Try to mint vault tokens.
    start_prank(CheatTarget::One(solver.contract_address), alice());
    let vault_token = vault_token_opt.unwrap();
    IVaultTokenDispatcher { contract_address: vault_token }.burn(owner(), 10);
}
