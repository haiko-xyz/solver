// Core lib imports.
use starknet::contract_address_const;

// Local imports.
use haiko_solver_core::{
    contracts::solver::SolverComponent,
    interfaces::ISolver::{ISolverDispatcher, ISolverDispatcherTrait},
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
    let (_, _, shares) = solver.deposit(market_id, base_amount, quote_amount);

    // Snapshot before.
    let vault_token = vault_token_opt.unwrap();
    let bef = snapshot(solver, market_id, base_token, quote_token, vault_token, alice());

    // Withdraw.
    start_prank(CheatTarget::One(solver.contract_address), alice());
    let (base_withdraw, quote_withdraw) = solver.withdraw_at_ratio(market_id, shares / 2);

    // Snapshot after.
    let aft = snapshot(solver, market_id, base_token, quote_token, vault_token, alice());

    // Run checks.
    assert(approx_eq(base_withdraw, base_amount / 2, 10), 'Base deposit');
    assert(approx_eq(quote_withdraw, quote_amount / 2, 10), 'Quote deposit');
    assert(aft.lp_base_bal == bef.lp_base_bal + base_withdraw, 'LP base bal');
    assert(aft.lp_quote_bal == bef.lp_quote_bal + quote_withdraw, 'LP quote bal');
    assert(aft.vault_lp_bal == bef.vault_lp_bal - shares / 2, 'LP shares');
    assert(aft.vault_total_bal == bef.vault_total_bal - shares / 2, 'LP total shares');
    assert(
        aft.market_state.base_reserves == bef.market_state.base_reserves - base_withdraw,
        'Base reserve'
    );
    assert(
        aft.market_state.quote_reserves == bef.market_state.quote_reserves - quote_withdraw,
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
    let (_, _, shares_init) = solver.deposit_initial(market_id, base_amount, quote_amount);

    // Deposit.
    start_prank(CheatTarget::One(solver.contract_address), alice());
    let (_, _, shares) = solver.deposit(market_id, base_amount, quote_amount);

    // Withdraw owner.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    solver.withdraw_at_ratio(market_id, shares_init);

    // Snapshot before.
    let vault_token = vault_token_opt.unwrap();
    let bef = snapshot(solver, market_id, base_token, quote_token, vault_token, alice());

    // Withdraw LP.
    start_prank(CheatTarget::One(solver.contract_address), alice());
    let (base_withdraw, quote_withdraw) = solver.withdraw_at_ratio(market_id, shares);

    // Snapshot after.
    let aft = snapshot(solver, market_id, base_token, quote_token, vault_token, alice());

    // Run checks.
    assert(approx_eq(base_withdraw, base_amount, 10), 'Base deposit');
    assert(approx_eq(quote_withdraw, quote_amount, 10), 'Quote deposit');
    assert(aft.lp_base_bal == bef.lp_base_bal + base_withdraw, 'LP base bal');
    assert(aft.lp_quote_bal == bef.lp_quote_bal + quote_withdraw, 'LP quote bal');
    assert(aft.vault_lp_bal == bef.vault_lp_bal - shares, 'LP shares');
    assert(aft.vault_total_bal == bef.vault_total_bal - shares, 'LP total shares');
    assert(
        aft.market_state.base_reserves == bef.market_state.base_reserves - base_withdraw,
        'Base reserve'
    );
    assert(
        aft.market_state.quote_reserves == bef.market_state.quote_reserves - quote_withdraw,
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
    let (_, _, shares) = solver.deposit(market_id, base_amount, quote_amount);

    // Pause.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    solver.pause(market_id);

    // Withdraw.
    start_prank(CheatTarget::One(solver.contract_address), alice());
    solver.withdraw_at_ratio(market_id, shares);
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
    repl_solver.set_market_params(market_id, market_params);

    // Deposit initial.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let base_amount = to_e18(100);
    let quote_amount = to_e18(500);
    solver.deposit_initial(market_id, base_amount, quote_amount);

    // Snapshot before.
    let vault_token = contract_address_const::<0x0>();
    let bef = snapshot(solver, market_id, _base_token, _quote_token, vault_token, owner());

    // Withdraw.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let (base_withdraw, quote_withdraw) = solver.withdraw(market_id, base_amount, 0);

    // Snapshot after.
    let aft = snapshot(solver, market_id, _base_token, _quote_token, vault_token, owner());

    // Run checks.
    assert(approx_eq(base_withdraw, base_amount, 10), 'Base withdraw');
    assert(quote_withdraw == 0, 'Quote withdraw');
    assert(aft.lp_base_bal == bef.lp_base_bal + base_withdraw, 'LP base bal');
    assert(aft.lp_quote_bal == bef.lp_quote_bal + quote_withdraw, 'LP quote bal');
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
    repl_solver.set_market_params(market_id, market_params);

    // Deposit initial.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let base_amount = to_e18(100);
    let quote_amount = to_e18(500);
    solver.deposit_initial(market_id, base_amount, quote_amount);

    // Snapshot before.
    let vault_token = contract_address_const::<0x0>();
    let bef = snapshot(solver, market_id, _base_token, _quote_token, vault_token, owner());

    // Withdraw.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let (base_withdraw, quote_withdraw) = solver.withdraw(market_id, 0, quote_amount);

    // Snapshot after.
    let aft = snapshot(solver, market_id, _base_token, _quote_token, vault_token, owner());

    // Run checks.
    assert(base_withdraw == 0, 'Base withdraw');
    assert(approx_eq(quote_withdraw, quote_amount, 10), 'Quote withdraw');
    assert(aft.lp_base_bal == bef.lp_base_bal + base_withdraw, 'LP base bal');
    assert(aft.lp_quote_bal == bef.lp_quote_bal + quote_withdraw, 'LP quote bal');
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

    // Snapshot before.
    let vault_token = contract_address_const::<0x0>();
    let bef = snapshot(solver, market_id, _base_token, _quote_token, vault_token, owner());

    // Withdraw.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let (base_withdraw, quote_withdraw) = solver
        .withdraw(market_id, base_amount / 2, quote_amount / 2);

    // Snapshot after.
    let aft = snapshot(solver, market_id, _base_token, _quote_token, vault_token, owner());

    // Run checks.
    assert(approx_eq(base_withdraw, base_amount / 2, 10), 'Base withdraw');
    assert(approx_eq(quote_withdraw, quote_amount / 2, 10), 'Quote withdraw');
    assert(aft.lp_base_bal == bef.lp_base_bal + base_withdraw, 'LP base bal');
    assert(aft.lp_quote_bal == bef.lp_quote_bal + quote_withdraw, 'LP quote bal');
    assert(aft.vault_lp_bal == bef.vault_lp_bal, 'LP shares');
    assert(aft.vault_total_bal == bef.vault_total_bal, 'LP total shares');
    assert(
        aft.market_state.base_reserves == bef.market_state.base_reserves - base_withdraw,
        'Base reserve'
    );
    assert(
        aft.market_state.quote_reserves == bef.market_state.quote_reserves - quote_withdraw,
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

    // Snapshot before.
    let vault_token = contract_address_const::<0x0>();
    let bef = snapshot(solver, market_id, _base_token, _quote_token, vault_token, owner());

    // Withdraw.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let (base_withdraw, quote_withdraw) = solver.withdraw(market_id, base_amount, quote_amount);

    // Snapshot after.
    let aft = snapshot(solver, market_id, _base_token, _quote_token, vault_token, owner());

    // Run checks.
    assert(approx_eq(base_withdraw, base_amount, 10), 'Base withdraw');
    assert(approx_eq(quote_withdraw, quote_amount, 10), 'Quote withdraw');
    assert(aft.lp_base_bal == bef.lp_base_bal + base_withdraw, 'LP base bal');
    assert(aft.lp_quote_bal == bef.lp_quote_bal + quote_withdraw, 'LP quote bal');
    assert(aft.vault_lp_bal == 0, 'LP shares');
    assert(aft.vault_total_bal == 0, 'LP total shares');
    assert(
        aft.market_state.base_reserves == bef.market_state.base_reserves - base_withdraw,
        'Base reserve'
    );
    assert(
        aft.market_state.quote_reserves == bef.market_state.quote_reserves - quote_withdraw,
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

    // Withdraw.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let (base_withdraw, quote_withdraw) = solver
        .withdraw(market_id, base_amount * 2, quote_amount * 2);

    // Run checks.
    assert(approx_eq(base_withdraw, base_amount, 10), 'Base withdraw');
    assert(approx_eq(quote_withdraw, quote_amount, 10), 'Quote withdraw');
}

////////////////////////////////
// TESTS - Events
////////////////////////////////

#[test]
fn test_withdraw_public_emits_event() {
    let (
        _base_token, _quote_token, _oracle, _vault_token_class, solver, market_id, _vault_token_opt
    ) =
        before(
        true
    );

    // Disable max skew.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let repl_solver = IReplicatingSolverDispatcher { contract_address: solver.contract_address };
    let mut market_params = default_market_params();
    market_params.max_skew = 0;
    repl_solver.set_market_params(market_id, market_params);

    // Deposit initial.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let base_amount = to_e18(100);
    let quote_amount = 1000_000000;
    let (_, _, shares) = solver.deposit_initial(market_id, base_amount, quote_amount);

    // Spy on events.
    let mut spy = spy_events(SpyOn::One(solver.contract_address));

    // Withdraw.
    let (base_withdraw, quote_withdraw) = solver.withdraw_at_ratio(market_id, shares);

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
                            base_amount: base_withdraw,
                            quote_amount: quote_withdraw,
                            shares
                        }
                    )
                )
            ]
        );
}

