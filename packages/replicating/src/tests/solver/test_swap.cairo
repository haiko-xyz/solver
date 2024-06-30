// Core lib imports.
use starknet::contract_address_const;

// Local imports.
use haiko_solver_core::{
    contracts::solver::SolverComponent,
    interfaces::{
        ISolver::{
            ISolverDispatcher, ISolverDispatcherTrait, ISolverQuoterDispatcher,
            ISolverQuoterDispatcherTrait
        },
        IVaultToken::{IVaultTokenDispatcher, IVaultTokenDispatcherTrait},
    },
    types::{SwapParams, MarketInfo},
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
    pub min_spread: u32,
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
}

fn get_test_cases_1() -> Span<TestCase> {
    let cases: Array<TestCase> = array![
        TestCase {
            description: "1) Full range liq, price 1, no spread",
            oracle_price: 1_00000000,
            base_reserves: to_e18(1000),
            quote_reserves: to_e18(1000),
            min_spread: 0,
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
                    amount_out: 90909090909090909146
                },
                SwapCase {
                    is_buy: false,
                    exact_input: true,
                    amount_in: to_e18(100),
                    amount_out: 90909090909090909146
                },
                SwapCase {
                    is_buy: true,
                    exact_input: false,
                    amount_in: 111111111111111111027,
                    amount_out: to_e18(100)
                },
                SwapCase {
                    is_buy: false,
                    exact_input: false,
                    amount_in: 111111111111111111027,
                    amount_out: to_e18(100)
                },
            ]
                .span(),
        },
        TestCase {
            description: "2) Full range liq, price 0.1, no spread",
            oracle_price: 0_10000000,
            base_reserves: to_e18(100),
            quote_reserves: to_e18(1000),
            min_spread: 0,
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
                    amount_out: 49999834853317669644
                },
                SwapCase {
                    is_buy: false,
                    exact_input: true,
                    amount_in: to_e18(10),
                    amount_out: 998997611702025557
                },
                SwapCase {
                    is_buy: true,
                    exact_input: false,
                    amount_in: 1111118450987902274,
                    amount_out: to_e18(10)
                },
                SwapCase {
                    is_buy: false,
                    exact_input: false,
                    amount_in: 101010443847319896836,
                    amount_out: to_e18(10)
                },
            ]
                .span(),
        },
        TestCase {
            description: "3) Full range liq, price 10, no spread",
            oracle_price: 10_00000000,
            base_reserves: to_e18(1000),
            quote_reserves: to_e18(100),
            min_spread: 0,
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
                    amount_out: 9900956827006555844
                },
                SwapCase {
                    is_buy: false,
                    exact_input: true,
                    amount_in: to_e18(100),
                    amount_out: 90909036314998803578
                },
                SwapCase {
                    is_buy: true,
                    exact_input: false,
                    amount_in: 1111114882320518862795,
                    amount_out: to_e18(100)
                },
                SwapCase {
                    is_buy: false,
                    exact_input: false,
                    amount_in: 466588818773133962045136853193659825,
                    amount_out: to_e18(100)
                },
            ]
                .span(),
        },
        TestCase {
            description: "4) Concentrated liq, price 1, no spread",
            oracle_price: 1_00000000,
            base_reserves: to_e18(1000),
            quote_reserves: to_e18(1000),
            min_spread: 0,
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
                    amount_out: 99753708432456984326
                },
                SwapCase {
                    is_buy: false,
                    exact_input: true,
                    amount_in: to_e18(100),
                    amount_out: 99753708432456984326
                },
                SwapCase {
                    is_buy: true,
                    exact_input: false,
                    amount_in: 100247510763823131034,
                    amount_out: to_e18(100)
                },
                SwapCase {
                    is_buy: false,
                    exact_input: false,
                    amount_in: 100247510763823131034,
                    amount_out: to_e18(100)
                },
            ]
                .span(),
        },
        TestCase {
            description: "5) Concentrated liq, price 1, 100 spread",
            oracle_price: 1_00000000,
            base_reserves: to_e18(1000),
            quote_reserves: to_e18(1000),
            min_spread: 100,
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
                    amount_out: 99654250398634336911
                },
                SwapCase {
                    is_buy: false,
                    exact_input: true,
                    amount_in: to_e18(100),
                    amount_out: 99654250398634336911
                },
                SwapCase {
                    is_buy: true,
                    exact_input: false,
                    amount_in: 100347807913318736434,
                    amount_out: to_e18(100)
                },
                SwapCase {
                    is_buy: false,
                    exact_input: false,
                    amount_in: 100347807913318736434,
                    amount_out: to_e18(100)
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
            description: "6) Concentrated liq, price 1, 50000 spread",
            oracle_price: 10_00000000,
            base_reserves: to_e18(1000),
            quote_reserves: to_e18(1000),
            min_spread: 50000,
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
                    amount_out: 6064393018672684143
                },
                SwapCase {
                    is_buy: false,
                    exact_input: true,
                    amount_in: to_e18(100),
                    amount_out: 597579323442496790520
                },
                SwapCase {
                    is_buy: true,
                    exact_input: false,
                    amount_in: 1652803511080475795527,
                    amount_out: to_e18(100)
                },
                SwapCase {
                    is_buy: false,
                    exact_input: false,
                    amount_in: 16528088195378414840,
                    amount_out: to_e18(100)
                },
            ]
                .span(),
        },
        TestCase {
            description: "7) Concentrated liq, price 1, 100 spread, 500 max delta",
            oracle_price: 1_00000000,
            base_reserves: to_e18(500),
            quote_reserves: to_e18(1000),
            min_spread: 100,
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
                    amount_out: 99245582637747914747
                },
                SwapCase {
                    is_buy: false,
                    exact_input: true,
                    amount_in: to_e18(100),
                    amount_out: 99819404970139967372
                },
                SwapCase {
                    is_buy: true,
                    exact_input: false,
                    amount_in: 100763924334713808578,
                    amount_out: to_e18(100)
                },
                SwapCase {
                    is_buy: false,
                    exact_input: false,
                    amount_in: 100181369566420499919,
                    amount_out: to_e18(100)
                },
            ]
                .span(),
        },
        TestCase {
            description: "8) Concentrated liq, price 0.1, 100 spread, 20000 max delta",
            oracle_price: 0_10000000,
            base_reserves: to_e18(500),
            quote_reserves: to_e18(1000),
            min_spread: 100,
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
                    amount_in: 61495781354774112619,
                    amount_out: 499999999999999999999
                },
                SwapCase {
                    is_buy: false,
                    exact_input: true,
                    amount_in: to_e18(100),
                    amount_out: 11967866534829175688
                },
                SwapCase {
                    is_buy: true,
                    exact_input: false,
                    amount_in: 12055018117706607774,
                    amount_out: to_e18(100)
                },
                SwapCase {
                    is_buy: false,
                    exact_input: false,
                    amount_in: 837391432418576103404,
                    amount_out: to_e18(100)
                },
            ]
                .span(),
        },
        TestCase {
            description: "9) Swap with liquidity exhausted",
            oracle_price: 1_00000000,
            base_reserves: to_e18(100),
            quote_reserves: to_e18(100),
            min_spread: 100,
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
                    amount_in: 102634081505001697489,
                    amount_out: 99999999999999999999
                },
                SwapCase {
                    is_buy: false,
                    exact_input: true,
                    amount_in: 102634081505001697489,
                    amount_out: 99999999999999999999
                },
            ]
                .span(),
        },
        TestCase {
            description: "10) Swap with high oracle price",
            oracle_price: 1_000_000_000_000_000_00000000,
            base_reserves: to_e18(1000),
            quote_reserves: to_e18(1000),
            min_spread: 100,
            range: 5000,
            max_delta: 0,
            max_skew: 0,
            amount: to_e18(100),
            threshold_sqrt_price: Option::None(()),
            threshold_amount: Option::None(()),
            exp: array![
                SwapCase {
                    is_buy: true, exact_input: true, amount_in: to_e18(100), amount_out: 99899,
                },
                SwapCase {
                    is_buy: false,
                    exact_input: true,
                    amount_in: 1026350,
                    amount_out: 999999999999999999999,
                },
                SwapCase {
                    is_buy: true,
                    exact_input: false,
                    amount_in: 100347899379444510663740995366407145,
                    amount_out: 99999999999999999999,
                },
                SwapCase {
                    is_buy: false,
                    exact_input: false,
                    amount_in: 100348,
                    amount_out: 100000000000000000000,
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
            min_spread: 100,
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
                    amount_in: 10263437372397,
                    amount_out: 999999999999999999999,
                },
                SwapCase {
                    is_buy: false,
                    exact_input: true,
                    amount_in: 99999999999999999999,
                    amount_out: 998993359216,
                },
                SwapCase {
                    is_buy: true,
                    exact_input: false,
                    amount_in: 1003480936228,
                    amount_out: 100000000000000000000,
                },
                SwapCase {
                    is_buy: false,
                    exact_input: false,
                    amount_in: 10034852567983843807643429092,
                    amount_out: 100000000000000000000,
                },
            ]
                .span(),
        },
        TestCase {
            description: "12) Swap buy capped at threshold price",
            oracle_price: 1_00000000,
            base_reserves: to_e18(100),
            quote_reserves: to_e18(100),
            min_spread: 100,
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
                    amount_in: 21850483612303829529,
                    amount_out: 20823204527740984512,
                },
                SwapCase {
                    is_buy: true,
                    exact_input: false,
                    amount_in: 21850483612303829529,
                    amount_out: 20823204527740984512,
                },
            ]
                .span(),
        },
        TestCase {
            description: "13) Swap sell capped at threshold price",
            oracle_price: 1_00000000,
            base_reserves: to_e18(100),
            quote_reserves: to_e18(100),
            min_spread: 100,
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
                    amount_in: 24240352373112801069,
                    amount_out: 22984922158048704819,
                },
                SwapCase {
                    is_buy: false,
                    exact_input: false,
                    amount_in: 24240352373112801069,
                    amount_out: 22984922158048704819,
                },
            ]
                .span(),
        },
        TestCase {
            description: "14) Swap capped at threshold amount, exact input",
            oracle_price: 1_00000000,
            base_reserves: to_e18(1000),
            quote_reserves: to_e18(1000),
            min_spread: 100,
            range: 5000,
            max_delta: 0,
            max_skew: 0,
            amount: to_e18(100),
            threshold_sqrt_price: Option::None(()),
            threshold_amount: Option::Some(99650000000000000000),
            exp: array![
                SwapCase {
                    is_buy: true,
                    exact_input: true,
                    amount_in: 99999999999999999999,
                    amount_out: 99654250398634336911,
                },
                SwapCase {
                    is_buy: false,
                    exact_input: true,
                    amount_in: 100000000000000000000,
                    amount_out: 99654250398634336911,
                },
            ]
                .span(),
        },
        TestCase {
            description: "15) Swap capped at threshold amount, exact output",
            oracle_price: 1_00000000,
            base_reserves: to_e18(1000),
            quote_reserves: to_e18(1000),
            min_spread: 100,
            range: 5000,
            max_delta: 0,
            max_skew: 0,
            amount: to_e18(100),
            threshold_sqrt_price: Option::None(()),
            threshold_amount: Option::Some(100350000000000000000),
            exp: array![
                SwapCase {
                    is_buy: true,
                    exact_input: false,
                    amount_in: 100347807913318736434,
                    amount_out: 99999999999999999999,
                },
                SwapCase {
                    is_buy: false,
                    exact_input: false,
                    amount_in: 100347807913318736434,
                    amount_out: 100000000000000000000,
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
            market_params.min_spread = case.min_spread;
            market_params.range = case.range;
            market_params.max_delta = case.max_delta;
            market_params.max_skew = case.max_skew;
            repl_solver.set_market_params(market_id, market_params);

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
            let solver_quoter = ISolverQuoterDispatcher {
                contract_address: solver.contract_address
            };
            let (quote_in, quote_out) = solver_quoter
                .quote(
                    market_id,
                    SwapParams {
                        is_buy: swap_case.is_buy,
                        amount: case.amount,
                        exact_input: swap_case.exact_input,
                        threshold_sqrt_price: case.threshold_sqrt_price,
                        threshold_amount: case.threshold_amount,
                    }
                );

            // Execute swap.
            let (amount_in, amount_out) = solver
                .swap(
                    market_id,
                    SwapParams {
                        is_buy: swap_case.is_buy,
                        amount: case.amount,
                        exact_input: swap_case.exact_input,
                        threshold_sqrt_price: case.threshold_sqrt_price,
                        threshold_amount: case.threshold_amount,
                    }
                );

            // Check results.
            println!("amount in: {}, amount out: {}", amount_in, amount_out);
            assert(
                approx_eq_pct(amount_in, swap_case.amount_in, 10)
                    || approx_eq(amount_in, swap_case.amount_in, 1000),
                'Amount in'
            );
            assert(
                approx_eq_pct(amount_out, swap_case.amount_out, 10)
                    || approx_eq(amount_out, swap_case.amount_out, 1000),
                'Amount out'
            );
            assert(amount_in == quote_in, 'Quote in');
            assert(amount_out == quote_out, 'Quote out');

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
    repl_solver.set_market_params(market_id, params);

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
    };
    solver.swap(market_id, params);
}

////////////////////////////////
// TESTS - Events
////////////////////////////////

#[test]
fn test_swap_should_emit_event() {
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
    };
    let (amount_in, amount_out) = solver.swap(market_id, params);

    // Check events emitted.
    spy
        .assert_emitted(
            @array![
                (
                    solver.contract_address,
                    SolverComponent::Event::Swap(
                        SolverComponent::Swap { market_id, caller: alice(), amount_in, amount_out, }
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
    let (
        _base_token, _quote_token, _oracle, _vault_token_class, solver, _market_id, _vault_token_opt
    ) =
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
    };
    solver.swap(1, params);
}

#[test]
#[should_panic(expected: ('Paused',))]
fn test_swap_fails_if_market_paused() {
    let (
        _base_token, _quote_token, _oracle, _vault_token_class, solver, market_id, _vault_token_opt
    ) =
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
    };
    solver.swap(market_id, params);
}

#[test]
#[should_panic(expected: ('BaseAllowance',))]
fn test_swap_fails_if_not_approved() {
    let (
        base_token, quote_token, _oracle, _vault_token_class, solver, market_id, _vault_token_opt
    ) =
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
    };
    solver.swap(market_id, params);
}

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
    };
    solver.swap(market_id, params);
}

