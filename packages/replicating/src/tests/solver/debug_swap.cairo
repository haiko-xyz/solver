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
        helpers::{
            actions::{deploy_replicating_solver, deploy_mock_pragma_oracle},
            utils::{before, before_custom_decimals},
        },
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

#[test]
fn test_debug_swap() {
    // Hard code params.
    let is_buy = false;
    let exact_input = false;
    let amount = 10000000000;
    let fee_rate = 25;
    let range = 5000;
    let max_delta = 500;
    let max_skew = 6000;
    let base_currency_id = 1398035019;
    let quote_currency_id = 1431520323;
    let min_sources = 2;
    let max_age = 1000;
    let oracle_price = 37067545;
    let oracle_decimals = 8;
    let base_reserves = 268762195878807302077639;
    let quote_reserves = 96834519855;
    let base_decimals = 18;
    let quote_decimals = 6;

    let (
        _base_token, _quote_token, oracle, _vault_token_class, solver, market_id, _vault_token_opt
    ) =
        before_custom_decimals(
        true, base_decimals, quote_decimals
    );

    // Set params.
    start_warp(CheatTarget::One(solver.contract_address), 1000);
    let repl_solver = IReplicatingSolverDispatcher { contract_address: solver.contract_address };
    let market_params = MarketParams {
        fee_rate,
        range,
        max_delta,
        max_skew,
        base_currency_id,
        quote_currency_id,
        min_sources,
        max_age
    };
    repl_solver.queue_market_params(market_id, market_params);
    repl_solver.set_market_params(market_id);

    // Set oracle price.
    start_warp(CheatTarget::One(oracle.contract_address), 1000);
    oracle
        .set_data_with_USD_hop(
            base_currency_id, quote_currency_id, oracle_price, oracle_decimals, 999, 5
        );

    // Deposit initial.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    solver.deposit_initial(market_id, base_reserves, quote_reserves);

    // Swap.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let params = SwapParams {
        is_buy,
        amount,
        exact_input,
        threshold_sqrt_price: Option::None(()),
        threshold_amount: Option::None(()),
        deadline: Option::None(()),
    };
    let (amount_in, amount_out) = solver.swap(market_id, params);
    println!("amount_in: {}, amount_out: {}", amount_in, amount_out);
}
