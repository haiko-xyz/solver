// Core lib imports.
use starknet::contract_address_const;

// Local imports.
use haiko_solver_core::{
    contracts::solver::SolverComponent,
    interfaces::ISolver::{
        ISolverDispatcher, ISolverDispatcherTrait, ISolverHooksDispatcher,
        ISolverHooksDispatcherTrait
    },
    types::SwapParams,
};
use haiko_solver_reversion::{
    contracts::mocks::mock_pragma_oracle::{
        IMockPragmaOracleDispatcher, IMockPragmaOracleDispatcherTrait
    },
    interfaces::IReversionSolver::{IReversionSolverDispatcher, IReversionSolverDispatcherTrait},
    types::{Trend, MarketParams},
    tests::{
        helpers::{
            actions::{deploy_reversion_solver, deploy_mock_pragma_oracle},
            params::default_market_params,
            utils::{
                before, before_custom_decimals, before_skip_approve, before_with_salt, snapshot,
                declare_classes
            },
        },
    },
};

// Haiko imports.
use haiko_lib::helpers::params::{owner, alice};
use haiko_lib::helpers::utils::{to_e18, to_e28_u128, approx_eq, approx_eq_pct};
use haiko_lib::helpers::actions::token::{fund, approve};

// External imports.
use snforge_std::{
    start_prank, start_warp, declare, spy_events, SpyOn, EventSpy, EventAssertions, CheatTarget
};
use openzeppelin::token::erc20::interface::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};

////////////////////////////////
// HELPERS
////////////////////////////////

#[derive(Drop, Clone)]
struct TestCase {
    pub description: ByteArray,
    // ORACLE
    pub oracle_price: u128, // note this is e8 not e28
    // LIQUIDITY
    pub base_reserves: u256,
    pub quote_reserves: u256,
    pub fee_rate: u16,
    pub range: u32,
    // SWAP
    pub amount: u256,
    pub threshold_sqrt_price: Option<u256>,
    pub threshold_amount: Option<u256>,
    pub exp: Span<SwapCase>,
}

#[derive(Drop, Clone)]
struct SwapCase {
    pub is_buy: bool,
    pub exact_input: bool,
    pub amount_in: u256,
    pub amount_out: u256,
    pub fees: u256,
}

