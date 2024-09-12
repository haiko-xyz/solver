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
    pub max_delta: u32,
    pub max_skew: u16,
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
            max_delta: 0,
            max_skew: 0,
            amount: to_e18(100),
            threshold_sqrt_price: Option::None(()),
            threshold_amount: Option::None(()),
            exp: array![
                SwapCase {
                    is_buy: true,
                    exact_input: true,
                    amount_in: to_e18(100),
                    amount_out: 90909090909090909146,
                    fees: 0,
                },
                SwapCase {
                    is_buy: false,
                    exact_input: true,
                    amount_in: to_e18(100),
                    amount_out: 90909090909090909146,
                    fees: 0,
                },
                SwapCase {
                    is_buy: true,
                    exact_input: false,
                    amount_in: 111111111111111111027,
                    amount_out: to_e18(100),
                    fees: 0,
                },
                SwapCase {
                    is_buy: false,
                    exact_input: false,
                    amount_in: 111111111111111111027,
                    amount_out: to_e18(100),
                    fees: 0,
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
            max_delta: 0,
            max_skew: 0,
            amount: to_e18(10),
            threshold_sqrt_price: Option::None(()),
            threshold_amount: Option::None(()),
            exp: array![
                SwapCase {
                    is_buy: true,
                    exact_input: true,
                    amount_in: to_e18(10),
                    amount_out: 49999834853317669644,
                    fees: 0,
                },
                SwapCase {
                    is_buy: false,
                    exact_input: true,
                    amount_in: to_e18(10),
                    amount_out: 998997611702025557,
                    fees: 0,
                },
                SwapCase {
                    is_buy: true,
                    exact_input: false,
                    amount_in: 1111118450987902274,
                    amount_out: to_e18(10),
                    fees: 0,
                },
                SwapCase {
                    is_buy: false,
                    exact_input: false,
                    amount_in: 101010443847319896836,
                    amount_out: to_e18(10),
                    fees: 0,
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
            max_delta: 0,
            max_skew: 0,
            amount: to_e18(100),
            threshold_sqrt_price: Option::None(()),
            threshold_amount: Option::None(()),
            exp: array![
                SwapCase {
                    is_buy: true,
                    exact_input: true,
                    amount_in: to_e18(100),
                    amount_out: 9900956827006555844,
                    fees: 0,
                },
                SwapCase {
                    is_buy: false,
                    exact_input: true,
                    amount_in: to_e18(100),
                    amount_out: 90909036314998803578,
                    fees: 0,
                },
                SwapCase {
                    is_buy: true,
                    exact_input: false,
                    amount_in: 1111114882320518862795,
                    amount_out: to_e18(100),
                    fees: 0,
                },
                SwapCase {
                    is_buy: false,
                    exact_input: false,
                    amount_in: 466588818773133962045136853193659825,
                    amount_out: to_e18(100),
                    fees: 0,
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
            max_delta: 0,
            max_skew: 0,
            amount: to_e18(100),
            threshold_sqrt_price: Option::None(()),
            threshold_amount: Option::None(()),
            exp: array![
                SwapCase {
                    is_buy: true,
                    exact_input: true,
                    amount_in: to_e18(100),
                    amount_out: 99753708432456984326,
                    fees: 0,
                },
                SwapCase {
                    is_buy: false,
                    exact_input: true,
                    amount_in: to_e18(100),
                    amount_out: 99753708432456984326,
                    fees: 0,
                },
                SwapCase {
                    is_buy: true,
                    exact_input: false,
                    amount_in: 100247510763823131034,
                    amount_out: to_e18(100),
                    fees: 0,
                },
                SwapCase {
                    is_buy: false,
                    exact_input: false,
                    amount_in: 100247510763823131034,
                    amount_out: to_e18(100),
                    fees: 0,
                },
            ]
                .span(),
        },
        TestCase {
            description: "5) Concentrated liq, price 1, 1% fees",
            oracle_price: 1_00000000,
            base_reserves: to_e18(1000),
            quote_reserves: to_e18(1000),
            fee_rate: 100,
            range: 5000,
            max_delta: 0,
            max_skew: 0,
            amount: to_e18(100),
            threshold_sqrt_price: Option::None(()),
            threshold_amount: Option::None(()),
            exp: array![
                SwapCase {
                    is_buy: true,
                    exact_input: true,
                    amount_in: to_e18(100),
                    amount_out: 98758603689263513299,
                    fees: to_e18(1),
                },
                SwapCase {
                    is_buy: false,
                    exact_input: true,
                    amount_in: to_e18(100),
                    amount_out: 98758603689263513299,
                    fees: to_e18(1),
                },
                SwapCase {
                    is_buy: true,
                    exact_input: false,
                    amount_in: 101260111882649627307,
                    amount_out: to_e18(100),
                    fees: 1012601118826496273,
                },
                SwapCase {
                    is_buy: false,
                    exact_input: false,
                    amount_in: 101260111882649627307,
                    amount_out: to_e18(100),
                    fees: 1012601118826496273,
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
            description: "6) Concentrated liq, price 1, 50% fees",
            oracle_price: 10_00000000,
            base_reserves: to_e18(1000),
            quote_reserves: to_e18(1000),
            fee_rate: 5000,
            range: 5000,
            max_delta: 0,
            max_skew: 0,
            amount: to_e18(100),
            threshold_sqrt_price: Option::None(()),
            threshold_amount: Option::None(()),
            exp: array![
                SwapCase {
                    is_buy: true,
                    exact_input: true,
                    amount_in: to_e18(100),
                    amount_out: 4999365860842892496,
                    fees: 50000000000000000000,
                },
                SwapCase {
                    is_buy: false,
                    exact_input: true,
                    amount_in: to_e18(100),
                    amount_out: 493899555720718382442,
                    fees: 50000000000000000000,
                },
                SwapCase {
                    is_buy: true,
                    exact_input: false,
                    amount_in: 2004957020254865157395,
                    amount_out: to_e18(100),
                    fees: 1002478510127432578697,
                },
                SwapCase {
                    is_buy: false,
                    exact_input: false,
                    amount_in: 20049634597552599158,
                    amount_out: to_e18(100),
                    fees: 10024817298776299579,
                },
            ]
                .span(),
        },
        TestCase {
            description: "7) Concentrated liq, price 1, 1% fees, 500 max delta",
            oracle_price: 1_00000000,
            base_reserves: to_e18(500),
            quote_reserves: to_e18(1000),
            fee_rate: 100,
            range: 5000,
            max_delta: 500,
            max_skew: 0,
            amount: to_e18(100),
            threshold_sqrt_price: Option::None(()),
            threshold_amount: Option::None(()),
            exp: array![
                SwapCase {
                    is_buy: true,
                    exact_input: true,
                    amount_in: to_e18(100),
                    amount_out: 98355771317925390873,
                    fees: to_e18(1),
                },
                SwapCase {
                    is_buy: false,
                    exact_input: true,
                    amount_in: to_e18(100),
                    amount_out: 98922277561466653632,
                    fees: to_e18(1),
                },
                SwapCase {
                    is_buy: true,
                    exact_input: false,
                    amount_in: 101680011392792093046,
                    amount_out: to_e18(100),
                    fees: 1016800113927920930,
                },
                SwapCase {
                    is_buy: false,
                    exact_input: false,
                    amount_in: 101092160374998987555,
                    amount_out: to_e18(100),
                    fees: 1010921603749989875,
                },
            ]
                .span(),
        },
        TestCase {
            description: "8) Concentrated liq, price 0.1, 1% fees, 20000 max delta",
            oracle_price: 0_10000000,
            base_reserves: to_e18(500),
            quote_reserves: to_e18(1000),
            fee_rate: 100,
            range: 5000,
            max_delta: 20000,
            max_skew: 0,
            amount: to_e18(100),
            threshold_sqrt_price: Option::None(()),
            threshold_amount: Option::None(()),
            exp: array![
                SwapCase {
                    is_buy: true,
                    exact_input: true,
                    amount_in: 62054865270942237718,
                    amount_out: 499999999999999999999,
                    fees: 620548652709422377,
                },
                SwapCase {
                    is_buy: false,
                    exact_input: true,
                    amount_in: to_e18(100),
                    amount_out: 11860073497841049336,
                    fees: to_e18(1),
                },
                SwapCase {
                    is_buy: true,
                    exact_input: false,
                    amount_in: 12164615338690643305,
                    amount_out: to_e18(100),
                    fees: 121646153386906433,
                },
                SwapCase {
                    is_buy: false,
                    exact_input: false,
                    amount_in: 845004508813220005468,
                    amount_out: to_e18(100),
                    fees: 8450045088132200054,
                },
            ]
                .span(),
        },
        TestCase {
            description: "9) Swap with liquidity exhausted",
            oracle_price: 1_00000000,
            base_reserves: to_e18(100),
            quote_reserves: to_e18(100),
            fee_rate: 100,
            range: 5000,
            max_delta: 0,
            max_skew: 0,
            amount: to_e18(200),
            threshold_sqrt_price: Option::None(()),
            threshold_amount: Option::None(()),
            exp: array![
                SwapCase {
                    is_buy: true,
                    exact_input: true,
                    amount_in: 103567170945545576580,
                    amount_out: 99999999999999999999,
                    fees: 1035671709455455765,
                },
                SwapCase {
                    is_buy: false,
                    exact_input: true,
                    amount_in: 103567170945545576580,
                    amount_out: 99999999999999999999,
                    fees: 1035671709455455765,
                },
            ]
                .span(),
        },
        TestCase {
            description: "10) Swap with high oracle price",
            oracle_price: 1_000_000_000_000_000_00000000,
            base_reserves: to_e18(1000),
            quote_reserves: to_e18(1000),
            fee_rate: 100,
            range: 5000,
            max_delta: 0,
            max_skew: 0,
            amount: to_e18(100),
            threshold_sqrt_price: Option::None(()),
            threshold_amount: Option::None(()),
            exp: array![
                SwapCase {
                    is_buy: true,
                    exact_input: true,
                    amount_in: to_e18(100),
                    amount_out: 98999,
                    fees: to_e18(1)
                },
                SwapCase {
                    is_buy: false,
                    exact_input: true,
                    amount_in: 1035681,
                    amount_out: 999999999999999999999,
                    fees: 10356,
                },
                SwapCase {
                    is_buy: true,
                    exact_input: false,
                    amount_in: 101260204180332276952555257675541019,
                    amount_out: 100000000000000000000,
                    fees: 1012602041803322769525552576755410,
                },
                SwapCase {
                    is_buy: false,
                    exact_input: false,
                    amount_in: 101261,
                    amount_out: 100000000000000000000,
                    fees: 1012,
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
            description: "11) Swap with low oracle price",
            oracle_price: 1,
            base_reserves: to_e18(1000),
            quote_reserves: to_e18(1000),
            fee_rate: 100,
            range: 5000,
            max_delta: 0,
            max_skew: 0,
            amount: to_e18(100),
            threshold_sqrt_price: Option::None(()),
            threshold_amount: Option::None(()),
            exp: array![
                SwapCase {
                    is_buy: true,
                    exact_input: true,
                    amount_in: 10356746582120,
                    amount_out: 999999999999999999999,
                    fees: 103567465821,
                },
                SwapCase {
                    is_buy: false,
                    exact_input: true,
                    amount_in: 100000000000000000000,
                    amount_out: 989992918767,
                    fees: 1000000000000000000,
                },
                SwapCase {
                    is_buy: true,
                    exact_input: false,
                    amount_in: 1012604001896,
                    amount_out: 99999999999999999999,
                    fees: 10126040018,
                },
                SwapCase {
                    is_buy: false,
                    exact_input: false,
                    amount_in: 10126083617468551702944516926,
                    amount_out: 100000000000000000000,
                    fees: 101260836174685517029445169,
                },
            ]
                .span(),
        },
        TestCase {
            description: "12) Swap buy capped at threshold price",
            oracle_price: 1_00000000,
            base_reserves: to_e18(100),
            quote_reserves: to_e18(100),
            fee_rate: 100,
            range: 50000,
            max_delta: 0,
            max_skew: 0,
            amount: to_e18(50),
            threshold_sqrt_price: Option::Some(10488088481701515469914535136),
            threshold_amount: Option::None(()),
            exp: array![
                SwapCase {
                    is_buy: true,
                    exact_input: true,
                    amount_in: 22288543558601668321,
                    amount_out: 21038779527378539768,
                    fees: 222885435586016683,
                },
                SwapCase {
                    is_buy: true,
                    exact_input: false,
                    amount_in: 22288543558601668321,
                    amount_out: 21038779527378539768,
                    fees: 222885435586016683,
                },
            ]
                .span(),
        },
        TestCase {
            description: "13) Swap sell capped at threshold price",
            oracle_price: 1_00000000,
            base_reserves: to_e18(100),
            quote_reserves: to_e18(100),
            fee_rate: 100,
            range: 50000,
            max_delta: 0,
            max_skew: 0,
            amount: to_e18(50),
            threshold_sqrt_price: Option::Some(9486832980505137995996680633),
            threshold_amount: Option::None(()),
            exp: array![
                SwapCase {
                    is_buy: false,
                    exact_input: true,
                    amount_in: 24701345711211794538,
                    amount_out: 23199416574442336449,
                    fees: 247013457112117945,
                },
                SwapCase {
                    is_buy: false,
                    exact_input: false,
                    amount_in: 24701345711211794538,
                    amount_out: 23199416574442336449,
                    fees: 247013457112117945,
                },
            ]
                .span(),
        },
        TestCase {
            description: "14) Swap capped at threshold amount, exact input",
            oracle_price: 1_00000000,
            base_reserves: to_e18(1000),
            quote_reserves: to_e18(1000),
            fee_rate: 100,
            range: 5000,
            max_delta: 0,
            max_skew: 0,
            amount: to_e18(100),
            threshold_sqrt_price: Option::None(()),
            threshold_amount: Option::Some(98750000000000000000),
            exp: array![
                SwapCase {
                    is_buy: true,
                    exact_input: true,
                    amount_in: 99999999999999999999,
                    amount_out: 98758603689263513299,
                    fees: 999999999999999999,
                },
                SwapCase {
                    is_buy: false,
                    exact_input: true,
                    amount_in: 100000000000000000000,
                    amount_out: 98758603689263513299,
                    fees: 1000000000000000000,
                },
            ]
                .span(),
        },
        TestCase {
            description: "15) Swap capped at threshold amount, exact output",
            oracle_price: 1_00000000,
            base_reserves: to_e18(1000),
            quote_reserves: to_e18(1000),
            fee_rate: 100,
            range: 5000,
            max_delta: 0,
            max_skew: 0,
            amount: to_e18(100),
            threshold_sqrt_price: Option::None(()),
            threshold_amount: Option::Some(101500000000000000000),
            exp: array![
                SwapCase {
                    is_buy: true,
                    exact_input: false,
                    amount_in: 101260111882649627307,
                    amount_out: 99999999999999999999,
                    fees: 1012601118826496273,
                },
                SwapCase {
                    is_buy: false,
                    exact_input: false,
                    amount_in: 101260111882649627307,
                    amount_out: 100000000000000000000,
                    fees: 1012601118826496273,
                },
            ]
                .span(),
        },
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

        // Loop through swap cases.
        let case = cases[i].clone();
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
            println!("Test Case {}", case.description);
            println!(
                "Swap Case {}) is_buy: {}, exact_input: {}",
                j + 1,
                swap_case.is_buy,
                swap_case.exact_input
            );

            // Set params.
            start_prank(CheatTarget::One(solver.contract_address), owner());
            let repl_solver = IReplicatingSolverDispatcher {
                contract_address: solver.contract_address
            };
            let mut market_params = repl_solver.market_params(market_id);
            market_params.fee_rate = case.fee_rate;
            market_params.range = case.range;
            market_params.max_delta = case.max_delta;
            market_params.max_skew = case.max_skew;
            repl_solver.queue_market_params(market_id, market_params);
            repl_solver.set_market_params(market_id);

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
                "amount in: {}, amount out: {}, fees: {}",
                swap.amount_in,
                swap.amount_out,
                swap.fees
            );
            if !(approx_eq_pct(swap.amount_in, swap_case.amount_in, 10)
                || approx_eq(swap.amount_in, swap_case.amount_in, 1000)) {
                panic(
                    array![
                        'Amount in',
                        i.into() + 1,
                        j.into() + 1,
                        swap.amount_in.low.into(),
                        swap.amount_in.high.into(),
                        swap_case.amount_in.low.into(),
                        swap_case.amount_in.high.into()
                    ]
                );
            }
            if !(approx_eq_pct(swap.amount_out, swap_case.amount_out, 10)
                || approx_eq(swap.amount_out, swap_case.amount_out, 1000)) {
                panic(
                    array![
                        'Amount out',
                        i.into() + 1,
                        j.into() + 1,
                        swap.amount_out.low.into(),
                        swap.amount_out.high.into(),
                        swap_case.amount_out.low.into(),
                        swap_case.amount_out.high.into()
                    ]
                );
            }
            if !(approx_eq_pct(swap.fees, swap_case.fees, 10)
                || approx_eq(swap.fees, swap_case.fees, 1000)) {
                panic(
                    array![
                        'Fees',
                        i.into() + 1,
                        j.into() + 1,
                        swap.fees.low.into(),
                        swap.fees.high.into(),
                        swap_case.fees.low.into(),
                        swap_case.fees.high.into()
                    ]
                );
            }
            assert(swap.amount_in == quote.amount_in, 'Quote in');
            assert(swap.amount_out == quote.amount_out, 'Quote out');
            assert(swap.fees == quote.fees, 'Quote fees');
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
fn test_swap_that_improves_skew_is_allowed() {
    let (
        _base_token, _quote_token, oracle, _vault_token_class, solver, market_id, _vault_token_opt
    ) =
        before(
        false
    );
    // Set skew at 50%.
    let repl_solver = IReplicatingSolverDispatcher { contract_address: solver.contract_address };
    let mut params = repl_solver.market_params(market_id);
    params.max_skew = 5000;
    repl_solver.queue_market_params(market_id, params);
    repl_solver.set_market_params(market_id);

    // Set oracle price.
    start_warp(CheatTarget::One(oracle.contract_address), 1000);
    oracle.set_data_with_USD_hop('ETH', 'USDC', 1_00000000, 8, 999, 5);

    // Deposit initial.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    solver.deposit_initial(market_id, to_e18(75), to_e18(25));

    // Set oracle price to bring skew above threshold.
    start_warp(CheatTarget::One(oracle.contract_address), 1000);
    oracle.set_data_with_USD_hop('ETH', 'USDC', 100_00000000, 8, 999, 5);

    // Swap buy to improve skew.
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
#[should_panic(expected: ('ThresholdAmount', 999979051909438890, 0))]
fn test_swap_fails_if_swap_buy_below_threshold_amount() {
    let (
        _base_token, _quote_token, _oracle, _vault_token_class, solver, market_id, _vault_token_opt
    ) =
        before(
        false
    );

    // Set params to remove max skew.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let repl_solver = IReplicatingSolverDispatcher { contract_address: solver.contract_address };
    let mut market_params = repl_solver.market_params(market_id);
    market_params.max_skew = 0;
    repl_solver.queue_market_params(market_id, market_params);
    repl_solver.set_market_params(market_id);

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
#[should_panic(expected: ('ThresholdAmount', 99044273158283891908, 0))]
fn test_swap_fails_if_swap_sell_below_threshold_amount() {
    let (
        _base_token, _quote_token, _oracle, _vault_token_class, solver, market_id, _vault_token_opt
    ) =
        before(
        false
    );

    // Disable max skew.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let repl_solver = IReplicatingSolverDispatcher { contract_address: solver.contract_address };
    let mut market_params = repl_solver.market_params(market_id);
    market_params.max_skew = 0;
    repl_solver.queue_market_params(market_id, market_params);
    repl_solver.set_market_params(market_id);

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
    let repl_solver = IReplicatingSolverDispatcher { contract_address: solver.contract_address };
    let mut market_params = repl_solver.market_params(market_id);
    market_params.range = 8000000;
    market_params.max_skew = 0;
    repl_solver.queue_market_params(market_id, market_params);
    repl_solver.set_market_params(market_id);

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
#[should_panic(expected: ('LimitUF',))]
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
    let repl_solver = IReplicatingSolverDispatcher { contract_address: solver.contract_address };
    let mut market_params = repl_solver.market_params(market_id);
    market_params.range = 7000000;
    market_params.max_skew = 0;
    repl_solver.queue_market_params(market_id, market_params);
    repl_solver.set_market_params(market_id);

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
#[should_panic(expected: ('MaxSkew',))]
fn test_swap_buy_above_max_skew_is_disallowed() {
    let (
        _base_token, _quote_token, oracle, _vault_token_class, solver, market_id, _vault_token_opt
    ) =
        before(
        false
    );

    // Set skew at 50%.
    let repl_solver = IReplicatingSolverDispatcher { contract_address: solver.contract_address };
    let mut params = repl_solver.market_params(market_id);
    params.max_skew = 5000;
    repl_solver.queue_market_params(market_id, params);
    repl_solver.set_market_params(market_id);

    // Set oracle price.
    start_warp(CheatTarget::One(oracle.contract_address), 1000);
    oracle.set_data_with_USD_hop('ETH', 'USDC', 100000000, 8, 999, 5); // 1

    // Deposit initial.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    solver.deposit_initial(market_id, to_e18(25), to_e18(75));

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
#[should_panic(expected: ('MaxSkew',))]
fn test_swap_sell_above_max_skew_is_disallowed() {
    let (
        _base_token, _quote_token, oracle, _vault_token_class, solver, market_id, _vault_token_opt
    ) =
        before(
        false
    );

    // Set skew at 50%.
    let repl_solver = IReplicatingSolverDispatcher { contract_address: solver.contract_address };
    let mut params = repl_solver.market_params(market_id);
    params.max_skew = 5000;
    repl_solver.queue_market_params(market_id, params);
    repl_solver.set_market_params(market_id);

    // Set oracle price.
    start_warp(CheatTarget::One(oracle.contract_address), 1000);
    oracle.set_data_with_USD_hop('ETH', 'USDC', 100000000, 8, 999, 5); // 1

    // Deposit initial.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    solver.deposit_initial(market_id, to_e18(75), to_e18(25));

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
#[should_panic(expected: ('MaxSkew',))]
fn test_change_in_oracle_price_above_max_skew_prevents_swap() {
    let (
        _base_token, _quote_token, oracle, _vault_token_class, solver, market_id, _vault_token_opt
    ) =
        before(
        false
    );

    // Set skew at 50%.
    let repl_solver = IReplicatingSolverDispatcher { contract_address: solver.contract_address };
    let mut params = repl_solver.market_params(market_id);
    params.max_skew = 5000;
    repl_solver.queue_market_params(market_id, params);
    repl_solver.set_market_params(market_id);

    // Set oracle price.
    start_warp(CheatTarget::One(oracle.contract_address), 1000);
    oracle.set_data_with_USD_hop('ETH', 'USDC', 1_00000000, 8, 999, 5);

    // Deposit initial.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    solver.deposit_initial(market_id, to_e18(25), to_e18(75));

    // Set oracle price to bring skew above threshold.
    start_warp(CheatTarget::One(oracle.contract_address), 1000);
    oracle.set_data_with_USD_hop('ETH', 'USDC', 0_10000000, 8, 999, 5);

    // Swap sell to improve skew.
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
#[should_panic(expected: ('Expired',))]
fn test_swap_past_expiry_is_rejected() {
    let (
        _base_token, _quote_token, _oracle, _vault_token_class, solver, market_id, _vault_token_opt
    ) =
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
