// Core lib imports.
use starknet::ContractAddress;
use starknet::contract_address_const;
use starknet::class_hash::ClassHash;

// Local imports.
use haiko_solver_core::{
    interfaces::ISolver::{ISolverDispatcher, ISolverDispatcherTrait}, types::SwapParams,
};
use haiko_solver_reversion::{
    contracts::mocks::{
        upgraded_reversion_solver::{
            UpgradedReversionSolver, IUpgradedReversionSolverDispatcher,
            IUpgradedReversionSolverDispatcherTrait
        },
        mock_pragma_oracle::{IMockPragmaOracleDispatcher, IMockPragmaOracleDispatcherTrait},
    },
    interfaces::{
        IReversionSolver::{IReversionSolverDispatcher, IReversionSolverDispatcherTrait},
        pragma::{DataType, PragmaPricesResponse},
    },
    types::{MarketParams, Trend},
    tests::{
        helpers::{actions::{deploy_reversion_solver, deploy_mock_pragma_oracle}, utils::before,},
    },
};

// Haiko imports.
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

    // Set trend.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let rev_solver = IReversionSolverDispatcher { contract_address: solver.contract_address };
    let model_params = rev_solver.model_params(market_id);
    rev_solver.set_model_params(market_id, Trend::Down, model_params.range);

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

    // Set trend.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let rev_solver = IReversionSolverDispatcher { contract_address: solver.contract_address };
    let model_params = rev_solver.model_params(market_id);
    rev_solver.set_model_params(market_id, Trend::Down, model_params.range);

    // Set withdraw fee.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    solver.set_withdraw_fee(market_id, 50);

    // Deposit initial.
    let dep_init = solver.deposit_initial(market_id, to_e18(100), to_e18(1000));

    // Deposit as LP.
    start_prank(CheatTarget::One(solver.contract_address), alice());
    let dep = solver.deposit(market_id, to_e18(50), to_e18(600)); // Contains extra, should coerce.
    println!(
        "base_deposit: {}, quote_deposit: {}, shares: {}",
        dep.base_amount,
        dep.quote_amount,
        dep.shares
    );

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
    println!("amount_in: {}, amount_out: {}", swap.amount_in, swap.amount_out);

    // Withdraw.
    start_prank(CheatTarget::One(solver.contract_address), alice());
    let wd = solver.withdraw_public(market_id, dep.shares);
    println!("base_withdraw: {}, quote_withdraw: {}", wd.base_amount, wd.quote_amount);

    // Collect withdraw fees.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let base_fees = solver
        .collect_withdraw_fees(solver.contract_address, base_token.contract_address);
    let quote_fees = solver
        .collect_withdraw_fees(solver.contract_address, quote_token.contract_address);
    println!("base_fees: {}, quote_fees: {}", base_fees, quote_fees);

    // Run checks.
    let res = solver.get_balances(market_id);
    println!("base_reserves: {}, quote_reserves: {}", res.base_amount, res.quote_amount);
    let base_deposit_exp = to_e18(50);
    let quote_deposit_exp = to_e18(500);
    println!(
        "base_reserves_exp: {}, quote_reserves_exp: {}",
        dep_init.base_amount + base_deposit_exp - swap.amount_out - wd.base_amount - base_fees,
        dep_init.quote_amount
            + quote_deposit_exp
            + swap.amount_in
            - swap.fees
            - wd.quote_amount
            - quote_fees
    );
    assert(dep.base_amount == base_deposit_exp, 'Base deposit');
    assert(dep.quote_amount == quote_deposit_exp, 'Quote deposit');
    assert(dep.shares == dep_init.shares / 2, 'Shares');
    assert(
        res.base_amount == dep_init.base_amount
            + base_deposit_exp
            - swap.amount_out
            - wd.base_amount
            - base_fees,
        'Base reserves'
    );
    assert(
        res.quote_amount == dep_init.quote_amount
            + quote_deposit_exp
            + swap.amount_in
            - swap.fees
            - wd.quote_amount
            - quote_fees,
        'Quote reserves'
    );
}