fn get_test_cases_1() -> Span<TestCase> {
    let cases: Array<TestCase> = array![
        TestCase {
            description: "1) Full range liq, price 1, no fees",
            oracle_price: 1_00000000,
            base_reserves: to_e18(1000),
            quote_reserves: to_e18(1000),
            fee_rate: 0,
            range: 7906625,
            amount: to_e18(100),
            threshold_sqrt_price: Option::None(()),
            threshold_amount: Option::None(()),
            exp: array![
                SwapCase {
                    is_buy: true,
                    exact_input: true,
                    amount_in: to_e18(100),
                    amount_out: 90909090909090909146,
                    fees: 0, // TODO: fix amount
                },
                SwapCase {
                    is_buy: false,
                    exact_input: true,
                    amount_in: to_e18(100),
                    amount_out: 90909090909090909146,
                    fees: 0, // TODO: fix amount
                },
                SwapCase {
                    is_buy: true,
                    exact_input: false,
                    amount_in: 111111111111111111027,
                    amount_out: to_e18(100),
                    fees: 0, // TODO: fix amount
                },
                SwapCase {
                    is_buy: false,
                    exact_input: false,
                    amount_in: 111111111111111111027,
                    amount_out: to_e18(100),
                    fees: 0, // TODO: fix amount
                },
            ]
                .span(),
        },
        TestCase {
            description: "2) Full range liq, price 0.1, no fees",
            oracle_price: 0_10000000,
            base_reserves: to_e18(100),
            quote_reserves: to_e18(1000),
            fee_rate: 0,
            range: 7676365,
            amount: to_e18(10),
            threshold_sqrt_price: Option::None(()),
            threshold_amount: Option::None(()),
            exp: array![
                SwapCase {
                    is_buy: true,
                    exact_input: true,
                    amount_in: to_e18(10),
                    amount_out: 50000084852067677296,
                    fees: 0, // TODO: fix amount
                },
                SwapCase {
                    is_buy: false,
                    exact_input: true,
                    amount_in: to_e18(10),
                    amount_out: 998997611702025557,
                    fees: 0, // TODO: fix amount
                },
                SwapCase {
                    is_buy: true,
                    exact_input: false,
                    amount_in: 1111107339914503129,
                    amount_out: to_e18(10),
                    fees: 0, // TODO: fix amount
                },
                SwapCase {
                    is_buy: false,
                    exact_input: false,
                    amount_in: 101010443847319896836,
                    amount_out: to_e18(10),
                    fees: 0, // TODO: fix amount
                },
            ]
                .span(),
        },
        TestCase {
            description: "3) Full range liq, price 10, no fees",
            oracle_price: 10_00000000,
            base_reserves: to_e18(1000),
            quote_reserves: to_e18(100),
            fee_rate: 0,
            range: 7676365,
            amount: to_e18(100),
            threshold_sqrt_price: Option::None(()),
            threshold_amount: Option::None(()),
            exp: array![
                SwapCase {
                    is_buy: true,
                    exact_input: true,
                    amount_in: to_e18(100),
                    amount_out: 9901054856275659172,
                    fees: 0, // TODO: fix amount
                },
                SwapCase {
                    is_buy: false,
                    exact_input: true,
                    amount_in: to_e18(100),
                    amount_out: 90909036314998803578,
                    fees: 0, // TODO: fix amount
                },
                SwapCase {
                    is_buy: true,
                    exact_input: false,
                    amount_in: 1111103771282806034735,
                    amount_out: to_e18(100),
                    fees: 0, // TODO: fix amount
                },
                SwapCase {
                    is_buy: false,
                    exact_input: false,
                    amount_in: 466588818773133962045136853193659825,
                    amount_out: to_e18(100),
                    fees: 0, // TODO: fix amount
                },
            ]
                .span(),
        },
        TestCase {
            description: "4) Concentrated liq, price 1, no fees",
            oracle_price: 1_00000000,
            base_reserves: to_e18(1000),
            quote_reserves: to_e18(1000),
            fee_rate: 0,
            range: 5000,
            amount: to_e18(100),
            threshold_sqrt_price: Option::None(()),
            threshold_amount: Option::None(()),
            exp: array![
                SwapCase {
                    is_buy: true,
                    exact_input: true,
                    amount_in: to_e18(100),
                    amount_out: 99753708432456984326,
                    fees: 0, // TODO: fix amount
                },
                SwapCase {
                    is_buy: false,
                    exact_input: true,
                    amount_in: to_e18(100),
                    amount_out: 99753708432456984326,
                    fees: 0, // TODO: fix amount
                },
                SwapCase {
                    is_buy: true,
                    exact_input: false,
                    amount_in: 100247510763823131034,
                    amount_out: to_e18(100),
                    fees: 0, // TODO: fix amount
                },
                SwapCase {
                    is_buy: false,
                    exact_input: false,
                    amount_in: 100247510763823131034,
                    amount_out: to_e18(100),
                    fees: 0, // TODO: fix amount
                },
            ]
                .span(),
        },
    ];
    cases.span()
}

