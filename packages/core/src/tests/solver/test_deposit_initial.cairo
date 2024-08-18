// Core lib imports.
use starknet::contract_address_const;

// Local imports.
use haiko_solver_core::{
    contracts::solver::SolverComponent,
    interfaces::{
        ISolver::{ISolverDispatcher, ISolverDispatcherTrait},
        IVaultToken::{IVaultTokenDispatcher, IVaultTokenDispatcherTrait},
    },
    types::solver::MarketInfo,
    tests::{
        helpers::{
            actions::deploy_mock_solver,
            utils::{before, before_custom_decimals, before_skip_approve, snapshot},
        },
    },
};

// Haiko imports.
use haiko_lib::helpers::params::{owner, alice};
use haiko_lib::helpers::utils::{to_e18, approx_eq_pct};

// External imports.
use snforge_std::{
    start_prank, start_warp, declare, spy_events, SpyOn, EventSpy, EventAssertions, CheatTarget
};
use openzeppelin::token::erc20::interface::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};

////////////////////////////////
// TESTS - Success cases
////////////////////////////////

#[test]
fn test_deposit_initial_public_both_tokens() {
    let (base_token, quote_token, _vault_token_class, solver, market_id, vault_token_opt) = before(
        true
    );

    // Snapshot before.
    let vault_token = vault_token_opt.unwrap();
    let bef = snapshot(solver, market_id, base_token, quote_token, vault_token, owner());

    // Deposit initial.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let base_amount = to_e18(100);
    let quote_amount = to_e18(500);
    let (base_deposit, quote_deposit, shares) = solver
        .deposit_initial(market_id, base_amount, quote_amount);

    // Snapshot after.
    let aft = snapshot(solver, market_id, base_token, quote_token, vault_token, owner());

    // Run checks.
    assert(base_deposit == base_amount, 'Base deposit');
    assert(quote_deposit == quote_amount, 'Quote deposit');
    assert(shares != 0, 'Shares');
    assert(aft.lp_base_bal == bef.lp_base_bal - base_amount, 'LP base bal');
    assert(aft.lp_quote_bal == bef.lp_quote_bal - quote_amount, 'LP quote bal');
    assert(aft.vault_lp_bal == bef.vault_lp_bal + shares, 'LP shares');
    assert(aft.vault_total_bal == bef.vault_total_bal + shares, 'LP total shares');
    assert(aft.market_state.base_reserves == base_amount, 'Base reserve');
    assert(aft.market_state.quote_reserves == quote_amount, 'Quote reserve');
}

#[test]
fn test_deposit_initial_public_base_token_only() {
    let (base_token, quote_token, _vault_token_class, solver, market_id, vault_token_opt) = before(
        true
    );

    // Snapshot before.
    let vault_token = vault_token_opt.unwrap();
    let bef = snapshot(solver, market_id, base_token, quote_token, vault_token, owner());

    // Deposit initial.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let base_amount = to_e18(100);
    let quote_amount = 0;
    let (base_deposit, quote_deposit, shares) = solver
        .deposit_initial(market_id, base_amount, quote_amount);

    // Snapshot after.
    let aft = snapshot(solver, market_id, base_token, quote_token, vault_token, owner());

    // Run checks.
    assert(base_deposit == base_amount, 'Base deposit');
    assert(quote_deposit == quote_amount, 'Quote deposit');
    assert(shares != 0, 'Shares');
    assert(aft.lp_base_bal == bef.lp_base_bal - base_amount, 'LP base bal');
    assert(aft.lp_quote_bal == bef.lp_quote_bal - quote_amount, 'LP quote bal');
    assert(aft.vault_lp_bal == bef.vault_lp_bal + shares, 'LP shares');
    assert(aft.vault_total_bal == bef.vault_total_bal + shares, 'LP total shares');
    assert(aft.market_state.base_reserves == base_amount, 'Base reserve');
    assert(aft.market_state.quote_reserves == quote_amount, 'Quote reserve');
}