#[test]
#[should_panic(expected: ('AmountZero',))]
fn test_swap_fails_if_amount_zero() {
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
    start_prank(CheatTarget::One(solver.contract_address), alice());
    let params = SwapParams {
        is_buy: true,
        amount: 0,
        exact_input: true,
        threshold_sqrt_price: Option::None(()),
        threshold_amount: Option::None(()),
    };
    solver.swap(market_id, params);
}

#[test]
#[should_panic(expected: ('ThresholdAmountZero',))]
fn test_swap_fails_if_min_amount_out_zero() {
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
    start_prank(CheatTarget::One(solver.contract_address), alice());
    let params = SwapParams {
        is_buy: true,
        amount: to_e18(10),
        exact_input: true,
        threshold_sqrt_price: Option::None(()),
        threshold_amount: Option::Some(0),
    };
    solver.swap(market_id, params);
}

#[test]
#[should_panic(expected: ('AmountZero',))]
fn test_swap_fails_if_swap_buy_with_zero_liquidity() {
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
    repl_solver.set_market_params(market_id, market_params);

    // Deposit initial.
    solver.deposit_initial(market_id, 0, to_e18(1000));

    // Swap.
    start_prank(CheatTarget::One(solver.contract_address), alice());
    let params = SwapParams {
        is_buy: true,
        amount: to_e18(10),
        exact_input: true,
        threshold_sqrt_price: Option::None(()),
        threshold_amount: Option::None(()),
    };
    solver.swap(market_id, params);
}