fn get_test_cases_2() -> Span<TestCase> {
    let cases: Array<TestCase> = array![
        TestCase {
            description: "5) Concentrated liq, price 1, 1% fees",
            oracle_price: 1_00000000,
            base_reserves: to_e18(1000),
            quote_reserves: to_e18(1000),
            fee_rate: 100,
            range: 5000,
            amount: to_e18(100),
            threshold_sqrt_price: Option::None(()),
            threshold_amount: Option::None(()),
            exp: array![
                SwapCase {
                    is_buy: true,
                    exact_input: true,
                    amount_in: to_e18(100),
                    amount_out: 98758603689263513299,
                    fees: 0, // TODO: fix amount
                },
                SwapCase {
                    is_buy: false,
                    exact_input: true,
                    amount_in: to_e18(100),
                    amount_out: 98758603689263513299,
                    fees: 0, // TODO: fix amount
                },
                SwapCase {
                    is_buy: true,
                    exact_input: false,
                    amount_in: 101260111882649627307,
                    amount_out: to_e18(100),
                    fees: 0, // TODO: fix amount
                },
                SwapCase {
                    is_buy: false,
                    exact_input: false,
                    amount_in: 101260111882649627307,
                    amount_out: to_e18(100),
                    fees: 0, // TODO: fix amount
                },
            ]
                .span(),
        },
        TestCase {
            description: "6) Concentrated liq, price 1, 50% fees",
            oracle_price: 10_00000000,
            base_reserves: to_e18(1000),
            quote_reserves: to_e18(1000),
            fee_rate: 5000,
            range: 5000,
            amount: to_e18(100),
            threshold_sqrt_price: Option::None(()),
            threshold_amount: Option::None(()),
            exp: array![
                SwapCase {
                    is_buy: true,
                    exact_input: true,
                    amount_in: to_e18(100),
                    amount_out: 4999415848330513296,
                    fees: 0, // TODO: fix amount
                },
                SwapCase {
                    is_buy: false,
                    exact_input: true,
                    amount_in: to_e18(100),
                    amount_out: 493899555720718382442,
                    fees: 0, // TODO: fix amount
                },
                SwapCase {
                    is_buy: true,
                    exact_input: false,
                    amount_in: 2004936970885156305832,
                    amount_out: to_e18(100),
                    fees: 0, // TODO: fix amount
                },
                SwapCase {
                    is_buy: false,
                    exact_input: false,
                    amount_in: 20049634597552599158,
                    amount_out: to_e18(100),
                    fees: 0, // TODO: fix amount    
                },
            ]
                .span(),
        },
        TestCase {
            description: "7) Swap with liquidity exhausted",
            oracle_price: 1_00000000,
            base_reserves: to_e18(100),
            quote_reserves: to_e18(100),
            fee_rate: 100,
            range: 5000,
            amount: to_e18(200),
            threshold_sqrt_price: Option::None(()),
            threshold_amount: Option::None(()),
            exp: array![
                SwapCase {
                    is_buy: true,
                    exact_input: true,
                    amount_in: 103567170945545576580,
                    amount_out: to_e18(100),
                    fees: 0, // TODO: fix amount
                },
                SwapCase {
                    is_buy: true,
                    exact_input: false,
                    amount_in: 103567170945545576580,
                    amount_out: to_e18(100),
                    fees: 0, // TODO: fix amount
                },
                SwapCase {
                    is_buy: false,
                    exact_input: true,
                    amount_in: 103567170945545576580,
                    amount_out: to_e18(100),
                    fees: 0, // TODO: fix amount
                },
                SwapCase {
                    is_buy: false,
                    exact_input: false,
                    amount_in: 103567170945545576580,
                    amount_out: to_e18(100),
                    fees: 0, // TODO: fix amount
                },
            ]
                .span(),
        },
        TestCase {
            description: "8) Swap with high oracle price",
            oracle_price: 1_000_000_000_000_000_00000000,
            base_reserves: to_e18(1000),
            quote_reserves: to_e18(1000),
            fee_rate: 100,
            range: 5000,
            amount: to_e18(100),
            threshold_sqrt_price: Option::None(()),
            threshold_amount: Option::None(()),
            exp: array![
                SwapCase {
                    is_buy: true,
                    exact_input: true,
                    amount_in: to_e18(100),
                    amount_out: 99000,
                    fees: 0, // TODO: fix amount
                },
                SwapCase {
                    is_buy: false,
                    exact_input: true,
                    amount_in: 1035681,
                    amount_out: 999999999999999999999,
                    fees: 0, // TODO: fix amount
                },
                SwapCase {
                    is_buy: true,
                    exact_input: false,
                    amount_in: 101259191588416392788627371401827001,
                    amount_out: 100000000000000000000,
                    fees: 0, // TODO: fix amount
                },
                SwapCase {
                    is_buy: false,
                    exact_input: false,
                    amount_in: 101261,
                    amount_out: 100000000000000000000,
                    fees: 0, // TODO: fix amount
                },
            ]
                .span(),
        },
    ];
    cases.span()
}

