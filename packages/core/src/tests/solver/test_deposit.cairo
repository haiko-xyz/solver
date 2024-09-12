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
    tests::{
        helpers::{
            actions::deploy_mock_solver,
            utils::{before, before_custom_decimals, before_skip_approve, snapshot},
        },
    },
};

// Haiko imports.
use haiko_lib::math::math;
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
fn test_deposit_public_vault_both_tokens_at_ratio() {
    let (base_token, quote_token, _vault_token_class, solver, market_id, vault_token_opt) = before(
        true
    );

    // Deposit initial.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let base_amount = to_e18(100);
    let quote_amount = to_e18(500);
    let dep_init = solver.deposit_initial(market_id, base_amount, quote_amount);

    // Snapshot before.
    let vault_token = vault_token_opt.unwrap();
    let bef = snapshot(solver, market_id, base_token, quote_token, vault_token, alice());

    // Deposit.
    start_prank(CheatTarget::One(solver.contract_address), alice());
    let dep = solver.deposit(market_id, base_amount, quote_amount);

    // Snapshot after.
    let aft = snapshot(solver, market_id, base_token, quote_token, vault_token, alice());

    // Run checks.
    assert(dep.base_amount == base_amount, 'Base deposit');
    assert(dep.quote_amount == quote_amount, 'Quote deposit');
    assert(dep_init.shares == dep.shares, 'Shares');
    assert(aft.lp_base_bal == bef.lp_base_bal - base_amount, 'LP base bal');
    assert(aft.lp_quote_bal == bef.lp_quote_bal - quote_amount, 'LP quote bal');
    assert(aft.vault_lp_bal == bef.vault_lp_bal + dep.shares, 'LP shares');
    assert(aft.vault_total_bal == bef.vault_total_bal + dep.shares, 'LP total shares');
    assert(
        aft.market_state.base_reserves == bef.market_state.base_reserves + base_amount,
        'Base reserve'
    );
    assert(
        aft.market_state.quote_reserves == bef.market_state.quote_reserves + quote_amount,
        'Quote reserve'
    );
}

#[test]
fn test_deposit_public_vault_both_tokens_above_base_ratio() {
    let (_base_token, _quote_token, _vault_token_class, solver, market_id, _vault_token_opt) =
        before(
        true
    );

    // Deposit initial.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let base_amount = to_e18(100);
    let quote_amount = to_e18(500);
    let dep_init = solver.deposit_initial(market_id, base_amount, quote_amount);

    // Deposit.
    start_prank(CheatTarget::One(solver.contract_address), alice());
    let dep = solver.deposit(market_id, base_amount + to_e18(50), quote_amount);

    // Run checks.
    assert(dep.base_amount == base_amount, 'Base deposit');
    assert(dep.quote_amount == quote_amount, 'Quote deposit');
    assert(dep.shares == dep_init.shares, 'Shares');
}

#[test]
fn test_deposit_public_vault_both_tokens_above_quote_ratio() {
    let (_base_token, _quote_token, _vault_token_class, solver, market_id, _vault_token_opt) =
        before(
        true
    );

    // Deposit initial.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let base_amount = to_e18(100);
    let quote_amount = to_e18(500);
    let dep_init = solver.deposit_initial(market_id, base_amount, quote_amount);

    // Deposit.
    start_prank(CheatTarget::One(solver.contract_address), alice());
    let dep = solver.deposit(market_id, base_amount, quote_amount + to_e18(500));

    // Run checks.
    assert(dep.base_amount == base_amount, 'Base deposit');
    assert(dep.quote_amount == quote_amount, 'Quote deposit');
    assert(dep.shares == dep_init.shares, 'Shares');
}

