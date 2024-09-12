// Core lib imports.
use starknet::contract_address_const;

// Local imports.
use haiko_solver_core::{
    contracts::solver::SolverComponent,
    interfaces::{
        ISolver::{ISolverDispatcher, ISolverDispatcherTrait},
        IVaultToken::{IVaultTokenDispatcher, IVaultTokenDispatcherTrait},
    },
    types::{MarketInfo, SwapParams},
    tests::helpers::{actions::deploy_mock_solver, utils::{before, snapshot},},
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
fn test_withdraw_partial_shares_from_public_vault() {
    let (base_token, quote_token, _vault_token_class, solver, market_id, vault_token_opt) = before(
        true
    );

    // Deposit initial.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let base_amount = to_e18(100);
    let quote_amount = to_e18(500);
    solver.deposit_initial(market_id, base_amount, quote_amount);

    // Deposit.
    start_prank(CheatTarget::One(solver.contract_address), alice());
    let dep = solver.deposit(market_id, base_amount, quote_amount);

    // Swap.
    let params = SwapParams {
        is_buy: false,
        amount: to_e18(10),
        exact_input: true,
        threshold_sqrt_price: Option::None(()),
        threshold_amount: Option::None(()),
        deadline: Option::None(()),
    };
    let swap = solver.swap(market_id, params);

    // Snapshot before.
    let vault_token = vault_token_opt.unwrap();
    let bef = snapshot(solver, market_id, base_token, quote_token, vault_token, alice());

    // Withdraw.
    start_prank(CheatTarget::One(solver.contract_address), alice());
    let wd = solver.withdraw_public(market_id, dep.shares / 2);

    // Snapshot after.
    let aft = snapshot(solver, market_id, base_token, quote_token, vault_token, alice());

    // Run checks.
    assert(
        approx_eq(wd.base_amount, (base_amount * 2 + swap.amount_in - swap.fees) / 4, 10),
        'Base deposit'
    );
    assert(
        approx_eq(wd.quote_amount, (quote_amount * 2 - swap.amount_out) / 4, 10), 'Quote deposit'
    );
    assert(approx_eq_pct(wd.base_fees, swap.fees / 2, 10), 'Base fees');
    assert(wd.quote_fees == 0, 'Quote fees');
    assert(aft.lp_base_bal == bef.lp_base_bal + wd.base_amount + wd.base_fees, 'LP base bal');
    assert(aft.lp_quote_bal == bef.lp_quote_bal + wd.quote_amount + wd.quote_fees, 'LP quote bal');
    assert(aft.vault_lp_bal == bef.vault_lp_bal - dep.shares / 2, 'LP shares');
    assert(aft.vault_total_bal == bef.vault_total_bal - dep.shares / 2, 'LP total shares');
    assert(
        aft.market_state.base_reserves == bef.market_state.base_reserves - wd.base_amount,
        'Base reserve'
    );
    assert(
        aft.market_state.quote_reserves == bef.market_state.quote_reserves - wd.quote_amount,
        'Quote reserve'
    );
}

#[test]
fn test_withdraw_remaining_shares_from_public_vault() {
    let (base_token, quote_token, _vault_token_class, solver, market_id, vault_token_opt) = before(
        true
    );

    // Deposit initial.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let base_amount = to_e18(100);
    let quote_amount = to_e18(500);
    let dep_init = solver.deposit_initial(market_id, base_amount, quote_amount);

    // Deposit.
    start_prank(CheatTarget::One(solver.contract_address), alice());
    let dep = solver.deposit(market_id, base_amount, quote_amount);

    // Swap.
    let params = SwapParams {
        is_buy: false,
        amount: to_e18(10),
        exact_input: true,
        threshold_sqrt_price: Option::None(()),
        threshold_amount: Option::None(()),
        deadline: Option::None(()),
    };
    let swap = solver.swap(market_id, params);

    // Withdraw owner.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    solver.withdraw_public(market_id, dep_init.shares);

    // Snapshot before.
    let vault_token = vault_token_opt.unwrap();
    let bef = snapshot(solver, market_id, base_token, quote_token, vault_token, alice());

    // Withdraw LP.
    start_prank(CheatTarget::One(solver.contract_address), alice());
    let wd = solver.withdraw_public(market_id, dep.shares);

    // Snapshot after.
    let aft = snapshot(solver, market_id, base_token, quote_token, vault_token, alice());

    // Run checks.
    assert(
        approx_eq(wd.base_amount, (base_amount * 2 + swap.amount_in - swap.fees) / 2, 1),
        'Base deposit'
    );
    assert(
        approx_eq(wd.quote_amount, (quote_amount * 2 - swap.amount_out) / 2, 1), 'Quote deposit'
    );
    assert(approx_eq_pct(wd.base_fees, swap.fees / 2, 10), 'Base fees');
    assert(wd.quote_fees == 0, 'Quote fees');
    assert(aft.lp_base_bal == bef.lp_base_bal + wd.base_amount + wd.base_fees, 'LP base bal');
    assert(aft.lp_quote_bal == bef.lp_quote_bal + wd.quote_amount, 'LP quote bal');
    assert(aft.vault_lp_bal == bef.vault_lp_bal - dep.shares, 'LP shares');
    assert(aft.vault_total_bal == bef.vault_total_bal - dep.shares, 'LP total shares');
    assert(
        aft.market_state.base_reserves == bef.market_state.base_reserves - wd.base_amount,
        'Base reserve'
    );
    assert(
        aft.market_state.quote_reserves == bef.market_state.quote_reserves - wd.quote_amount,
        'Quote reserve'
    );
}

#[test]
fn test_withdraw_allowed_even_if_paused() {
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
    start_prank(CheatTarget::One(solver.contract_address), alice());
    let dep = solver.deposit(market_id, base_amount, quote_amount);

    // Pause.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    solver.pause(market_id);

    // Withdraw.
    start_prank(CheatTarget::One(solver.contract_address), alice());
    solver.withdraw_public(market_id, dep.shares);
}

#[test]
fn test_withdraw_private_base_only() {
    let (_base_token, _quote_token, _vault_token_class, solver, market_id, _vault_token_opt) =
        before(
        false
    );

    // Deposit initial.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let base_amount = to_e18(100);
    let quote_amount = to_e18(500);
    solver.deposit_initial(market_id, base_amount, quote_amount);

    // Swap.
    let params = SwapParams {
        is_buy: false,
        amount: to_e18(10),
        exact_input: true,
        threshold_sqrt_price: Option::None(()),
        threshold_amount: Option::None(()),
        deadline: Option::None(()),
    };
    let swap = solver.swap(market_id, params);

    // Snapshot before.
    let vault_token = contract_address_const::<0x0>();
    let bef = snapshot(solver, market_id, _base_token, _quote_token, vault_token, owner());

    // Withdraw.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let wd = solver.withdraw_private(market_id, base_amount + swap.amount_in, 0);

    // Snapshot after.
    let aft = snapshot(solver, market_id, _base_token, _quote_token, vault_token, owner());

    // Run checks.
    assert(approx_eq(wd.base_amount, base_amount + swap.amount_in - swap.fees, 1), 'Base withdraw');
    assert(wd.quote_amount == 0, 'Quote withdraw');
    assert(approx_eq(wd.base_fees, swap.fees, 1), 'Base fees');
    assert(wd.quote_fees == 0, 'Quote fees');
    assert(aft.lp_base_bal == bef.lp_base_bal + wd.base_amount + wd.base_fees, 'LP base bal');
    assert(aft.lp_quote_bal == bef.lp_quote_bal + wd.quote_amount + wd.quote_fees, 'LP quote bal');
    assert(aft.vault_lp_bal == bef.vault_lp_bal, 'LP shares');
    assert(aft.vault_total_bal == bef.vault_total_bal, 'LP total shares');
}

#[test]
fn test_withdraw_private_quote_only() {
    let (_base_token, _quote_token, _vault_token_class, solver, market_id, _vault_token_opt) =
        before(
        false
    );

    // Deposit initial.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let base_amount = to_e18(100);
    let quote_amount = to_e18(500);
    solver.deposit_initial(market_id, base_amount, quote_amount);

    // Swap.
    let params = SwapParams {
        is_buy: false,
        amount: to_e18(10),
        exact_input: true,
        threshold_sqrt_price: Option::None(()),
        threshold_amount: Option::None(()),
        deadline: Option::None(()),
    };
    let swap = solver.swap(market_id, params);

    // Snapshot before.
    let vault_token = contract_address_const::<0x0>();
    let bef = snapshot(solver, market_id, _base_token, _quote_token, vault_token, owner());

    // Withdraw.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let wd = solver.withdraw_private(market_id, 0, quote_amount); // will be capped at available

    // Snapshot after.
    let aft = snapshot(solver, market_id, _base_token, _quote_token, vault_token, owner());

    // Run checks.
    assert(wd.base_amount == 0, 'Base withdraw');
    assert(approx_eq(wd.quote_amount, quote_amount - swap.amount_out, 1), 'Quote withdraw');
    assert(approx_eq_pct(wd.base_fees, swap.fees, 10), 'Base fees');
    assert(wd.quote_fees == 0, 'Quote fees');
    assert(aft.lp_base_bal == bef.lp_base_bal + wd.base_amount + wd.base_fees, 'LP base bal');
    assert(aft.lp_quote_bal == bef.lp_quote_bal + wd.quote_amount + wd.quote_fees, 'LP quote bal');
    assert(aft.vault_lp_bal == bef.vault_lp_bal, 'LP shares');
    assert(aft.vault_total_bal == bef.vault_total_bal, 'LP total shares');
}

#[test]
fn test_withdraw_private_partial_amounts() {
    let (_base_token, _quote_token, _vault_token_class, solver, market_id, _vault_token_opt) =
        before(
        false
    );

    // Deposit initial.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let base_amount = to_e18(100);
    let quote_amount = to_e18(500);
    solver.deposit_initial(market_id, base_amount, quote_amount);

    // Swap.
    let params = SwapParams {
        is_buy: false,
        amount: to_e18(10),
        exact_input: true,
        threshold_sqrt_price: Option::None(()),
        threshold_amount: Option::None(()),
        deadline: Option::None(()),
    };
    let swap = solver.swap(market_id, params);

    // Snapshot before.
    let vault_token = contract_address_const::<0x0>();
    let bef = snapshot(solver, market_id, _base_token, _quote_token, vault_token, owner());

    // Withdraw.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let wd = solver
        .withdraw_private(
            market_id, (base_amount + swap.amount_in) / 2, (quote_amount - swap.amount_out) / 2
        );

    // Snapshot after.
    let aft = snapshot(solver, market_id, _base_token, _quote_token, vault_token, owner());

    // Run checks.
    assert(approx_eq(wd.base_amount, (base_amount + swap.amount_in) / 2, 1), 'Base withdraw');
    assert(approx_eq(wd.quote_amount, (quote_amount - swap.amount_out) / 2, 1), 'Quote withdraw');
    assert(approx_eq(wd.base_fees, swap.fees, 1), 'Base fees');
    assert(wd.quote_fees == 0, 'Quote fees');
    assert(aft.lp_base_bal == bef.lp_base_bal + wd.base_amount + wd.base_fees, 'LP base bal');
    assert(aft.lp_quote_bal == bef.lp_quote_bal + wd.quote_amount + wd.quote_fees, 'LP quote bal');
    assert(aft.vault_lp_bal == bef.vault_lp_bal, 'LP shares');
    assert(aft.vault_total_bal == bef.vault_total_bal, 'LP total shares');
    assert(
        aft.market_state.base_reserves == bef.market_state.base_reserves - wd.base_amount,
        'Base reserve'
    );
    assert(
        aft.market_state.quote_reserves == bef.market_state.quote_reserves - wd.quote_amount,
        'Quote reserve'
    );
}

#[test]
fn test_withdraw_all_remaining_balances_from_private_vault() {
    let (_base_token, _quote_token, _vault_token_class, solver, market_id, _vault_token_opt) =
        before(
        false
    );

    // Deposit initial.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let base_amount = to_e18(100);
    let quote_amount = to_e18(500);
    solver.deposit_initial(market_id, base_amount, quote_amount);

    // Swap.
    let params = SwapParams {
        is_buy: false,
        amount: to_e18(10),
        exact_input: true,
        threshold_sqrt_price: Option::None(()),
        threshold_amount: Option::None(()),
        deadline: Option::None(()),
    };
    let swap = solver.swap(market_id, params);

    // Snapshot before.
    let vault_token = contract_address_const::<0x0>();
    let bef = snapshot(solver, market_id, _base_token, _quote_token, vault_token, owner());

    // Withdraw.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let wd = solver
        .withdraw_private(
            market_id, base_amount + swap.amount_in - swap.fees, quote_amount - swap.amount_out
        );

    // Snapshot after.
    let aft = snapshot(solver, market_id, _base_token, _quote_token, vault_token, owner());

    // Run checks.
    assert(approx_eq(wd.base_amount, base_amount + swap.amount_in - swap.fees, 1), 'Base withdraw');
    assert(approx_eq(wd.quote_amount, quote_amount - swap.amount_out, 1), 'Quote withdraw');
    assert(wd.base_fees == swap.fees, 'Base fees');
    assert(wd.quote_fees == 0, 'Quote fees');
    assert(aft.lp_base_bal == bef.lp_base_bal + wd.base_amount + wd.base_fees, 'LP base bal');
    assert(aft.lp_quote_bal == bef.lp_quote_bal + wd.quote_amount + wd.quote_fees, 'LP quote bal');
    assert(aft.vault_lp_bal == 0, 'LP shares');
    assert(aft.vault_total_bal == 0, 'LP total shares');
    assert(
        aft.market_state.base_reserves == bef.market_state.base_reserves - wd.base_amount,
        'Base reserve'
    );
    assert(
        aft.market_state.quote_reserves == bef.market_state.quote_reserves - wd.quote_amount,
        'Quote reserve'
    );
    assert(
        aft.market_state.base_fees == bef.market_state.base_fees - wd.base_fees, 'Base fees reserve'
    );
    assert(
        aft.market_state.quote_fees == bef.market_state.quote_fees - wd.quote_fees,
        'Quote fees reserve'
    );
}

#[test]
fn test_withdraw_more_than_available_correctly_caps_amount_for_private_vault() {
    let (_base_token, _quote_token, _vault_token_class, solver, market_id, _vault_token_opt) =
        before(
        false
    );

    // Deposit initial.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let base_amount = to_e18(100);
    let quote_amount = to_e18(500);
    solver.deposit_initial(market_id, base_amount, quote_amount);

    // Swap.
    let params = SwapParams {
        is_buy: false,
        amount: to_e18(10),
        exact_input: true,
        threshold_sqrt_price: Option::None(()),
        threshold_amount: Option::None(()),
        deadline: Option::None(()),
    };
    let swap = solver.swap(market_id, params);

    // Withdraw.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let wd = solver.withdraw_private(market_id, base_amount * 2, quote_amount * 2);

    // Run checks.
    assert(approx_eq(wd.base_amount, base_amount + swap.amount_in - swap.fees, 1), 'Base withdraw');
    assert(approx_eq(wd.quote_amount, quote_amount - swap.amount_out, 1), 'Quote withdraw');
    assert(wd.base_fees == swap.fees, 'Base fees');
    assert(wd.quote_fees == 0, 'Quote fees');
}

////////////////////////////////
// TESTS - Events
////////////////////////////////

#[test]
fn test_withdraw_public_emits_event() {
    let (_base_token, _quote_token, _vault_token_class, solver, market_id, _vault_token_opt) =
        before(
        true
    );

    // Deposit initial.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let base_amount = to_e18(100);
    let quote_amount = 1000_000000;
    let dep_init = solver.deposit_initial(market_id, base_amount, quote_amount);

    // Spy on events.
    let mut spy = spy_events(SpyOn::One(solver.contract_address));

    // Withdraw.
    let wd = solver.withdraw_public(market_id, dep_init.shares);

    // Check events emitted.
    spy
        .assert_emitted(
            @array![
                (
                    solver.contract_address,
                    SolverComponent::Event::Withdraw(
                        SolverComponent::Withdraw {
                            market_id,
                            caller: owner(),
                            base_amount: wd.base_amount,
                            quote_amount: wd.quote_amount,
                            base_fees: wd.base_fees,
                            quote_fees: wd.quote_fees,
                            shares: dep_init.shares,
                        }
                    )
                )
            ]
        );
}

#[test]
fn test_withdraw_private_emits_event() {
    let (_base_token, _quote_token, _vault_token_class, solver, market_id, _vault_token_opt) =
        before(
        false
    );

    // Deposit initial.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let base_amount = to_e18(100);
    let quote_amount = 1000_000000;
    let dep_init = solver.deposit_initial(market_id, base_amount, quote_amount);

    // Spy on events.
    let mut spy = spy_events(SpyOn::One(solver.contract_address));

    // Withdraw.
    let wd = solver.withdraw_private(market_id, base_amount, quote_amount);

    // Check events emitted.
    spy
        .assert_emitted(
            @array![
                (
                    solver.contract_address,
                    SolverComponent::Event::Withdraw(
                        SolverComponent::Withdraw {
                            market_id,
                            caller: owner(),
                            base_amount: wd.base_amount,
                            quote_amount: wd.quote_amount,
                            base_fees: wd.base_fees,
                            quote_fees: wd.quote_fees,
                            shares: dep_init.shares,
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
#[should_panic(expected: ('SharesZero',))]
fn test_withdraw_public_zero_shares() {
    let (_base_token, _quote_token, _vault_token_class, solver, market_id, _vault_token_opt) =
        before(
        true
    );

    // Deposit initial.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    solver.deposit_initial(market_id, to_e18(100), to_e18(500));

    // Withdraw.
    solver.withdraw_public(market_id, 0);
}

#[test]
#[should_panic(expected: ('InsuffShares',))]
fn test_withdraw_public_more_shares_than_available() {
    let (_base_token, _quote_token, _vault_token_class, solver, market_id, _vault_token_opt) =
        before(
        true
    );

    // Deposit initial.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let dep_init = solver.deposit_initial(market_id, to_e18(100), to_e18(500));

    // Withdraw.
    solver.withdraw_public(market_id, dep_init.shares + 1);
}

#[test]
#[should_panic(expected: ('MarketNull',))]
fn test_withdraw_public_uninitialised_market() {
    let (_base_token, _quote_token, _vault_token_class, solver, _market_id, _vault_token_opt) =
        before(
        true
    );

    // Withdraw.
    solver.withdraw_public(1, 1000);
}

#[test]
#[should_panic(expected: ('UseWithdrawPublic',))]
fn test_withdraw_custom_amounts_fail_for_public_vault() {
    let (_base_token, _quote_token, _vault_token_class, solver, market_id, _vault_token_opt) =
        before(
        true
    );

    // Deposit initial.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let base_amount = to_e18(100);
    let quote_amount = to_e18(500);
    solver.deposit_initial(market_id, base_amount, quote_amount);

    // Withdraw.
    solver.withdraw_private(market_id, base_amount, quote_amount);
}

#[test]
#[should_panic(expected: ('AmountZero',))]
fn test_withdraw_private_zero_amounts() {
    let (_base_token, _quote_token, _vault_token_class, solver, market_id, _vault_token_opt) =
        before(
        false
    );

    // Deposit initial.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    solver.deposit_initial(market_id, to_e18(100), to_e18(500));

    // Withdraw.
    solver.withdraw_private(market_id, 0, 0);
}

#[test]
#[should_panic(expected: ('MarketNull',))]
fn test_withdraw_private_uninitialised_market() {
    let (_base_token, _quote_token, _vault_token_class, solver, _market_id, _vault_token_opt) =
        before(
        false
    );

    // Withdraw.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    solver.withdraw_private(1, to_e18(100), to_e18(500));
}

#[test]
#[should_panic(expected: ('OnlyMarketOwner',))]
fn test_withdraw_private_not_owner() {
    let (_base_token, _quote_token, _vault_token_class, solver, market_id, _vault_token_opt) =
        before(
        false
    );

    // Withdraw.
    start_prank(CheatTarget::One(solver.contract_address), alice());
    solver.withdraw_private(market_id, to_e18(100), to_e18(500));
}

#[test]
#[should_panic(expected: ('UseWithdrawPrivate',))]
fn test_withdraw_public_fail_for_private_vault() {
    let (_base_token, _quote_token, _vault_token_class, solver, market_id, _vault_token_opt) =
        before(
        false
    );

    // Deposit initial.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let base_amount = to_e18(100);
    let quote_amount = to_e18(500);
    solver.deposit_initial(market_id, base_amount, quote_amount);

    // Withdraw.
    solver.withdraw_public(market_id, 1000);
}
