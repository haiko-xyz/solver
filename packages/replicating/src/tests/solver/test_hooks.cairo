// Local imports.
use haiko_solver_core::{
    interfaces::ISolver::{ISolverHooksDispatcher, ISolverHooksDispatcherTrait},
    types::solver::SwapParams,
};
use haiko_solver_replicating::tests::helpers::utils::before;

// Haiko imports.
use haiko_lib::helpers::{utils::to_e18, params::alice};

// External imports.
use snforge_std::{start_prank, CheatTarget};

#[test]
#[should_panic(expected: ('NotSolver',))]
fn test_after_swap_fails_for_non_solver_caller() {
    let (
        _base_token, _quote_token, _oracle, _vault_token_class, solver, market_id, _vault_token_opt
    ) =
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
    };
    solver_hooks.after_swap(market_id, alice(), params);
}

#[test]
#[should_panic(expected: ('NotSolver',))]
fn test_after_withdraw_fails_for_non_solver_caller() {
    let (
        _base_token, _quote_token, _oracle, _vault_token_class, solver, market_id, _vault_token_opt
    ) =
        before(
        false
    );

    // Call after swap.
    start_prank(CheatTarget::One(solver.contract_address), alice());
    let solver_hooks = ISolverHooksDispatcher { contract_address: solver.contract_address };
    solver_hooks.after_withdraw(market_id, alice(), 100000, 100, 100);
}