#[test]
fn test_deposit_public_vault_both_tokens_above_available() {
    let (base_token, quote_token, _vault_token_class, solver, market_id, _vault_token_opt) = before(
        true
    );

    // Transfer excess balances.
    start_prank(CheatTarget::One(base_token.contract_address), owner());
    start_prank(CheatTarget::One(quote_token.contract_address), owner());
    let base_amount = to_e18(100);
    let quote_amount = to_e18(500);
    base_token.transfer(alice(), base_token.balanceOf(owner()) - base_amount * 2);
    quote_token.transfer(alice(), quote_token.balanceOf(owner()) - quote_amount * 2);
    stop_prank(CheatTarget::One(base_token.contract_address));
    stop_prank(CheatTarget::One(quote_token.contract_address));

    // Deposit initial.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    solver.deposit_initial(market_id, base_amount, quote_amount);

    // Deposit should be capped at available.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let dep = solver.deposit(market_id, base_amount * 2, quote_amount * 2);

    // Run checks.
    assert(dep.base_amount == base_amount, 'Base deposit');
    assert(dep.quote_amount == quote_amount, 'Quote deposit');
}

#[test]
fn test_deposit_public_vault_base_token_only() {
    let (base_token, quote_token, _vault_token_class, solver, market_id, vault_token_opt) = before(
        true
    );

    // Deposit initial.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let base_amount = to_e18(100);
    let quote_amount = 0;
    let dep_init = solver.deposit_initial(market_id, base_amount, quote_amount);

    // Snapshot before.
    let vault_token = vault_token_opt.unwrap();
    let bef = snapshot(solver, market_id, base_token, quote_token, vault_token, alice());

    // Deposit.
    start_prank(CheatTarget::One(solver.contract_address), alice());
    let dep = solver.deposit(market_id, base_amount, quote_amount);

    // Snapshot after.
    let aft = snapshot(solver, market_id, base_token, quote_token, vault_token, alice());

    // Run checks.
    assert(dep.base_amount == base_amount, 'Base deposit');
    assert(dep.quote_amount == quote_amount, 'Quote deposit');
    assert(dep.shares == dep_init.shares, 'Shares');

    assert(aft.lp_base_bal == bef.lp_base_bal - base_amount, 'LP base bal');
    assert(aft.lp_quote_bal == bef.lp_quote_bal - quote_amount, 'LP quote bal');
    assert(aft.vault_lp_bal == bef.vault_lp_bal + dep.shares, 'LP shares');
    assert(aft.vault_total_bal == bef.vault_total_bal + dep.shares, 'LP total shares');
    assert(
        aft.market_state.base_reserves == bef.market_state.base_reserves + base_amount,
        'Base reserve'
    );
    assert(
        aft.market_state.quote_reserves == bef.market_state.quote_reserves + quote_amount,
        'Quote reserve'
    );
}

#[test]
fn test_deposit_public_vault_quote_token_only() {
    let (base_token, quote_token, _vault_token_class, solver, market_id, vault_token_opt) = before(
        true
    );

    // Deposit initial.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let base_amount = 0;
    let quote_amount = to_e18(500);
    let dep_init = solver.deposit_initial(market_id, base_amount, quote_amount);

    // Snapshot before.
    let vault_token = vault_token_opt.unwrap();
    let bef = snapshot(solver, market_id, base_token, quote_token, vault_token, alice());

    // Deposit.
    start_prank(CheatTarget::One(solver.contract_address), alice());
    let dep = solver.deposit(market_id, base_amount, quote_amount);

    // Snapshot after.
    let aft = snapshot(solver, market_id, base_token, quote_token, vault_token, alice());

    // Run checks.
    assert(dep.base_amount == base_amount, 'Base deposit');
    assert(dep.quote_amount == quote_amount, 'Quote deposit');
    assert(dep.shares == dep_init.shares, 'Shares');

    assert(aft.lp_base_bal == bef.lp_base_bal - base_amount, 'LP base bal');
    assert(aft.lp_quote_bal == bef.lp_quote_bal - quote_amount, 'LP quote bal');
    assert(aft.vault_lp_bal == bef.vault_lp_bal + dep.shares, 'LP shares');
    assert(aft.vault_total_bal == bef.vault_total_bal + dep.shares, 'LP total shares');
    assert(
        aft.market_state.base_reserves == bef.market_state.base_reserves + base_amount,
        'Base reserve'
    );
    assert(
        aft.market_state.quote_reserves == bef.market_state.quote_reserves + quote_amount,
        'Quote reserve'
    );
}