fn get_test_cases_3() -> Span<TestCase> {
    let cases: Array<TestCase> = array![
        TestCase {
            description: "9) Swap with low oracle price",
            oracle_price: 1,
            base_reserves: to_e18(1000),
            quote_reserves: to_e18(1000),
            fee_rate: 100,
            range: 5000,
            amount: to_e18(100),
            threshold_sqrt_price: Option::None(()),
            threshold_amount: Option::None(()),
            exp: array![
                SwapCase {
                    is_buy: true,
                    exact_input: true,
                    amount_in: 10356643015690,
                    amount_out: 999999999999999999999,
                    fees: 0, // TODO: fix amount
                },
                SwapCase {
                    is_buy: false,
                    exact_input: true,
                    amount_in: 100000000000000000000,
                    amount_out: 989992918767,
                    fees: 0, // TODO: fix amount
                },
                SwapCase {
                    is_buy: true,
                    exact_input: false,
                    amount_in: 1012593875957,
                    amount_out: 99999999999999999999,
                    fees: 0, // TODO: fix amount
                },
                SwapCase {
                    is_buy: false,
                    exact_input: false,
                    amount_in: 10126083617468551702944516926,
                    amount_out: 100000000000000000000,
                    fees: 0, // TODO: fix amount
                },
            ]
                .span(),
        },
        TestCase {
            description: "10) Swap buy capped at threshold price",
            oracle_price: 1_00000000,
            base_reserves: to_e18(100),
            quote_reserves: to_e18(100),
            fee_rate: 100,
            range: 50000,
            amount: to_e18(50),
            threshold_sqrt_price: Option::Some(10488088481701515469914535136),
            threshold_amount: Option::None(()),
            exp: array![
                SwapCase {
                    is_buy: true,
                    exact_input: true,
                    amount_in: 22288543558601668321,
                    amount_out: 21038779527378539768,
                    fees: 0, // TODO: fix amount
                },
                SwapCase {
                    is_buy: true,
                    exact_input: false,
                    amount_in: 22288543558601668321,
                    amount_out: 21038779527378539768,
                    fees: 0, // TODO: fix amount
                },
            ]
                .span(),
        },
        TestCase {
            description: "11) Swap sell capped at threshold price",
            oracle_price: 1_00000000,
            base_reserves: to_e18(100),
            quote_reserves: to_e18(100),
            fee_rate: 100,
            range: 50000,
            amount: to_e18(50),
            threshold_sqrt_price: Option::Some(9486832980505137995996680633),
            threshold_amount: Option::None(()),
            exp: array![
                SwapCase {
                    is_buy: false,
                    exact_input: true,
                    amount_in: 24701345711211794538,
                    amount_out: 23199416574442336449,
                    fees: 0, // TODO: fix amount
                },
                SwapCase {
                    is_buy: false,
                    exact_input: false,
                    amount_in: 24701345711211794538,
                    amount_out: 23199416574442336449,
                    fees: 0, // TODO: fix amount
                },
            ]
                .span(),
        },
        TestCase {
            description: "12) Swap capped at threshold amount, exact input",
            oracle_price: 1_00000000,
            base_reserves: to_e18(1000),
            quote_reserves: to_e18(1000),
            fee_rate: 100,
            range: 5000,
            amount: to_e18(100),
            threshold_sqrt_price: Option::None(()),
            threshold_amount: Option::Some(98650000000000000000),
            exp: array![
                SwapCase {
                    is_buy: true,
                    exact_input: true,
                    amount_in: 99999999999999999999,
                    amount_out: 98758603689263513299,
                    fees: 0, // TODO: fix amount
                },
                SwapCase {
                    is_buy: false,
                    exact_input: true,
                    amount_in: 100000000000000000000,
                    amount_out: 98758603689263513299,
                    fees: 0, // TODO: fix amount
                },
            ]
                .span(),
        },
    // TestCase {
    //     description: "13) Swap capped at threshold amount, exact output",
    //     oracle_price: 1_00000000,
    //     base_reserves: to_e18(1000),
    //     quote_reserves: to_e18(1000),
    //     fee_rate: 100,
    //     range: 5000,
    //     amount: to_e18(100),
    //     threshold_sqrt_price: Option::None(()),
    //     threshold_amount: Option::Some(101350000000000000000),
    //     exp: array![
    //         SwapCase {
    //             is_buy: true,
    //             exact_input: false,
    //             amount_in: 101260111882649627307,
    //             amount_out: 99999999999999999999,
    //             fees: 0, // TODO: fix amount
    //         },
    //         SwapCase {
    //             is_buy: false,
    //             exact_input: false,
    //             amount_in: 101260111882649627307,
    //             amount_out: 100000000000000000000,
    //             fees: 0, // TODO: fix amount
    //         },
    //     ]
    //         .span(),
    // },
    ];
    cases.span()
}

