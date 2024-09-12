// Core lib imports.
use starknet::contract_address_const;

// Local imports.
use haiko_solver_core::{
    contracts::solver::SolverComponent,
    interfaces::ISolver::{ISolverDispatcher, ISolverDispatcherTrait}, types::SwapParams,
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
    let (base_token, quote_token, _oracle, _vault_token_class, solver, market_id, vault_token_opt) =
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
    assert(approx_eq(wd.base_fees, swap.fees / 2, 10), 'Base fees withdraw');
    assert(wd.quote_fees == 0, 'Quote fees withdraw');
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
    assert(aft.bid.lower_sqrt_price == bef.bid.lower_sqrt_price, 'Bid lower sqrt price');
    assert(aft.bid.upper_sqrt_price == bef.bid.upper_sqrt_price, 'Bid upper sqrt price');
    assert(
        approx_eq(aft.bid.liquidity.into(), bef.bid.liquidity.into() * 3 / 4, 1000), 'Bid liquidity'
    );
    assert(aft.ask.lower_sqrt_price == bef.ask.lower_sqrt_price, 'Ask lower sqrt price');
    assert(aft.ask.upper_sqrt_price == bef.ask.upper_sqrt_price, 'Ask upper sqrt price');
    assert(
        approx_eq(aft.ask.liquidity.into(), bef.ask.liquidity.into() * 3 / 4, 1000), 'Ask liquidity'
    );
}

#[test]
fn test_withdraw_remaining_shares_from_public_vault() {
    let (base_token, quote_token, _oracle, _vault_token_class, solver, market_id, vault_token_opt) =
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
    assert(approx_eq(wd.base_fees, swap.fees / 2, 1), 'Base fees withdraw');
    assert(wd.quote_fees == 0, 'Quote fees withdraw');
    assert(aft.lp_base_bal == bef.lp_base_bal + wd.base_amount + wd.base_fees, 'LP base bal');
    assert(aft.lp_quote_bal == bef.lp_quote_bal + wd.quote_amount + wd.quote_fees, 'LP quote bal');
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
    assert(aft.bid.lower_sqrt_price == 0, 'Bid lower sqrt price');
    assert(aft.bid.upper_sqrt_price == 0, 'Bid upper sqrt price');
    assert(aft.bid.liquidity == 0, 'Bid liquidity');
    assert(aft.ask.lower_sqrt_price == 0, 'Ask lower sqrt price');
    assert(aft.ask.upper_sqrt_price == 0, 'Ask upper sqrt price');
    assert(aft.ask.liquidity == 0, 'Ask liquidity');
}

#[test]
fn test_withdraw_allowed_even_if_paused() {
    let (
        _base_token, _quote_token, _oracle, _vault_token_class, solver, market_id, _vault_token_opt
    ) =
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
    let (
        _base_token, _quote_token, _oracle, _vault_token_class, solver, market_id, _vault_token_opt
    ) =
        before(
        false
    );

    // Disable max skew.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let repl_solver = IReplicatingSolverDispatcher { contract_address: solver.contract_address };
    let mut market_params = default_market_params();
    market_params.max_skew = 0;
    repl_solver.queue_market_params(market_id, market_params);
    repl_solver.set_market_params(market_id);

    // Deposit initial.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let base_amount = to_e18(100);
    let quote_amount = to_e18(500);
    solver.deposit_initial(market_id, base_amount, quote_amount);

    // Swap.
    start_prank(CheatTarget::One(solver.contract_address), alice());
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
    assert(
        approx_eq(wd.base_amount, base_amount + swap.amount_in - swap.fees, 10), 'Base withdraw'
    );
    assert(wd.quote_amount == 0, 'Quote withdraw');
    assert(approx_eq(wd.base_fees, swap.fees, 10), 'Base fees withdraw');
    assert(wd.quote_fees == 0, 'Quote fees withdraw');
    assert(aft.lp_base_bal == bef.lp_base_bal + wd.base_amount + wd.base_fees, 'LP base bal');
    assert(aft.lp_quote_bal == bef.lp_quote_bal + wd.quote_amount + wd.quote_fees, 'LP quote bal');
    assert(aft.vault_lp_bal == bef.vault_lp_bal, 'LP shares');
    assert(aft.vault_total_bal == bef.vault_total_bal, 'LP total shares');
}

#[test]
fn test_withdraw_private_quote_only() {
    let (
        _base_token, _quote_token, _oracle, _vault_token_class, solver, market_id, _vault_token_opt
    ) =
        before(
        false
    );

    // Disable max skew.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let repl_solver = IReplicatingSolverDispatcher { contract_address: solver.contract_address };
    let mut market_params = default_market_params();
    market_params.max_skew = 0;
    repl_solver.queue_market_params(market_id, market_params);
    repl_solver.set_market_params(market_id);

    // Deposit initial.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let base_amount = to_e18(100);
    let quote_amount = to_e18(500);
    solver.deposit_initial(market_id, base_amount, quote_amount);

    // Swap.
    start_prank(CheatTarget::One(solver.contract_address), alice());
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
    let wd = solver.withdraw_private(market_id, 0, quote_amount - swap.amount_out);

    // Snapshot after.
    let aft = snapshot(solver, market_id, _base_token, _quote_token, vault_token, owner());

    // Run checks.
    assert(wd.base_amount == 0, 'Base withdraw');
    assert(approx_eq(wd.quote_amount, quote_amount - swap.amount_out, 10), 'Quote withdraw');
    assert(approx_eq(wd.base_fees, swap.fees, 10), 'Base fees withdraw');
    assert(wd.quote_fees == 0, 'Quote fees withdraw');
    assert(aft.lp_base_bal == bef.lp_base_bal + wd.base_amount + wd.base_fees, 'LP base bal');
    assert(aft.lp_quote_bal == bef.lp_quote_bal + wd.quote_amount + wd.quote_fees, 'LP quote bal');
    assert(aft.vault_lp_bal == bef.vault_lp_bal, 'LP shares');
    assert(aft.vault_total_bal == bef.vault_total_bal, 'LP total shares');
}