#[test]
fn test_deposit_public_vault_multiple_lps_capped_at_available() {
    let (base_token, _quote_token, _vault_token_class, solver, market_id, vault_token_opt) = before(
        true
    );

    // Deposit initial.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let base_deposit_init = to_e18(20000);
    let quote_deposit_init = to_e18(10);
    solver.deposit_initial(market_id, base_deposit_init, quote_deposit_init);

    // For LP deposit, transfer out excess balance such that only 15k base tokens available.
    start_prank(CheatTarget::One(base_token.contract_address), alice());
    let lp_base_balance = base_token.balanceOf(alice());
    let base_available = to_e18(30000);
    let quote_available = to_e18(15);
    base_token.transfer(bob(), lp_base_balance - base_available);
    stop_prank(CheatTarget::One(base_token.contract_address));

    // Spy on events.
    let mut spy = spy_events(SpyOn::One(solver.contract_address));

    // Deposit.
    start_prank(CheatTarget::One(solver.contract_address), alice());
    let base_deposit = to_e18(40000);
    let quote_deposit = to_e18(20);
    let dep = solver.deposit(market_id, base_deposit, quote_deposit);
    assert(dep.base_amount == base_available, 'Base deposit');
    assert(dep.quote_amount == quote_available, 'Quote deposit');

    // Check vault balances.
    let vault_token_addr = vault_token_opt.unwrap();
    let vault_token = ERC20ABIDispatcher { contract_address: vault_token_addr };
    let owner_vault_bal = vault_token.balanceOf(owner());
    let lp_vault_bal = vault_token.balanceOf(alice());
    assert(
        approx_eq(lp_vault_bal, math::mul_div(owner_vault_bal, 3, 2, false), 1000), 'Vault shares'
    );

    // Check events emitted with correct amounts
    spy
        .assert_emitted(
            @array![
                (
                    solver.contract_address,
                    SolverComponent::Event::Deposit(
                        SolverComponent::Deposit {
                            market_id,
                            caller: alice(),
                            base_amount: dep.base_amount,
                            quote_amount: dep.quote_amount,
                            base_fees: dep.base_fees,
                            quote_fees: dep.quote_fees,
                            shares: dep.shares
                        }
                    )
                )
            ]
        );
}

#[test]
fn test_deposit_private_vault_both_tokens_at_arbitrary_ratio() {
    let (base_token, quote_token, _vault_token_class, solver, market_id, _vault_token_opt) = before(
        false
    );

    // Deposit initial.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let base_deposit_init = to_e18(100);
    let quote_deposit_init = to_e18(500);
    solver.deposit_initial(market_id, base_deposit_init, quote_deposit_init);

    // Snapshot before.
    let vault_token = contract_address_const::<0x0>();
    let bef = snapshot(solver, market_id, base_token, quote_token, vault_token, owner());

    // Deposit at arbitrary ratio.
    let base_deposit = to_e18(50);
    let quote_deposit = to_e18(600);
    let dep = solver.deposit(market_id, base_deposit, quote_deposit);

    // Snapshot after.
    let aft = snapshot(solver, market_id, base_token, quote_token, vault_token, owner());

    // Run checks.
    assert(base_deposit == dep.base_amount, 'Base deposit');
    assert(quote_deposit == dep.quote_amount, 'Quote deposit');
    assert(dep.shares == 0, 'Shares');
    assert(aft.lp_base_bal == bef.lp_base_bal - dep.base_amount, 'LP base bal');
    assert(aft.lp_quote_bal == bef.lp_quote_bal - dep.quote_amount, 'LP quote bal');
    assert(aft.vault_lp_bal == bef.vault_lp_bal + dep.shares, 'LP shares');
    assert(aft.vault_total_bal == bef.vault_total_bal + dep.shares, 'LP total shares');
    assert(
        aft.market_state.base_reserves == bef.market_state.base_reserves + dep.base_amount,
        'Base reserve'
    );
    assert(
        aft.market_state.quote_reserves == bef.market_state.quote_reserves + dep.quote_amount,
        'Quote reserve'
    );
}