fn run_swap_cases(cases: Span<TestCase>) {
    // Declare classes.
    let (erc20_class, vault_token_class, solver_class, oracle_class) = declare_classes();

    // Fetch, loop through and run test cases.
    let mut i = 0;
    loop {
        if i == cases.len() {
            break;
        }

        // Extract test case.
        let case = cases[i].clone();
        println!("Test Case {}", case.description);

        // Loop through swap cases.
        let mut j = 0;
        loop {
            if j == case.exp.len() {
                break;
            }

            // Extract swap case.
            let swap_case = case.exp[j].clone();

            // Setup vm.
            let salt: felt252 = (i.into() + 1) * 1000 + j.into() + 1;
            let (
                _base_token,
                _quote_token,
                oracle,
                _vault_token_class,
                solver,
                market_id,
                _vault_token_opt
            ) =
                before_with_salt(
                false, salt, (erc20_class, vault_token_class, solver_class, oracle_class)
            );

            // Print description.
            println!(
                "  Swap Case {}) is_buy: {}, exact_input: {}",
                j + 1,
                swap_case.is_buy,
                swap_case.exact_input
            );

            // Set params.
            start_prank(CheatTarget::One(solver.contract_address), owner());
            let rev_solver = IReversionSolverDispatcher {
                contract_address: solver.contract_address
            };
            let mut market_params = rev_solver.market_params(market_id);
            market_params.fee_rate = case.fee_rate;
            rev_solver.queue_market_params(market_id, market_params);
            rev_solver.set_market_params(market_id);

            // Set model params.
            rev_solver.set_model_params(market_id, Trend::Range, case.range);

            // Set oracle price.
            start_warp(CheatTarget::One(oracle.contract_address), 1000);
            oracle
                .set_data_with_USD_hop(
                    market_params.base_currency_id,
                    market_params.quote_currency_id,
                    case.oracle_price,
                    8,
                    999,
                    5
                );

            // Setup liquidity.
            start_prank(CheatTarget::One(solver.contract_address), owner());
            solver.deposit_initial(market_id, case.base_reserves, case.quote_reserves);

            // Obtain quotes and execute swaps.
            start_prank(CheatTarget::One(solver.contract_address), alice());
            let solver_hooks = ISolverHooksDispatcher { contract_address: solver.contract_address };
            let quote = solver_hooks
                .quote(
                    market_id,
                    SwapParams {
                        is_buy: swap_case.is_buy,
                        amount: case.amount,
                        exact_input: swap_case.exact_input,
                        threshold_sqrt_price: case.threshold_sqrt_price,
                        threshold_amount: case.threshold_amount,
                        deadline: Option::None(()),
                    }
                );

            // If exact input, additionally quote for uptrend and downtrend cases and compare quotes.
            if swap_case.exact_input && case.threshold_sqrt_price.is_none() {
                // Set uptrend and compare quotes.
                start_prank(CheatTarget::One(solver.contract_address), owner());
                let rev_solver = IReversionSolverDispatcher {
                    contract_address: solver.contract_address
                };
                rev_solver.set_model_params(market_id, Trend::Up, case.range);
                let quote_up = solver_hooks
                    .quote(
                        market_id,
                        SwapParams {
                            is_buy: swap_case.is_buy,
                            amount: case.amount,
                            exact_input: swap_case.exact_input,
                            threshold_sqrt_price: case.threshold_sqrt_price,
                            threshold_amount: case.threshold_amount,
                            deadline: Option::None(()),
                        }
                    );
                if swap_case.is_buy {
                    assert(
                        quote_up.amount_in == 0 && quote_up.amount_out == 0 && quote_up.fees == 0,
                        'Quote amounts: uptrend'
                    );
                } else {
                    assert(quote_up.amount_in == quote.amount_in, 'Quote in: uptrend');
                    assert(quote_up.amount_out == quote.amount_out, 'Quote out: uptrend');
                    assert(quote_up.fees == 0, 'Quote fees: uptrend');
                }
                // Set downtrend and compare quotes.
                rev_solver.set_model_params(market_id, Trend::Down, case.range);
                let quote_down = solver_hooks
                    .quote(
                        market_id,
                        SwapParams {
                            is_buy: swap_case.is_buy,
                            amount: case.amount,
                            exact_input: swap_case.exact_input,
                            threshold_sqrt_price: case.threshold_sqrt_price,
                            threshold_amount: case.threshold_amount,
                            deadline: Option::None(()),
                        }
                    );
                if !swap_case.is_buy {
                    assert(
                        quote_down.amount_in == 0
                            && quote_down.amount_out == 0
                            && quote_down.fees == 0,
                        'Quote amounts: downtrend'
                    );
                } else {
                    assert(quote_down.amount_in == quote.amount_in, 'Quote in: downtrend');
                    assert(quote_down.amount_out == quote.amount_out, 'Quote out: downtrend');
                    assert(quote_down.fees == 0, 'Quote fees: downtrend');
                }
                // Reset trend.
                rev_solver.set_model_params(market_id, Trend::Range, case.range);
            }

            // Execute swap.
            let swap = solver
                .swap(
                    market_id,
                    SwapParams {
                        is_buy: swap_case.is_buy,
                        amount: case.amount,
                        exact_input: swap_case.exact_input,
                        threshold_sqrt_price: case.threshold_sqrt_price,
                        threshold_amount: case.threshold_amount,
                        deadline: Option::None(()),
                    }
                );

            // Check results.
            println!(
                "    Amount in: {}, amount out: {}, fees: {}",
                swap.amount_in,
                swap.amount_out,
                swap.fees
            );
            assert(
                approx_eq_pct(swap.amount_in, swap_case.amount_in, 10)
                    || approx_eq(swap.amount_in, swap_case.amount_in, 1000),
                'Amount in'
            );
            assert(
                approx_eq_pct(swap.amount_out, swap_case.amount_out, 10)
                    || approx_eq(swap.amount_out, swap_case.amount_out, 1000),
                'Amount out'
            );
            assert(
                approx_eq_pct(swap.fees, swap_case.fees, 10)
                    || approx_eq(swap.fees, swap_case.fees, 1000),
                'Fees'
            );
            assert(swap.amount_in == quote.amount_in, 'Quote in');
            assert(swap.amount_out == quote.amount_out, 'Quote out');
            assert(swap.fees == quote.fees, 'Fees');

            j += 1;
        };

        i += 1;
    };
}