#[test]
#[should_panic(expected: ('AmountZero',))]
fn test_swap_fails_if_swap_sell_with_zero_liquidity() {
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
    repl_solver.set_market_params(market_id, market_params);

    // Deposit initial.
    solver.deposit_initial(market_id, to_e18(1000), 0);

    // Swap.
    start_prank(CheatTarget::One(solver.contract_address), alice());
    let params = SwapParams {
        is_buy: false,
        amount: to_e18(10),
        exact_input: true,
        threshold_sqrt_price: Option::None(()),
        threshold_amount: Option::None(()),
    };
    solver.swap(market_id, params);
}

#[test]
#[should_panic(expected: ('ThresholdAmount', 1004501675692245436, 0))]
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
    repl_solver.set_market_params(market_id, market_params);

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
    };
    solver.swap(market_id, params);
}

#[test]
#[should_panic(expected: ('ThresholdAmount', 99492002490779814763, 0))]
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
    repl_solver.set_market_params(market_id, market_params);

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
    repl_solver.set_market_params(market_id, market_params);

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
    repl_solver.set_market_params(market_id, market_params);

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
    repl_solver.set_market_params(market_id, params);

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
    repl_solver.set_market_params(market_id, params);

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
    repl_solver.set_market_params(market_id, params);

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
    };
    solver.swap(market_id, params);
}