#[test]
fn test_deposit_private_vault_base_token_only() {
    let (base_token, quote_token, _vault_token_class, solver, market_id, _vault_token_opt) = before(
        false
    );

    // Deposit initial.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let base_deposit_init = to_e18(100);
    let quote_deposit_init = to_e18(500);
    solver.deposit_initial(market_id, base_deposit_init, quote_deposit_init);

    // Snapshot before.
    let vault_token = contract_address_const::<0x0>();
    let bef = snapshot(solver, market_id, base_token, quote_token, vault_token, owner());

    // Deposit at arbitrary ratio.
    let base_deposit = to_e18(50);
    let quote_deposit = 0;
    let dep = solver.deposit(market_id, base_deposit, quote_deposit);

    // Snapshot after.
    let aft = snapshot(solver, market_id, base_token, quote_token, vault_token, owner());

    // Run checks.
    assert(base_deposit == dep.base_amount, 'Base deposit');
    assert(quote_deposit == dep.quote_amount, 'Quote deposit');
    assert(dep.shares == 0, 'Shares');
    assert(aft.lp_base_bal == bef.lp_base_bal - dep.base_amount, 'LP base bal');
    assert(aft.lp_quote_bal == bef.lp_quote_bal - dep.quote_amount, 'LP quote bal');
    assert(aft.vault_lp_bal == bef.vault_lp_bal + dep.shares, 'LP shares');
    assert(aft.vault_total_bal == bef.vault_total_bal + dep.shares, 'LP total shares');
    assert(
        aft.market_state.base_reserves == bef.market_state.base_reserves + dep.base_amount,
        'Base reserve'
    );
    assert(
        aft.market_state.quote_reserves == bef.market_state.quote_reserves + dep.quote_amount,
        'Quote reserve'
    );
}

#[test]
fn test_deposit_private_vault_quote_token_only() {
    let (base_token, quote_token, _vault_token_class, solver, market_id, _vault_token_opt) = before(
        false
    );

    // Deposit initial.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let base_deposit_init = to_e18(100);
    let quote_deposit_init = to_e18(500);
    solver.deposit_initial(market_id, base_deposit_init, quote_deposit_init);

    // Snapshot before.
    let vault_token = contract_address_const::<0x0>();
    let bef = snapshot(solver, market_id, base_token, quote_token, vault_token, owner());

    // Deposit at arbitrary ratio.
    let base_deposit = 0;
    let quote_deposit = to_e18(600);
    let dep = solver.deposit(market_id, base_deposit, quote_deposit);

    // Snapshot after.
    let aft = snapshot(solver, market_id, base_token, quote_token, vault_token, owner());

    // Run checks.
    assert(base_deposit == dep.base_amount, 'Base deposit');
    assert(quote_deposit == dep.quote_amount, 'Quote deposit');
    assert(dep.shares == 0, 'Shares');
    assert(aft.lp_base_bal == bef.lp_base_bal - dep.base_amount, 'LP base bal');
    assert(aft.lp_quote_bal == bef.lp_quote_bal - dep.quote_amount, 'LP quote bal');
    assert(aft.vault_lp_bal == bef.vault_lp_bal + dep.shares, 'LP shares');
    assert(aft.vault_total_bal == bef.vault_total_bal + dep.shares, 'LP total shares');
    assert(
        aft.market_state.base_reserves == bef.market_state.base_reserves + dep.base_amount,
        'Base reserve'
    );
    assert(
        aft.market_state.quote_reserves == bef.market_state.quote_reserves + dep.quote_amount,
        'Quote reserve'
    );
}

////////////////////////////////
// TESTS - Events
////////////////////////////////

#[test]
fn test_deposit_emits_event() {
    let (_base_token, _quote_token, _vault_token_class, solver, market_id, _vault_token_opt) =
        before(
        true
    );

    // Deposit initial.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let base_amount = to_e18(100);
    let quote_amount = 1000_000000;
    solver.deposit_initial(market_id, base_amount, quote_amount);

    // Spy on events.
    let mut spy = spy_events(SpyOn::One(solver.contract_address));

    // Deposit.
    let dep = solver.deposit(market_id, base_amount, quote_amount);

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
                            base_amount: dep.base_amount,
                            quote_amount: dep.quote_amount,
                            base_fees: dep.base_fees,
                            quote_fees: dep.quote_fees,
                            shares: dep.shares
                        }
                    )
                )
            ]
        );
}