#[test]
fn test_deposit_initial_public_quote_token_only() {
    let (base_token, quote_token, _vault_token_class, solver, market_id, vault_token_opt) = before(
        true
    );

    // Snapshot before.
    let vault_token = vault_token_opt.unwrap();
    let bef = snapshot(solver, market_id, base_token, quote_token, vault_token, owner());

    // Deposit initial.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let base_amount = 0;
    let quote_amount = to_e18(500);
    let (base_deposit, quote_deposit, shares) = solver
        .deposit_initial(market_id, base_amount, quote_amount);

    // Snapshot after.
    let aft = snapshot(solver, market_id, base_token, quote_token, vault_token, owner());

    // Run checks.
    assert(base_deposit == base_amount, 'Base deposit');
    assert(quote_deposit == quote_amount, 'Quote deposit');
    assert(shares != 0, 'Shares');
    assert(aft.lp_base_bal == bef.lp_base_bal - base_amount, 'LP base bal');
    assert(aft.lp_quote_bal == bef.lp_quote_bal - quote_amount, 'LP quote bal');
    assert(aft.vault_lp_bal == bef.vault_lp_bal + shares, 'LP shares');
    assert(aft.vault_total_bal == bef.vault_total_bal + shares, 'LP total shares');
    assert(aft.market_state.base_reserves == base_amount, 'Base reserve');
    assert(aft.market_state.quote_reserves == quote_amount, 'Quote reserve');
}

#[test]
fn test_deposit_initial_private_both_tokens() {
    let (base_token, quote_token, _vault_token_class, solver, market_id, _vault_token_opt) = before(
        false
    );

    // Snapshot before.
    let vault_token = contract_address_const::<0x0>();
    let bef = snapshot(solver, market_id, base_token, quote_token, vault_token, owner());

    // Deposit initial.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let base_amount = to_e18(100);
    let quote_amount = to_e18(500);
    let (base_deposit, quote_deposit, shares) = solver
        .deposit_initial(market_id, base_amount, quote_amount);

    // Snapshot after.
    let aft = snapshot(solver, market_id, base_token, quote_token, vault_token, owner());

    // Run checks.
    assert(base_deposit == base_amount, 'Base deposit');
    assert(quote_deposit == quote_amount, 'Quote deposit');
    assert(shares == 0, 'Shares');
    assert(aft.lp_base_bal == bef.lp_base_bal - base_amount, 'LP base bal');
    assert(aft.lp_quote_bal == bef.lp_quote_bal - quote_amount, 'LP quote bal');
    assert(aft.market_state.base_reserves == base_amount, 'Base reserve');
    assert(aft.market_state.quote_reserves == quote_amount, 'Quote reserve');
}

#[test]
fn test_deposit_initial_private_base_token_only() {
    let (base_token, quote_token, _vault_token_class, solver, market_id, _vault_token_opt) = before(
        false
    );

    // Snapshot before.
    let vault_token = contract_address_const::<0x0>();
    let bef = snapshot(solver, market_id, base_token, quote_token, vault_token, owner());

    // Deposit initial.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let base_amount = to_e18(100);
    let quote_amount = 0;
    let (base_deposit, quote_deposit, shares) = solver
        .deposit_initial(market_id, base_amount, quote_amount);

    // Snapshot after.
    let aft = snapshot(solver, market_id, base_token, quote_token, vault_token, owner());

    // Run checks.
    assert(base_deposit == base_amount, 'Base deposit');
    assert(quote_deposit == quote_amount, 'Quote deposit');
    assert(shares == 0, 'Shares');
    assert(aft.lp_base_bal == bef.lp_base_bal - base_amount, 'LP base bal');
    assert(aft.lp_quote_bal == bef.lp_quote_bal - quote_amount, 'LP quote bal');
    assert(aft.market_state.base_reserves == base_amount, 'Base reserve');
    assert(aft.market_state.quote_reserves == quote_amount, 'Quote reserve');
}

#[test]
fn test_deposit_initial_private_quote_token_only() {
    let (base_token, quote_token, _vault_token_class, solver, market_id, _vault_token_opt) = before(
        false
    );

    // Snapshot before.
    let vault_token = contract_address_const::<0x0>();
    let bef = snapshot(solver, market_id, base_token, quote_token, vault_token, owner());

    // Deposit initial.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let base_amount = 0;
    let quote_amount = to_e18(500);
    let (base_deposit, quote_deposit, shares) = solver
        .deposit_initial(market_id, base_amount, quote_amount);

    // Snapshot after.
    let aft = snapshot(solver, market_id, base_token, quote_token, vault_token, owner());

    // Run checks.
    assert(base_deposit == base_amount, 'Base deposit');
    assert(quote_deposit == quote_amount, 'Quote deposit');
    assert(shares == 0, 'Shares');
    assert(aft.lp_base_bal == bef.lp_base_bal - base_amount, 'LP base bal');
    assert(aft.lp_quote_bal == bef.lp_quote_bal - quote_amount, 'LP quote bal');
    assert(aft.market_state.base_reserves == base_amount, 'Base reserve');
    assert(aft.market_state.quote_reserves == quote_amount, 'Quote reserve');
}

////////////////////////////////
// TESTS - Events
////////////////////////////////