////////////////////////////////
// TESTS - Success cases
////////////////////////////////

#[test]
fn test_swap_cases_1() {
    run_swap_cases(get_test_cases_1());
}

#[test]
fn test_swap_cases_2() {
    run_swap_cases(get_test_cases_2());
}

#[test]
fn test_swap_cases_3() {
    run_swap_cases(get_test_cases_3());
}

#[test]
fn test_price_rises_above_last_cached_price_in_uptrend() {
    let (
        _base_token, _quote_token, oracle, _vault_token_class, solver, market_id, _vault_token_opt
    ) =
        before(
        false
    );

    // Set trend.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let rev_solver = IReversionSolverDispatcher { contract_address: solver.contract_address };
    let model_params = rev_solver.model_params(market_id);
    rev_solver.set_model_params(market_id, Trend::Up, model_params.range);

    // Deposit initial.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    solver.deposit_initial(market_id, to_e18(100), to_e18(1000));

    // Sell swap to cache price.
    start_prank(CheatTarget::One(solver.contract_address), alice());
    let params = SwapParams {
        is_buy: false,
        amount: to_e18(5),
        exact_input: true,
        threshold_sqrt_price: Option::None(()),
        threshold_amount: Option::None(()),
        deadline: Option::None(()),
    };
    solver.swap(market_id, params);

    // Oracle price rises above last cached price.
    start_warp(CheatTarget::One(oracle.contract_address), 1000);
    oracle.set_data_with_USD_hop('ETH', 'USDC', 1050000000, 8, 999, 5); // 10.5

    // Swap again to update cached price.
    start_prank(CheatTarget::One(solver.contract_address), alice());
    let params = SwapParams {
        is_buy: false,
        amount: to_e18(5),
        exact_input: true,
        threshold_sqrt_price: Option::None(()),
        threshold_amount: Option::None(()),
        deadline: Option::None(()),
    };
    let swap = solver.swap(market_id, params);

    // Run checks.
    let model_params = rev_solver.model_params(market_id);
    assert(model_params.cached_price == 1050000000, 'Cached price');
    assert(swap.amount_in == to_e18(5), 'Amount in');
    assert(swap.amount_out > to_e18(50), 'Amount out');
    assert(swap.fees == 0, 'Fees'); // TODO: fix amount
}