#[test]
fn test_deposit_with_referrer_emits_event() {
    let (_base_token, _quote_token, _vault_token_class, solver, market_id, _vault_token_opt) =
        before(
        true
    );

    // Deposit initial.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let base_amount = to_e18(100);
    let quote_amount = 1000_000000;
    solver.deposit_initial(market_id, base_amount, quote_amount);

    // Spy on events.
    let mut spy = spy_events(SpyOn::One(solver.contract_address));

    // Deposit.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let dep = solver.deposit_with_referrer(market_id, base_amount, quote_amount, alice());

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
                            base_amount: dep.base_amount,
                            quote_amount: dep.quote_amount,
                            base_fees: dep.base_fees,
                            quote_fees: dep.quote_fees,
                            shares: dep.shares
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
fn test_deposit_both_amounts_zero_fails() {
    let (_base_token, _quote_token, _vault_token_class, solver, market_id, _vault_token_opt) =
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
#[should_panic(expected: ('MarketNull',))]
fn test_deposit_market_uninitialised() {
    let (_base_token, _quote_token, _vault_token_class, solver, market_id, _vault_token_opt) =
        before(
        true
    );

    // Deposit initial.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let base_amount = to_e18(100);
    let quote_amount = to_e18(500);
    solver.deposit_initial(market_id, base_amount, quote_amount);

    // Deposit.
    solver.deposit(1, base_amount, quote_amount);
}

#[test]
#[should_panic(expected: ('UseDepositInitial',))]
fn test_deposit_no_existing_deposits() {
    let (_base_token, _quote_token, _vault_token_class, solver, market_id, _vault_token_opt) =
        before(
        true
    );

    // Deposit.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let base_amount = to_e18(100);
    let quote_amount = to_e18(500);
    solver.deposit(market_id, base_amount, quote_amount);
}

#[test]
#[should_panic(expected: ('Paused',))]
fn test_deposit_paused() {
    let (_base_token, _quote_token, _vault_token_class, solver, market_id, _vault_token_opt) =
        before(
        true
    );

    // Deposit initial.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let base_amount = to_e18(100);
    let quote_amount = to_e18(500);
    solver.deposit_initial(market_id, base_amount, quote_amount);

    // Pause.
    solver.pause(market_id);

    // Deposit.
    start_prank(CheatTarget::One(solver.contract_address), alice());
    solver.deposit(market_id, base_amount, quote_amount);
}

#[test]
#[should_panic(expected: ('OnlyMarketOwner',))]
fn test_deposit_private_market_for_non_owner_caller() {
    let (_base_token, _quote_token, _vault_token_class, solver, market_id, _vault_token_opt) =
        before(
        false
    );

    // Deposit initial.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let base_amount = to_e18(100);
    let quote_amount = to_e18(500);
    solver.deposit_initial(market_id, base_amount, quote_amount);

    // Deposit.
    start_prank(CheatTarget::One(solver.contract_address), alice());
    solver.deposit(market_id, base_amount, quote_amount);
}

#[test]
#[should_panic(expected: ('BaseAllowance',))]
fn test_deposit_not_approved() {
    let (base_token, quote_token, _vault_token_class, solver, market_id, _vault_token_opt) =
        before_skip_approve(
        false
    );

    // Deposit initial.
    let base_amount = to_e18(100);
    let quote_amount = to_e18(500);
    approve(base_token, alice(), solver.contract_address, base_amount);
    approve(quote_token, alice(), solver.contract_address, quote_amount);
    start_prank(CheatTarget::One(solver.contract_address), owner());
    solver.deposit_initial(market_id, base_amount, quote_amount);

    // Deposit.
    start_prank(CheatTarget::One(solver.contract_address), alice());
    solver.deposit(market_id, base_amount, quote_amount);
}
