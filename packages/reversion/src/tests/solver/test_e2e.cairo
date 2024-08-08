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
    let repl_solver = IReversionSolverDispatcher { contract_address: solver.contract_address };
    repl_solver.set_trend(market_id, Trend::Up);

    // Deposit initial.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let (base_deposit_init, quote_deposit_init, shares_init) = solver
        .deposit_initial(market_id, to_e18(100), to_e18(1000));

    // Deposit.
    let (base_deposit, quote_deposit, shares) = solver.deposit(market_id, to_e18(100), to_e18(500));

    // Swap.
    let params = SwapParams {
        is_buy: true,
        amount: to_e18(10),
        exact_input: true,
        threshold_sqrt_price: Option::None(()),
        threshold_amount: Option::None(()),
    };
    let (amount_in, amount_out) = solver.swap(market_id, params);

    // Withdraw.
    let (base_withdraw, quote_withdraw) = solver
        .withdraw_private(market_id, to_e18(50), to_e18(300));

    // Run checks.
    let (base_reserves, quote_reserves) = solver.get_balances(market_id);
    assert(
        base_reserves == base_deposit + base_deposit_init - amount_out - base_withdraw,
        'Base reserves'
    );
    assert(
        quote_reserves == quote_deposit + quote_deposit_init + amount_in - quote_withdraw,
        'Quote reserves'
    );
    assert(shares_init == 0, 'Shares init');
    assert(shares == 0, 'Shares');
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
    let repl_solver = IReversionSolverDispatcher { contract_address: solver.contract_address };
    repl_solver.set_trend(market_id, Trend::Up);

    // Set withdraw fee.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    solver.set_withdraw_fee(market_id, 50);

    // Deposit initial.
    let (base_deposit_init, quote_deposit_init, shares_init) = solver
        .deposit_initial(market_id, to_e18(100), to_e18(1000));

    // Deposit as LP.
    start_prank(CheatTarget::One(solver.contract_address), alice());
    let (base_deposit, quote_deposit, shares) = solver
        .deposit(market_id, to_e18(50), to_e18(600)); // Contains extra, should coerce.
    println!(
        "base_deposit: {}, quote_deposit: {}, shares: {}", base_deposit, quote_deposit, shares
    );

    // Swap.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let params = SwapParams {
        is_buy: true,
        amount: to_e18(10),
        exact_input: true,
        threshold_sqrt_price: Option::None(()),
        threshold_amount: Option::None(()),
    };
    let (amount_in, amount_out) = solver.swap(market_id, params);
    println!("amount_in: {}, amount_out: {}", amount_in, amount_out);

    // Withdraw.
    start_prank(CheatTarget::One(solver.contract_address), alice());
    let (base_withdraw, quote_withdraw) = solver.withdraw_public(market_id, shares);
    println!("base_withdraw: {}, quote_withdraw: {}", base_withdraw, quote_withdraw);

    // Collect withdraw fees.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let base_fees = solver
        .collect_withdraw_fees(solver.contract_address, base_token.contract_address);
    let quote_fees = solver
        .collect_withdraw_fees(solver.contract_address, quote_token.contract_address);
    println!("base_fees: {}, quote_fees: {}", base_fees, quote_fees);

    // Run checks.
    let (base_reserves, quote_reserves) = solver.get_balances(market_id);
    println!("base_reserves: {}, quote_reserves: {}", base_reserves, quote_reserves);
    let base_deposit_exp = to_e18(50);
    let quote_deposit_exp = to_e18(500);
    println!(
        "base_reserves_exp: {}, quote_reserves_exp: {}",
        base_deposit_init + base_deposit_exp - amount_out - base_withdraw - base_fees,
        quote_deposit_init + quote_deposit_exp + amount_in - quote_withdraw - quote_fees
    );
    assert(base_deposit == base_deposit_exp, 'Base deposit');
    assert(quote_deposit == quote_deposit_exp, 'Quote deposit');
    assert(shares == shares_init / 2, 'Shares');
    assert(
        base_reserves == base_deposit_init
            + base_deposit_exp
            - amount_out
            - base_withdraw
            - base_fees,
        'Base reserves'
    );
    assert(
        quote_reserves == quote_deposit_init
            + quote_deposit_exp
            + amount_in
            - quote_withdraw
            - quote_fees,
        'Quote reserves'
    );
}
