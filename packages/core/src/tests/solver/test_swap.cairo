// Core lib imports.
use starknet::contract_address_const;

// Local imports.
use haiko_solver_core::{
    contracts::solver::SolverComponent,
    contracts::mocks::mock_solver::{IMockSolverDispatcher, IMockSolverDispatcherTrait},
    interfaces::ISolver::{
        ISolverDispatcher, ISolverDispatcherTrait, ISolverHooksDispatcher,
        ISolverHooksDispatcherTrait
    },
    types::SwapParams,
    tests::helpers::{actions::deploy_mock_solver, utils::{before, before_skip_approve, snapshot},},
};

// Haiko imports.
use haiko_lib::helpers::params::{owner, alice};
use haiko_lib::helpers::utils::{to_e18, to_e28, approx_eq, approx_eq_pct};
use haiko_lib::helpers::actions::token::{fund, approve};

// External imports.
use snforge_std::{
    start_prank, start_warp, declare, spy_events, SpyOn, EventSpy, EventAssertions, CheatTarget
};
use openzeppelin::token::erc20::interface::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};

///////////////////////////////
/// TESTS - Success cases
///////////////////////////////

#[test]
fn test_swap_buy_exact_in() {
    let (_base_token, _quote_token, _vault_token_class, solver, market_id, _vault_token_opt) =
        before(
        false
    );

    // Set price.
    start_warp(CheatTarget::One(solver.contract_address), 1000);
    let mock_solver = IMockSolverDispatcher { contract_address: solver.contract_address };
    mock_solver.set_price(market_id, to_e28(5));

    // Deposit initial.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    solver.deposit_initial(market_id, to_e18(5), to_e18(25));

    // Swap buy.
    start_prank(CheatTarget::One(solver.contract_address), alice());
    let params = SwapParams {
        is_buy: true,
        amount: to_e18(5),
        exact_input: true,
        threshold_sqrt_price: Option::None(()),
        threshold_amount: Option::None(()),
        deadline: Option::None(()),
    };
    let (amount_in, amount_out) = solver.swap(market_id, params);

    // Run checks.
    assert(amount_in == params.amount, 'Amount in');
    assert(amount_out == to_e18(1), 'Amount out');
}

#[test]
fn test_swap_sell_exact_in() {
    let (_base_token, _quote_token, _vault_token_class, solver, market_id, _vault_token_opt) =
        before(
        false
    );

    // Set price.
    start_warp(CheatTarget::One(solver.contract_address), 1000);
    let mock_solver = IMockSolverDispatcher { contract_address: solver.contract_address };
    mock_solver.set_price(market_id, to_e28(5));

    // Deposit initial.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    solver.deposit_initial(market_id, to_e18(5), to_e18(25));

    // Swap buy.
    start_prank(CheatTarget::One(solver.contract_address), alice());
    let params = SwapParams {
        is_buy: false,
        amount: to_e18(1),
        exact_input: true,
        threshold_sqrt_price: Option::None(()),
        threshold_amount: Option::None(()),
        deadline: Option::None(()),
    };
    let (amount_in, amount_out) = solver.swap(market_id, params);

    // Run checks.
    assert(amount_in == params.amount, 'Amount in');
    assert(amount_out == to_e18(5), 'Amount out');
}

#[test]
fn test_swap_buy_exact_out() {
    let (_base_token, _quote_token, _vault_token_class, solver, market_id, _vault_token_opt) =
        before(
        false
    );

    // Set price.
    start_warp(CheatTarget::One(solver.contract_address), 1000);
    let mock_solver = IMockSolverDispatcher { contract_address: solver.contract_address };
    mock_solver.set_price(market_id, to_e28(5));

    // Deposit initial.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    solver.deposit_initial(market_id, to_e18(5), to_e18(25));

    // Swap buy.
    start_prank(CheatTarget::One(solver.contract_address), alice());
    let params = SwapParams {
        is_buy: true,
        amount: to_e18(1),
        exact_input: false,
        threshold_sqrt_price: Option::None(()),
        threshold_amount: Option::None(()),
        deadline: Option::None(()),
    };
    let (amount_in, amount_out) = solver.swap(market_id, params);

    // Run checks.
    assert(amount_in == to_e18(5), 'Amount in');
    assert(amount_out == params.amount, 'Amount out');
}

