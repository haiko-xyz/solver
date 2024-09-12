// Core lib imports.
use starknet::contract_address_const;

// Local imports.
use haiko_solver_core::{
    interfaces::{
        ISolver::{ISolverDispatcher, ISolverDispatcherTrait},
        IVaultToken::{IVaultTokenDispatcher, IVaultTokenDispatcherTrait},
    },
    tests::helpers::utils::before, types::SwapParams
};

// Haiko imports.
use haiko_lib::math::math;
use haiko_lib::helpers::params::{owner, alice, bob};
use haiko_lib::helpers::utils::{to_e18, approx_eq};

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
    let (_base_token, _quote_token, _vault_token_class, solver, market_id, _vault_token_opt) =
        before(
        true
    );

    // Deposit initial.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let base_owner = to_e18(100);
    let quote_owner = to_e18(500);
    solver.deposit_initial(market_id, base_owner, quote_owner);

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
    let swap = solver.swap(market_id, params);

    // Get balances.
    let bal = solver.get_balances(market_id);
    assert(bal.base_amount == base_owner - swap.amount_out, 'Base amount');
    assert(bal.quote_amount == quote_owner + swap.amount_in - swap.fees, 'Quote amount');
    assert(bal.base_fees == 0, 'Base fees');
    assert(bal.quote_fees == swap.fees, 'Quote fees');
}

#[test]
fn test_get_user_balances() {
    let (_base_token, _quote_token, _vault_token_class, solver, market_id, _vault_token_opt) =
        before(
        true
    );

    // Deposit initial.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let base_deposit_owner = to_e18(100);
    let quote_deposit_owner = to_e18(500);
    solver.deposit_initial(market_id, base_deposit_owner, quote_deposit_owner);

    // Deposit.
    start_prank(CheatTarget::One(solver.contract_address), alice());
    let base_deposit_alice = to_e18(50);
    let quote_deposit_alice = to_e18(250);
    solver.deposit(market_id, base_deposit_alice, quote_deposit_alice);

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
    let swap = solver.swap(market_id, params);

    // Get balances.
    let bal_owner = solver.get_user_balances(owner(), market_id);
    let bal_alice = solver.get_user_balances(alice(), market_id);

    // Run checks.
    assert(swap.amount_in == params.amount, 'Amount in');
    assert(swap.fees == math::mul_div(params.amount, 50, 10000, true), 'Fees');
    assert(
        approx_eq(bal_owner.base_amount, base_deposit_owner - swap.amount_out * 2 / 3, 1),
        'Base owner'
    );
    assert(
        approx_eq(
            bal_owner.quote_amount, quote_deposit_owner + (swap.amount_in - swap.fees) * 2 / 3, 1
        ),
        'Quote owner'
    );
    assert(bal_owner.base_fees == 0, 'Base fees owner');
    assert(approx_eq(bal_owner.quote_fees, swap.fees * 2 / 3, 1), 'Quote fees owner');
    assert(
        approx_eq(bal_alice.base_amount, base_deposit_alice - swap.amount_out / 3, 1), 'Base alice'
    );
    assert(
        approx_eq(
            bal_alice.quote_amount, quote_deposit_alice + (swap.amount_in - swap.fees) / 3, 1
        ),
        'Quote alice'
    );
    assert(bal_alice.base_fees == 0, 'Base fees alice');
    assert(approx_eq(bal_alice.quote_fees, swap.fees / 3, 1), 'Quote fees alice');
}