#[test]
fn test_deposit_initial_emits_event() {
    let (_base_token, _quote_token, _vault_token_class, solver, market_id, _vault_token_opt) =
        before(
        true
    );

    // Spy on events.
    let mut spy = spy_events(SpyOn::One(solver.contract_address));

    // Deposit initial.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let base_amount = to_e18(100);
    let quote_amount = 1000_000000;
    let (base_deposit, quote_deposit, shares) = solver
        .deposit_initial(market_id, base_amount, quote_amount);

    // Check events emitted.
    spy
        .assert_emitted(
            @array![
                (
                    solver.contract_address,
                    SolverComponent::Event::Deposit(
                        SolverComponent::Deposit {
                            market_id,
                            caller: owner(),
                            base_amount: base_deposit,
                            quote_amount: quote_deposit,
                            shares
                        }
                    )
                )
            ]
        );
}

#[test]
fn test_deposit_initial_with_referrer_emits_event() {
    let (_base_token, _quote_token, _vault_token_class, solver, market_id, _vault_token_opt) =
        before(
        true
    );

    // Spy on events.
    let mut spy = spy_events(SpyOn::One(solver.contract_address));

    // Deposit initial.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let base_amount = to_e18(100);
    let quote_amount = 1000_000000;
    let (base_deposit, quote_deposit, shares) = solver
        .deposit_initial_with_referrer(market_id, base_amount, quote_amount, alice());

    // Check events emitted.
    spy
        .assert_emitted(
            @array![
                (
                    solver.contract_address,
                    SolverComponent::Event::Referral(
                        SolverComponent::Referral { caller: owner(), referrer: alice(), }
                    )
                ),
                (
                    solver.contract_address,
                    SolverComponent::Event::Deposit(
                        SolverComponent::Deposit {
                            market_id,
                            caller: owner(),
                            base_amount: base_deposit,
                            quote_amount: quote_deposit,
                            shares
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
fn test_deposit_initial_both_amounts_zero_fails() {
    let (_base_token, _quote_token, _vault_token_class, solver, market_id, _vault_token_opt) =
        before(
        true
    );

    // Deposit initial.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let base_amount = 0;
    let quote_amount = 0;
    solver.deposit_initial(market_id, base_amount, quote_amount);
}

#[test]
#[should_panic(expected: ('MarketNull',))]
fn test_deposit_initial_uninitialised_market_fails() {
    let (_base_token, _quote_token, _vault_token_class, solver, _market_id, _vault_token_opt) =
        before(
        true
    );

    // Deposit initial.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let base_amount = to_e18(100);
    let quote_amount = to_e18(500);
    solver.deposit_initial(1, base_amount, quote_amount);
}

#[test]
#[should_panic(expected: ('UseDeposit',))]
fn test_deposit_initial_on_market_with_existing_deposits() {
    let (_base_token, _quote_token, _vault_token_class, solver, market_id, _vault_token_opt) =
        before(
        true
    );

    // Deposit initial.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let base_amount = to_e18(100);
    let quote_amount = to_e18(500);
    solver.deposit_initial(market_id, base_amount, quote_amount);

    // Deposit initial again.
    solver.deposit_initial(market_id, base_amount, quote_amount);
}

#[test]
#[should_panic(expected: ('Paused',))]
fn test_deposit_initial_on_paused_market() {
    let (_base_token, _quote_token, _vault_token_class, solver, market_id, _vault_token_opt) =
        before(
        true
    );

    // Pause market.
    solver.pause(market_id);

    // Deposit initial.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let base_amount = to_e18(100);
    let quote_amount = to_e18(500);
    solver.deposit_initial(market_id, base_amount, quote_amount);
}

#[test]
#[should_panic(expected: ('OnlyMarketOwner',))]
fn test_deposit_initial_on_private_market_for_non_owner_caller() {
    let (_base_token, _quote_token, _vault_token_class, solver, market_id, _vault_token_opt) =
        before(
        false
    );

    // Deposit initial.
    start_prank(CheatTarget::One(solver.contract_address), alice());
    let base_amount = to_e18(100);
    let quote_amount = to_e18(500);
    solver.deposit_initial(market_id, base_amount, quote_amount);
}

#[test]
#[should_panic(expected: ('BaseAllowance',))]
fn test_deposit_initial_not_approved() {
    let (_base_token, _quote_token, _vault_token_class, solver, market_id, _vault_token_opt) =
        before_skip_approve(
        false
    );

    // Deposit initial.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let base_amount = to_e18(100);
    let quote_amount = to_e18(500);
    solver.deposit_initial(market_id, base_amount, quote_amount);
}