#[test]
fn test_swap_sell_exact_out() {
    let (_base_token, _quote_token, _vault_token_class, solver, market_id, _vault_token_opt) =
        before(
        false
    );

    // Set price.
    start_warp(CheatTarget::One(solver.contract_address), 1000);
    let mock_solver = IMockSolverDispatcher { contract_address: solver.contract_address };
    mock_solver.set_price(market_id, to_e28(5));

    // Deposit initial.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    solver.deposit_initial(market_id, to_e18(5), to_e18(25));

    // Swap buy.
    start_prank(CheatTarget::One(solver.contract_address), alice());
    let params = SwapParams {
        is_buy: false,
        amount: to_e18(5),
        exact_input: false,
        threshold_sqrt_price: Option::None(()),
        threshold_amount: Option::None(()),
        deadline: Option::None(()),
    };
    let (amount_in, amount_out) = solver.swap(market_id, params);

    // Run checks.
    assert(amount_in == to_e18(1), 'Amount in');
    assert(amount_out == params.amount, 'Amount out');
}

////////////////////////////////
// TESTS - Events
////////////////////////////////

#[test]
fn test_swap_should_emit_event() {
    let (_base_token, _quote_token, _vault_token_class, solver, market_id, _vault_token_opt) =
        before(
        false
    );

    // Deposit initial.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    solver.deposit_initial(market_id, to_e18(100), to_e18(1000));

    // Spy on events.
    let mut spy = spy_events(SpyOn::One(solver.contract_address));

    // Swap.
    start_prank(CheatTarget::One(solver.contract_address), alice());
    let params = SwapParams {
        is_buy: true,
        amount: to_e18(10),
        exact_input: true,
        threshold_sqrt_price: Option::None(()),
        threshold_amount: Option::None(()),
        deadline: Option::None(()),
    };
    let (amount_in, amount_out) = solver.swap(market_id, params);

    // Check events emitted.
    spy
        .assert_emitted(
            @array![
                (
                    solver.contract_address,
                    SolverComponent::Event::Swap(
                        SolverComponent::Swap {
                            market_id,
                            caller: alice(),
                            amount_in,
                            amount_out,
                            is_buy: params.is_buy,
                            exact_input: params.exact_input
                        }
                    )
                )
            ]
        );
}

////////////////////////////////
// TESTS - Fail cases
////////////////////////////////

#[test]
#[should_panic(expected: ('MarketNull',))]
fn test_swap_fails_if_market_uninitialised() {
    let (_base_token, _quote_token, _vault_token_class, solver, _market_id, _vault_token_opt) =
        before(
        false
    );

    // Swap.
    start_prank(CheatTarget::One(solver.contract_address), alice());
    let params = SwapParams {
        is_buy: true,
        amount: to_e18(10),
        exact_input: true,
        threshold_sqrt_price: Option::None(()),
        threshold_amount: Option::None(()),
        deadline: Option::None(()),
    };
    solver.swap(1, params);
}

#[test]
#[should_panic(expected: ('Paused',))]
fn test_swap_fails_if_market_paused() {
    let (_base_token, _quote_token, _vault_token_class, solver, market_id, _vault_token_opt) =
        before(
        false
    );

    // Deposit initial.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    solver.deposit_initial(market_id, to_e18(100), to_e18(1000));

    // Pause.
    solver.pause(market_id);

    // Swap.
    start_prank(CheatTarget::One(solver.contract_address), alice());
    let params = SwapParams {
        is_buy: true,
        amount: to_e18(10),
        exact_input: true,
        threshold_sqrt_price: Option::None(()),
        threshold_amount: Option::None(()),
        deadline: Option::None(()),
    };
    solver.swap(market_id, params);
}

#[test]
#[should_panic(expected: ('BaseAllowance',))]
fn test_swap_fails_if_not_approved() {
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

    // Swap without approval.
    start_prank(CheatTarget::One(solver.contract_address), alice());
    let params = SwapParams {
        is_buy: true,
        amount: to_e18(10),
        exact_input: true,
        threshold_sqrt_price: Option::None(()),
        threshold_amount: Option::None(()),
        deadline: Option::None(()),
    };
    solver.swap(market_id, params);
}

#[test]
#[should_panic(expected: ('AmountZero',))]
fn test_swap_fails_if_amount_zero() {
    let (_base_token, _quote_token, _vault_token_class, solver, market_id, _vault_token_opt) =
        before(
        false
    );

    // Deposit initial.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    solver.deposit_initial(market_id, to_e18(100), to_e18(1000));

    // Swap.
    start_prank(CheatTarget::One(solver.contract_address), alice());
    let params = SwapParams {
        is_buy: true,
        amount: 0,
        exact_input: true,
        threshold_sqrt_price: Option::None(()),
        threshold_amount: Option::None(()),
        deadline: Option::None(()),
    };
    solver.swap(market_id, params);
}