#[test]
fn test_price_falls_below_last_cached_price_and_rises_again_in_uptrend() {
    let (
        _base_token, _quote_token, oracle, _vault_token_class, solver, market_id, _vault_token_opt
    ) =
        before(
        false
    );

    // Set trend.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let rev_solver = IReversionSolverDispatcher { contract_address: solver.contract_address };
    let model_params = rev_solver.model_params(market_id);
    rev_solver.set_model_params(market_id, Trend::Up, model_params.range);

    // Deposit initial.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    solver.deposit_initial(market_id, to_e18(100), to_e18(1000));

    // Sell swap to cache price.
    start_prank(CheatTarget::One(solver.contract_address), alice());
    let params = SwapParams {
        is_buy: false,
        amount: to_e18(5),
        exact_input: true,
        threshold_sqrt_price: Option::None(()),
        threshold_amount: Option::None(()),
        deadline: Option::None(()),
    };
    solver.swap(market_id, params);

    // Oracle price falls above last cached price.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    oracle.set_data_with_USD_hop('ETH', 'USDC', 950000000, 8, 999, 5); // 9.5

    // Swap again to update cached price.
    start_prank(CheatTarget::One(solver.contract_address), alice());
    let params = SwapParams {
        is_buy: true,
        amount: to_e18(1),
        exact_input: true,
        threshold_sqrt_price: Option::None(()),
        threshold_amount: Option::None(()),
        deadline: Option::None(()),
    };
    let swap_1 = solver.swap(market_id, params);

    // Oracle price recovers.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    oracle.set_data_with_USD_hop('ETH', 'USDC', 990000000, 8, 999, 5); // 9.9

    // Swap again to update cached price.
    start_prank(CheatTarget::One(solver.contract_address), alice());
    let swap_2 = solver.swap(market_id, params);
    println!("amount_in_2: {}, amount_out_2: {}", swap_2.amount_in, swap_2.amount_out);

    // Run checks.
    let model_params = rev_solver.model_params(market_id);
    assert(model_params.cached_price == 1000000000, 'Cached price');
    assert(swap_1.amount_in == to_e18(1), 'Amount in 1');
    assert(swap_1.amount_out < to_e18(95) / 100, 'Amount out 1');
    assert(swap_1.fees == 0, 'Fees 1'); // TODO: fix amount
    assert(swap_2.amount_in == to_e18(1), 'Amount in 2');
    assert(
        swap_2.amount_out > to_e18(95) / 1000 && swap_2.amount_out < to_e18(1) / 100, 'Amount out 2'
    );
    assert(swap_2.fees == 0, 'Fees 2'); // TODO: fix amount
}

////////////////////////////////
// TESTS - Events
////////////////////////////////