#[test]
fn test_withdraw_private_partial_amounts() {
    let (
        _base_token, _quote_token, _oracle, _vault_token_class, solver, market_id, _vault_token_opt
    ) =
        before(
        false
    );

    // Deposit initial.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let base_amount = to_e18(100);
    let quote_amount = to_e18(500);
    solver.deposit_initial(market_id, base_amount, quote_amount);

    // Swap.
    start_prank(CheatTarget::One(solver.contract_address), alice());
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
            market_id,
            (base_amount + swap.amount_in - swap.fees) / 2,
            (quote_amount - swap.amount_out) / 2
        );

    // Snapshot after.
    let aft = snapshot(solver, market_id, _base_token, _quote_token, vault_token, owner());

    // Run checks.
    assert(
        approx_eq(wd.base_amount, (base_amount + swap.amount_in - swap.fees) / 2, 10),
        'Base withdraw'
    );
    assert(approx_eq(wd.quote_amount, (quote_amount - swap.amount_out) / 2, 10), 'Quote withdraw');
    assert(approx_eq(wd.base_fees, swap.fees, 10), 'Base fees withdraw');
    assert(wd.quote_fees == 0, 'Quote fees withdraw');
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
    assert(aft.bid.lower_sqrt_price == bef.bid.lower_sqrt_price, 'Bid lower sqrt price');
    assert(aft.bid.upper_sqrt_price == bef.bid.upper_sqrt_price, 'Bid upper sqrt price');
    assert(
        approx_eq(aft.bid.liquidity.into(), bef.bid.liquidity.into() / 2, 1000), 'Bid liquidity'
    );
    assert(aft.ask.lower_sqrt_price == bef.ask.lower_sqrt_price, 'Ask lower sqrt price');
    assert(aft.ask.upper_sqrt_price == bef.ask.upper_sqrt_price, 'Ask upper sqrt price');
    assert(
        approx_eq(aft.ask.liquidity.into(), bef.ask.liquidity.into() / 2, 1000), 'Ask liquidity'
    );
}

#[test]
fn test_withdraw_all_remaining_balances_from_private_vault() {
    let (
        _base_token, _quote_token, _oracle, _vault_token_class, solver, market_id, _vault_token_opt
    ) =
        before(
        false
    );

    // Deposit initial.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let base_amount = to_e18(100);
    let quote_amount = to_e18(500);
    solver.deposit_initial(market_id, base_amount, quote_amount);

    // Swap.
    start_prank(CheatTarget::One(solver.contract_address), alice());
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
        .withdraw_private(market_id, base_amount + swap.amount_in, quote_amount - swap.amount_out);

    // Snapshot after.
    let aft = snapshot(solver, market_id, _base_token, _quote_token, vault_token, owner());

    // Run checks.
    assert(
        approx_eq(wd.base_amount, base_amount + swap.amount_in - swap.fees, 10), 'Base withdraw'
    );
    assert(approx_eq(wd.quote_amount, quote_amount - swap.amount_out, 10), 'Quote withdraw');
    assert(approx_eq(wd.base_fees, swap.fees, 10), 'Base fees withdraw');
    assert(wd.quote_fees == 0, 'Quote fees withdraw');
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
    assert(aft.bid.lower_sqrt_price == 0, 'Bid lower sqrt price');
    assert(aft.bid.upper_sqrt_price == 0, 'Bid upper sqrt price');
    assert(aft.bid.liquidity == 0, 'Bid liquidity');
    assert(aft.ask.lower_sqrt_price == 0, 'Ask lower sqrt price');
    assert(aft.ask.upper_sqrt_price == 0, 'Ask upper sqrt price');
    assert(aft.ask.liquidity == 0, 'Ask liquidity');
}

#[test]
fn test_withdraw_more_than_available_correctly_caps_amount_for_private_vault() {
    let (
        _base_token, _quote_token, _oracle, _vault_token_class, solver, market_id, _vault_token_opt
    ) =
        before(
        false
    );

    // Deposit initial.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let base_amount = to_e18(100);
    let quote_amount = to_e18(500);
    solver.deposit_initial(market_id, base_amount, quote_amount);

    // Swap.
    start_prank(CheatTarget::One(solver.contract_address), alice());
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
    assert(
        approx_eq(wd.base_amount, base_amount + swap.amount_in - swap.fees, 10), 'Base withdraw'
    );
    assert(approx_eq(wd.quote_amount, quote_amount - swap.amount_out, 10), 'Quote withdraw');
    assert(wd.base_fees == swap.fees, 'Base fees withdraw');
    assert(wd.quote_fees == 0, 'Quote fees withdraw');
}