#[test]
fn test_withdraw_private_emits_event() {
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
    repl_solver.set_market_params(market_id, market_params);

    // Deposit initial.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let base_amount = to_e18(100);
    let quote_amount = 1000_000000;
    let (_, _, shares) = solver.deposit_initial(market_id, base_amount, quote_amount);

    // Spy on events.
    let mut spy = spy_events(SpyOn::One(solver.contract_address));

    // Withdraw.
    let (base_withdraw, quote_withdraw) = solver.withdraw(market_id, base_amount, quote_amount);

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
                            base_amount: base_withdraw,
                            quote_amount: quote_withdraw,
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
#[should_panic(expected: ('SharesZero',))]
fn test_withdraw_public_zero_shares() {
    let (
        _base_token, _quote_token, _oracle, _vault_token_class, solver, market_id, _vault_token_opt
    ) =
        before(
        true
    );

    // Deposit initial.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    solver.deposit_initial(market_id, to_e18(100), to_e18(500));

    // Withdraw.
    solver.withdraw_at_ratio(market_id, 0);
}

#[test]
#[should_panic(expected: ('InsuffShares',))]
fn test_withdraw_public_more_shares_than_available() {
    let (
        _base_token, _quote_token, _oracle, _vault_token_class, solver, market_id, _vault_token_opt
    ) =
        before(
        true
    );

    // Deposit initial.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let (_, _, shares) = solver.deposit_initial(market_id, to_e18(100), to_e18(500));

    // Withdraw.
    solver.withdraw_at_ratio(market_id, shares + 1);
}

#[test]
#[should_panic(expected: ('MarketNull',))]
fn test_withdraw_public_uninitialised_market() {
    let (
        _base_token, _quote_token, _oracle, _vault_token_class, solver, _market_id, _vault_token_opt
    ) =
        before(
        true
    );

    // Withdraw.
    solver.withdraw_at_ratio(1, 1000);
}

#[test]
#[should_panic(expected: ('UseWithdrawAtRatio',))]
fn test_withdraw_custom_amounts_fail_for_public_vault() {
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

    // Withdraw.
    solver.withdraw(market_id, base_amount, quote_amount);
}


#[test]
#[should_panic(expected: ('AmountZero',))]
fn test_withdraw_private_zero_amounts() {
    let (
        _base_token, _quote_token, _oracle, _vault_token_class, solver, market_id, _vault_token_opt
    ) =
        before(
        false
    );

    // Deposit initial.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    solver.deposit_initial(market_id, to_e18(100), to_e18(500));

    // Withdraw.
    solver.withdraw(market_id, 0, 0);
}

#[test]
#[should_panic(expected: ('MarketNull',))]
fn test_withdraw_private_uninitialised_market() {
    let (
        _base_token, _quote_token, _oracle, _vault_token_class, solver, _market_id, _vault_token_opt
    ) =
        before(
        false
    );

    // Withdraw.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    solver.withdraw_at_ratio(1, 1000);
}
