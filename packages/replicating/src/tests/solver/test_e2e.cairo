// Core lib imports.
use starknet::ContractAddress;
use starknet::contract_address_const;
use starknet::class_hash::ClassHash;

// Local imports.
use haiko_solver_core::{
    interfaces::ISolver::{ISolverDispatcher, ISolverDispatcherTrait}, types::SwapParams,
};
use haiko_solver_replicating::{
    contracts::mocks::{
        upgraded_replicating_solver::{
            UpgradedReplicatingSolver, IUpgradedReplicatingSolverDispatcher,
            IUpgradedReplicatingSolverDispatcherTrait
        },
        mock_pragma_oracle::{IMockPragmaOracleDispatcher, IMockPragmaOracleDispatcherTrait},
    },
    interfaces::{
        IReplicatingSolver::{IReplicatingSolverDispatcher, IReplicatingSolverDispatcherTrait},
        pragma::{DataType, PragmaPricesResponse},
    },
    types::MarketParams,
    tests::{
        helpers::{actions::{deploy_replicating_solver, deploy_mock_pragma_oracle}, utils::before,},
    },
};

// Haiko imports.
use haiko_lib::math::math;
use haiko_lib::helpers::{
    params::{owner, alice, bob, treasury, default_token_params},
    actions::{
        market_manager::{create_market, modify_position, swap},
        token::{deploy_token, fund, approve},
    },
    utils::{to_e18, to_e18_u128, to_e28, approx_eq, approx_eq_pct},
};

// External imports.
use openzeppelin::token::erc20::interface::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};
use snforge_std::{
    declare, start_warp, start_prank, stop_prank, CheatTarget, spy_events, SpyOn, EventSpy,
    EventAssertions, EventFetcher, ContractClass, ContractClassTrait
};

////////////////////////////////
// TESTS
////////////////////////////////

#[test]
fn test_solver_e2e_private_market() {
    let (
        _base_token, _quote_token, oracle, _vault_token_class, solver, market_id, _vault_token_opt
    ) =
        before(
        false
    );

    // Set oracle price.
    start_warp(CheatTarget::One(oracle.contract_address), 1000);
    oracle.set_data_with_USD_hop('ETH', 'USDC', 1000000000, 8, 999, 5); // 10

    // Deposit initial.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let dep_init = solver.deposit_initial(market_id, to_e18(100), to_e18(1000));

    // Deposit.
    let dep = solver.deposit(market_id, to_e18(100), to_e18(500));

    // Swap.
    let params = SwapParams {
        is_buy: true,
        amount: to_e18(10),
        exact_input: true,
        threshold_sqrt_price: Option::None(()),
        threshold_amount: Option::None(()),
        deadline: Option::None(()),
    };
    let swap = solver.swap(market_id, params);

    // Withdraw.
    let wd = solver.withdraw_private(market_id, to_e18(50), to_e18(300));

    // Run checks.
    let res = solver.get_balances(market_id);
    assert(
        res.base_amount == dep.base_amount
            + dep_init.base_amount
            - swap.amount_out
            - wd.base_amount,
        'Base reserves'
    );
    assert(
        res.quote_amount == dep.quote_amount
            + dep_init.quote_amount
            + swap.amount_in
            - swap.fees
            - wd.quote_amount,
        'Quote reserves'
    );
    assert(wd.base_fees == 0, 'Base fees');
    assert(
        approx_eq(wd.quote_fees, swap.fees * to_e18(300) / (to_e18(1500) + swap.amount_in), 1),
        'Quote fees'
    );
    assert(dep_init.shares == 0, 'Shares init');
    assert(dep.shares == 0, 'Shares');
}

#[test]
fn test_solver_e2e_public_market() {
    let (base_token, quote_token, oracle, _vault_token_class, solver, market_id, _vault_token_opt) =
        before(
        true
    );

    // Set oracle price.
    start_warp(CheatTarget::One(oracle.contract_address), 1000);
    oracle.set_data_with_USD_hop('ETH', 'USDC', 1000000000, 8, 999, 5); // 10

    // Set withdraw fee.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    solver.set_withdraw_fee(market_id, 50);

    // Deposit initial.
    let dep_init = solver.deposit_initial(market_id, to_e18(100), to_e18(1000));

    // Deposit as LP.
    start_prank(CheatTarget::One(solver.contract_address), alice());
    let dep = solver.deposit(market_id, to_e18(50), to_e18(600)); // Contains extra, should coerce.

    // Swap.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let params = SwapParams {
        is_buy: true,
        amount: to_e18(10),
        exact_input: true,
        threshold_sqrt_price: Option::None(()),
        threshold_amount: Option::None(()),
        deadline: Option::None(()),
    };
    let swap = solver.swap(market_id, params);

    // Withdraw.
    start_prank(CheatTarget::One(solver.contract_address), alice());
    let wd = solver.withdraw_public(market_id, dep.shares);

    // Collect withdraw fees.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let base_withdraw_fees = solver
        .collect_withdraw_fees(solver.contract_address, base_token.contract_address);
    let quote_withdraw_fees = solver
        .collect_withdraw_fees(solver.contract_address, quote_token.contract_address);

    // Run checks.
    let res = solver.get_balances(market_id);
    let base_deposit_exp = to_e18(50);
    let quote_deposit_exp = to_e18(500);
    assert(dep.base_amount == base_deposit_exp, 'Base deposit');
    assert(dep.quote_amount == quote_deposit_exp, 'Quote deposit');
    assert(
        approx_eq(
            wd.base_amount,
            math::mul_div(base_deposit_exp - swap.amount_out / 3, 995, 1000, false),
            10
        ),
        'Base withdraw'
    );
    assert(
        approx_eq(
            wd.quote_amount,
            math::mul_div(quote_deposit_exp + swap.amount_in / 3, 995, 1000, false),
            10
        ),
        'Quote withdraw'
    );
    assert(wd.base_fees == 0, 'Base fees');
    assert(
        approx_eq(wd.quote_fees, math::mul_div(swap.fees / 3, 995, 1000, false), 10), 'Quote fees'
    );
    assert(dep.shares == dep_init.shares / 2, 'Shares');
    assert(
        approx_eq(
            res.base_amount, (dep_init.base_amount + base_deposit_exp - swap.amount_out) * 2 / 3, 10
        ),
        'Base reserves'
    );
    assert(
        approx_eq(
            res.quote_amount,
            (dep_init.quote_amount + quote_deposit_exp + swap.amount_in - swap.fees) * 2 / 3,
            10
        ),
        'Quote reserves'
    );
    assert(
        approx_eq(
            base_withdraw_fees,
            math::mul_div(base_deposit_exp - swap.amount_out / 3, 5, 1000, false),
            10
        ),
        'Base withdraw fees'
    );
    assert(
        approx_eq(
            quote_withdraw_fees,
            math::mul_div(quote_deposit_exp + swap.amount_in / 3, 5, 1000, false),
            10
        ),
        'Quote withdraw fees'
    );
}