#[test]
#[should_panic(expected: ('ThresholdAmountZero',))]
fn test_swap_fails_if_min_amount_out_zero() {
    let (_base_token, _quote_token, _vault_token_class, solver, market_id, _vault_token_opt) =
        before(
        false
    );

    // Deposit initial.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    solver.deposit_initial(market_id, to_e18(100), to_e18(1000));

    // Swap.
    start_prank(CheatTarget::One(solver.contract_address), alice());
    let params = SwapParams {
        is_buy: true,
        amount: to_e18(10),
        exact_input: true,
        threshold_sqrt_price: Option::None(()),
        threshold_amount: Option::Some(0),
        deadline: Option::None(()),
    };
    solver.swap(market_id, params);
}

#[test]
#[should_panic(expected: ('AmountZero',))]
fn test_swap_fails_if_swap_buy_with_zero_liquidity() {
    let (_base_token, _quote_token, _vault_token_class, solver, market_id, _vault_token_opt) =
        before(
        false
    );

    // Deposit initial.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    solver.deposit_initial(market_id, 0, to_e18(1000));

    // Swap.
    start_prank(CheatTarget::One(solver.contract_address), alice());
    let params = SwapParams {
        is_buy: true,
        amount: to_e18(10),
        exact_input: true,
        threshold_sqrt_price: Option::None(()),
        threshold_amount: Option::None(()),
        deadline: Option::None(()),
    };
    solver.swap(market_id, params);
}

#[test]
#[should_panic(expected: ('AmountZero',))]
fn test_swap_fails_if_swap_sell_with_zero_liquidity() {
    let (_base_token, _quote_token, _vault_token_class, solver, market_id, _vault_token_opt) =
        before(
        false
    );

    // Deposit initial.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    solver.deposit_initial(market_id, to_e18(1000), 0);

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
    solver.swap(market_id, params);
}

#[test]
#[should_panic(expected: ('ThresholdAmount', 10000000000000000000, 0))]
fn test_swap_fails_if_swap_buy_below_threshold_amount() {
    let (_base_token, _quote_token, _vault_token_class, solver, market_id, _vault_token_opt) =
        before(
        false
    );

    // Deposit initial.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    solver.deposit_initial(market_id, to_e18(1000), to_e18(1000));

    // Swap.
    start_prank(CheatTarget::One(solver.contract_address), alice());
    let params = SwapParams {
        is_buy: true,
        amount: to_e18(10),
        exact_input: true,
        threshold_sqrt_price: Option::None(()),
        threshold_amount: Option::Some(to_e18(20)),
        deadline: Option::None(()),
    };
    solver.swap(market_id, params);
}

#[test]
#[should_panic(expected: ('ThresholdAmount', 10000000000000000000, 0))]
fn test_swap_fails_if_swap_sell_below_threshold_amount() {
    let (_base_token, _quote_token, _vault_token_class, solver, market_id, _vault_token_opt) =
        before(
        false
    );

    // Deposit initial.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    solver.deposit_initial(market_id, to_e18(1000), to_e18(1000));

    // Swap.
    start_prank(CheatTarget::One(solver.contract_address), alice());
    let params = SwapParams {
        is_buy: false,
        amount: to_e18(10),
        exact_input: true,
        threshold_sqrt_price: Option::None(()),
        threshold_amount: Option::Some(to_e18(20)),
        deadline: Option::None(()),
    };
    solver.swap(market_id, params);
}

#[test]
#[should_panic(expected: ('Expired',))]
fn test_swap_past_expiry_is_rejected() {
    let (_base_token, _quote_token, _vault_token_class, solver, market_id, _vault_token_opt) =
        before(
        false
    );

    // Deposit initial.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    solver.deposit_initial(market_id, to_e18(100), to_e18(1000));

    // Swap.
    start_warp(CheatTarget::One(solver.contract_address), 1000);
    start_prank(CheatTarget::One(solver.contract_address), alice());
    let params = SwapParams {
        is_buy: true,
        amount: to_e18(10),
        exact_input: true,
        threshold_sqrt_price: Option::None(()),
        threshold_amount: Option::None(()),
        deadline: Option::Some(1),
    };
    solver.swap(market_id, params);
}

#[test]
#[should_panic(expected: ('NotSolver',))]
fn test_after_swap_fails_for_non_solver_caller() {
    let (_base_token, _quote_token, _vault_token_class, solver, market_id, _vault_token_opt) =
        before(
        false
    );

    // Call after swap.
    start_prank(CheatTarget::One(solver.contract_address), alice());
    let solver_hooks = ISolverHooksDispatcher { contract_address: solver.contract_address };
    let params = SwapParams {
        is_buy: true,
        amount: to_e18(10),
        exact_input: true,
        threshold_sqrt_price: Option::None(()),
        threshold_amount: Option::None(()),
        deadline: Option::None(()),
    };
    solver_hooks.after_swap(market_id, params);
}
