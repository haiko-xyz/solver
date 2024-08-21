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
    let (
        _base_token, _quote_token, oracle, _vault_token_class, solver, market_id, _vault_token_opt
    ) =
        before(
        true
    );

    // Set params.
    start_warp(CheatTarget::One(solver.contract_address), 1000);
    let repl_solver = IReplicatingSolverDispatcher { contract_address: solver.contract_address };
    let market_params = MarketParams {
        min_spread: 25,
        range: 5000,
        max_delta: 500,
        max_skew: 6000,
        base_currency_id: 1398035019,
        quote_currency_id: 4543560,
        min_sources: 2,
        max_age: 1000
    };
    repl_solver.queue_market_params(market_id, market_params);
    repl_solver.set_market_params(market_id);

    // Set oracle price.
    start_warp(CheatTarget::One(oracle.contract_address), 1000);
    oracle.set_data_with_USD_hop('STRK', 'ETH', 13717, 8, 999, 5);

    // Deposit initial.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let (base_deposit_init, quote_deposit_init, shares_init) = solver
        .deposit_initial(market_id, 80000000000000000000000, 11428658419735305956);

    // Swap.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let params = SwapParams {
        is_buy: false,
        amount: to_e18(1000),
        exact_input: true,
        threshold_sqrt_price: Option::None(()),
        threshold_amount: Option::None(()),
        deadline: Option::None(()),
    };
    let (amount_in, amount_out) = solver.swap(market_id, params);
    println!("amount_in: {}, amount_out: {}", amount_in, amount_out);
}