#[test]
fn test_swap_emits_event() {
    let (
        _base_token, _quote_token, _oracle, _vault_token_class, solver, market_id, _vault_token_opt
    ) =
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
    let swap = solver.swap(market_id, params);

    // Check events.
    spy
        .assert_emitted(
            @array![
                (
                    solver.contract_address,
                    SolverComponent::Event::Swap(
                        SolverComponent::Swap {
                            market_id,
                            caller: alice(),
                            is_buy: params.is_buy,
                            exact_input: params.exact_input,
                            amount_in: swap.amount_in,
                            amount_out: swap.amount_out,
                            fees: swap.fees,
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
#[should_panic(expected: ('InvalidOraclePrice',))]
fn test_swap_fails_if_invalid_oracle_price() {
    let (
        _base_token, _quote_token, oracle, _vault_token_class, solver, market_id, _vault_token_opt
    ) =
        before(
        false
    );

    // Set oracle price.
    start_warp(CheatTarget::One(solver.contract_address), 1000);
    IMockPragmaOracleDispatcher { contract_address: oracle.contract_address }
        .set_data_with_USD_hop('ETH', 'USDC', 1000000000, 8, 999, 1); // 10

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
        threshold_amount: Option::None(()),
        deadline: Option::None(()),
    };
    solver.swap(market_id, params);
}

#[test]
#[should_panic(expected: ('ThresholdAmount', 995001635073273840, 0))]
fn test_swap_fails_if_swap_buy_below_threshold_amount() {
    let (
        _base_token, _quote_token, _oracle, _vault_token_class, solver, market_id, _vault_token_opt
    ) =
        before(
        false
    );

    // Deposit initial.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    solver.deposit_initial(market_id, to_e18(1000), 0);

    // Swap.
    start_prank(CheatTarget::One(solver.contract_address), alice());
    let params = SwapParams {
        is_buy: true,
        amount: to_e18(10),
        exact_input: true,
        threshold_sqrt_price: Option::None(()),
        threshold_amount: Option::Some(to_e18(2)),
        deadline: Option::None(()),
    };
    solver.swap(market_id, params);
}

#[test]
#[should_panic(expected: ('ThresholdAmount', 99449990405342377223, 0))]
fn test_swap_fails_if_swap_sell_below_threshold_amount() {
    let (
        _base_token, _quote_token, _oracle, _vault_token_class, solver, market_id, _vault_token_opt
    ) =
        before(
        false
    );

    // Deposit initial.
    solver.deposit_initial(market_id, to_e18(1000), to_e18(1000));

    // Swap.
    start_prank(CheatTarget::One(solver.contract_address), alice());
    let params = SwapParams {
        is_buy: false,
        amount: to_e18(10),
        exact_input: true,
        threshold_sqrt_price: Option::None(()),
        threshold_amount: Option::Some(to_e18(100)),
        deadline: Option::None(()),
    };
    solver.swap(market_id, params);
}

#[test]
#[should_panic(expected: ('LimitOF',))]
fn test_swap_fails_if_limit_overflows() {
    let (
        _base_token, _quote_token, _oracle, _vault_token_class, solver, market_id, _vault_token_opt
    ) =
        before(
        false
    );

    // Set params.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let rev_solver = IReversionSolverDispatcher { contract_address: solver.contract_address };
    let model_params = rev_solver.model_params(market_id);
    rev_solver.set_model_params(market_id, model_params.trend, 8000000);

    // Deposit initial.
    solver.deposit_initial(market_id, to_e18(1000), to_e18(1000));

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
#[should_panic(expected: ('OracleLimitUF',))]
fn test_swap_fails_if_limit_underflows() {
    let (
        _base_token, _quote_token, oracle, _vault_token_class, solver, market_id, _vault_token_opt
    ) =
        before(
        false
    );

    // Set oracle.
    start_warp(CheatTarget::One(oracle.contract_address), 1000);
    oracle.set_data_with_USD_hop('ETH', 'USDC', 1, 8, 999, 5);

    // Set params.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let rev_solver = IReversionSolverDispatcher { contract_address: solver.contract_address };
    let model_params = rev_solver.model_params(market_id);
    rev_solver.set_model_params(market_id, model_params.trend, 7000000);

    // Deposit initial.
    solver.deposit_initial(market_id, to_e18(1000), to_e18(1000));

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
        deadline: Option::None(()),
    };
    solver_hooks.after_swap(market_id, params);
}
