// Core lib imports.
use core::integer::BoundedInt;

// Local imports.
use haiko_solver_reversion::types::Trend;
use haiko_solver_reversion::libraries::{
    spread_math::{get_virtual_position, get_virtual_position_range}, swap_lib::get_swap_amounts
};

// Haiko imports.
use haiko_lib::math::price_math;
use haiko_lib::types::i32::{i32, I32Trait};
use haiko_lib::helpers::utils::{approx_eq, approx_eq_pct, to_e28, to_e18};
use haiko_lib::constants::{MAX_LIMIT_SHIFTED};

////////////////////////////////
// TYPES
////////////////////////////////

#[derive(Drop, Copy)]
struct PositionTestCase {
    lower_limit: u32,
    upper_limit: u32,
    amount: u256,
    lower_sqrt_price_exp: u256,
    upper_sqrt_price_exp: u256,
    bid_liquidity_exp: u128,
    ask_liquidity_exp: u128,
}

#[derive(Drop, Copy)]
struct PositionRangeTestCase {
    trend: Trend,
    range: u32,
    cached_price: u256,
    oracle_price: u256,
    bid_lower_exp: u32,
    bid_upper_exp: u32,
    ask_lower_exp: u32,
    ask_upper_exp: u32,
}

////////////////////////////////
// CONSTANTS
////////////////////////////////

const ONE: u128 = 10000000000000000000000000000;

////////////////////////////////
// TESTS
////////////////////////////////

#[test]
fn test_get_virtual_position_cases() {
    // Define test cases.
    let cases: Span<PositionTestCase> = array![
        // Case 1
        PositionTestCase {
            lower_limit: 7906624,
            upper_limit: 7906625,
            amount: to_e18(1000),
            lower_sqrt_price_exp: 9999950000374996875027343503,
            upper_sqrt_price_exp: to_e28(1),
            bid_liquidity_exp: 200001499998750006249960937,
            ask_liquidity_exp: 200000499998750006249960937,
        },
        // Case 2
        PositionTestCase {
            lower_limit: 7906625,
            upper_limit: 7907625,
            amount: 0,
            lower_sqrt_price_exp: 10000000000000000000000000000,
            upper_sqrt_price_exp: 10050124957342558567913166002,
            bid_liquidity_exp: 0,
            ask_liquidity_exp: 0,
        },
        // Case 3
        PositionTestCase {
            lower_limit: 7906625 - 600000,
            upper_limit: 7906625 - 500000,
            amount: to_e18(1),
            lower_sqrt_price_exp: 497878151745117899580653183,
            upper_sqrt_price_exp: 820860246859540603883281915,
            bid_liquidity_exp: 30961468611618563661,
            ask_liquidity_exp: 126535925281766305,
        },
        // Case 4
        PositionTestCase {
            lower_limit: 7906625 - 100000,
            upper_limit: 7906625 - 90000,
            amount: to_e18(1),
            lower_sqrt_price_exp: 6065321760310693212937818528,
            upper_sqrt_price_exp: 6376295862771640675414689014,
            bid_liquidity_exp: 32157018609791833633,
            ask_liquidity_exp: 12436497361224684536,
        },
        // Case 5
        PositionTestCase {
            lower_limit: 7906625 + 90000,
            upper_limit: 7906625 + 100000,
            amount: to_e18(1),
            lower_sqrt_price_exp: 15683086568152456989606954482,
            upper_sqrt_price_exp: 16487171489295820592662817441,
            bid_liquidity_exp: 12436497361224684536,
            ask_liquidity_exp: 32157018609791833633,
        },
        // Case 6
        PositionTestCase {
            lower_limit: 7906625 + 500000,
            upper_limit: 7906625 + 600000,
            amount: to_e18(1),
            lower_sqrt_price_exp: 121823416814959055458686853108,
            upper_sqrt_price_exp: 200852356444019400322324232963,
            bid_liquidity_exp: 126535925281766305,
            ask_liquidity_exp: 30961468611618563661,
        },
        // Case 7
        PositionTestCase {
            lower_limit: 7906625,
            upper_limit: 7907625,
            amount: 1,
            lower_sqrt_price_exp: 10000000000000000000000000000,
            upper_sqrt_price_exp: 10050124957342558567913166002,
            bid_liquidity_exp: 199,
            ask_liquidity_exp: 200,
        },
        // Case 8
        PositionTestCase {
            lower_limit: 7906625,
            upper_limit: 7907625,
            amount: to_e18(100000000000000000),
            lower_sqrt_price_exp: 10000000000000000000000000000,
            upper_sqrt_price_exp: 10050124957342558567913166002,
            bid_liquidity_exp: 19950141666274308048509441863855847152,
            ask_liquidity_exp: 20050141666274308048509441863855847152,
        },
    ]
        .span();

    // Loop through test cases and perform checks.
    let mut i = 0;
    loop {
        if i >= cases.len() {
            break;
        }
        let case = *cases.at(i);
        let bid = get_virtual_position(true, case.lower_limit, case.upper_limit, case.amount);
        let ask = get_virtual_position(false, case.lower_limit, case.upper_limit, case.amount);
        if (!approx_eq_pct(bid.lower_sqrt_price, case.lower_sqrt_price_exp, 22)) {
            panic!(
                "Lower sqrt p {}: {} (act), {} (exp)",
                i + 1,
                bid.lower_sqrt_price,
                case.lower_sqrt_price_exp
            );
        }
        if (!approx_eq_pct(bid.upper_sqrt_price, case.upper_sqrt_price_exp, 22)) {
            panic!(
                "Upper sqrt p {}: {} (act), {} (exp)",
                i + 1,
                bid.upper_sqrt_price,
                case.upper_sqrt_price_exp
            );
        }
        if (if bid.liquidity < ONE {
            !approx_eq(bid.liquidity.into(), case.bid_liquidity_exp.into(), 10000)
        } else {
            !approx_eq_pct(bid.liquidity.into(), case.bid_liquidity_exp.into(), 22)
        }) {
            panic!(
                "Bid liquidity {}: {} (act), {} (exp)", i + 1, bid.liquidity, case.bid_liquidity_exp
            );
        }
        if (if ask.liquidity < ONE {
            !approx_eq(ask.liquidity.into(), case.ask_liquidity_exp.into(), 10000)
        } else {
            !approx_eq_pct(ask.liquidity.into(), case.ask_liquidity_exp.into(), 22)
        }) {
            panic!(
                "Ask liquidity {}: {} (act), {} (exp)", i + 1, ask.liquidity, case.ask_liquidity_exp
            );
        }
        i += 1;
    };
}

#[test]
fn test_get_virtual_position_range() {
    // Define test cases.
    let cases: Span<PositionRangeTestCase> = array![
        // Case 1: Uptrend, oracle price is outside (above) bid position
        PositionRangeTestCase {
            trend: Trend::Up,
            range: 1000,
            cached_price: to_e28(1),
            oracle_price: to_e28(11) / 10, // 1.1
            bid_lower_exp: 7915156,
            bid_upper_exp: 7916156,
            ask_lower_exp: 0,
            ask_upper_exp: 0,
        },
        // Case 2: Uptrend, oracle price is equal to cached price
        PositionRangeTestCase {
            trend: Trend::Up,
            range: 1000,
            cached_price: to_e28(1),
            oracle_price: to_e28(1),
            bid_lower_exp: 7905625,
            bid_upper_exp: 7906625,
            ask_lower_exp: 0,
            ask_upper_exp: 0,
        },
        // Case 3: Uptrend, oracle price is inside virtual bid position
        PositionRangeTestCase {
            trend: Trend::Up,
            range: 1000,
            cached_price: to_e28(1),
            oracle_price: to_e28(995) / 1000, // 0.995
            bid_lower_exp: 7905625,
            bid_upper_exp: 7906123,
            ask_lower_exp: 7906123,
            ask_upper_exp: 7906625,
        },
        // Case 4: Uptrend, oracle price at bid lower
        PositionRangeTestCase {
            trend: Trend::Up,
            range: 1000,
            cached_price: to_e28(1),
            oracle_price: to_e28(99005) / 100000, // 0.99005
            bid_lower_exp: 0,
            bid_upper_exp: 0,
            ask_lower_exp: 7905625,
            ask_upper_exp: 7906625,
        },
        // Case 5: Uptrend, oracle price is outside (above) ask position
        PositionRangeTestCase {
            trend: Trend::Up,
            range: 1000,
            cached_price: to_e28(1),
            oracle_price: to_e28(95) / 100, // 0.95
            bid_lower_exp: 0,
            bid_upper_exp: 0,
            ask_lower_exp: 7905625,
            ask_upper_exp: 7906625,
        },
        // Case 6: Uptrend, cached price unset
        PositionRangeTestCase {
            trend: Trend::Up,
            range: 1000,
            cached_price: 0,
            oracle_price: to_e28(9) / 10, // 0.9
            bid_lower_exp: 7895088,
            bid_upper_exp: 7896088,
            ask_lower_exp: 0,
            ask_upper_exp: 0,
        },
        // Case 7: Downtrend, oracle price is outside (below) bid position
        PositionRangeTestCase {
            trend: Trend::Down,
            range: 1000,
            cached_price: to_e28(1),
            oracle_price: to_e28(9) / 10, // 0.9
            bid_lower_exp: 0,
            bid_upper_exp: 0,
            ask_lower_exp: 7896088,
            ask_upper_exp: 7897088,
        },
        // Case 8: Downtrend, oracle price is equal to cached price
        PositionRangeTestCase {
            trend: Trend::Down,
            range: 1000,
            cached_price: to_e28(1),
            oracle_price: to_e28(1),
            bid_lower_exp: 0,
            bid_upper_exp: 0,
            ask_lower_exp: 7906625,
            ask_upper_exp: 7907625,
        },
        // Case 9: Downtrend, oracle price is inside ask position
        PositionRangeTestCase {
            trend: Trend::Down,
            range: 1000,
            cached_price: to_e28(1),
            oracle_price: to_e28(1005) / 1000, // 1.005
            bid_lower_exp: 7906625,
            bid_upper_exp: 7907124,
            ask_lower_exp: 7907124,
            ask_upper_exp: 7907625,
        },
        // Case 10: Downtrend, oracle price is at ask upper
        PositionRangeTestCase {
            trend: Trend::Down,
            range: 1000,
            cached_price: to_e28(1),
            oracle_price: to_e28(101006) / 100000, // 1.01006
            bid_lower_exp: 7906625,
            bid_upper_exp: 7907625,
            ask_lower_exp: 0,
            ask_upper_exp: 0,
        },
        // Case 11: Downtrend, oracle price is outside (above) ask upper
        PositionRangeTestCase {
            trend: Trend::Down,
            range: 1000,
            cached_price: to_e28(1),
            oracle_price: to_e28(105) / 100, // 1.05
            bid_lower_exp: 7906625,
            bid_upper_exp: 7907625,
            ask_lower_exp: 0,
            ask_upper_exp: 0,
        },
        // Case 12: Downtrend, cached price unset
        PositionRangeTestCase {
            trend: Trend::Down,
            range: 1000,
            cached_price: 0,
            oracle_price: to_e28(11) / 10, // 1.1
            bid_lower_exp: 0,
            bid_upper_exp: 0,
            ask_lower_exp: 7916156,
            ask_upper_exp: 7917156,
        },
        // Case 13: Ranging, oracle price is equal to cached
        PositionRangeTestCase {
            trend: Trend::Range,
            range: 1000,
            cached_price: to_e28(1),
            oracle_price: to_e28(1),
            bid_lower_exp: 7905625,
            bid_upper_exp: 7906625,
            ask_lower_exp: 7906625,
            ask_upper_exp: 7907625,
        },
        // Case 14: Ranging, oracle price is above cached
        PositionRangeTestCase {
            trend: Trend::Range,
            range: 1000,
            cached_price: to_e28(1),
            oracle_price: to_e28(15) / 10, // 1.5
            bid_lower_exp: 7946171,
            bid_upper_exp: 7947171,
            ask_lower_exp: 7947171,
            ask_upper_exp: 7948171,
        },
        // Case 15: Ranging, oracle price is above cached
        PositionRangeTestCase {
            trend: Trend::Range,
            range: 1000,
            cached_price: to_e28(1),
            oracle_price: to_e28(5) / 10, // 0.5
            bid_lower_exp: 7836309,
            bid_upper_exp: 7837309,
            ask_lower_exp: 7837309,
            ask_upper_exp: 7838309,
        },
    ]
        .span();

    // Loop through test cases and perform checks.
    let mut i = 0;
    loop {
        if i >= cases.len() {
            break;
        }
        let case = *cases.at(i);
        let (bid_lower, bid_upper, ask_lower, ask_upper) = get_virtual_position_range(
            case.trend, case.range, case.cached_price, case.oracle_price
        );
        if (!approx_eq(bid_lower.into(), case.bid_lower_exp.into(), 1)) {
            panic!("Bid lower {}: {} (act), {} (exp)", i + 1, bid_lower, case.bid_lower_exp);
        }
        if (!approx_eq(bid_upper.into(), case.bid_upper_exp.into(), 1)) {
            panic!("Bid upper {}: {} (act), {} (exp)", i + 1, bid_upper, case.bid_upper_exp);
        }
        if (!approx_eq(ask_lower.into(), case.ask_lower_exp.into(), 1)) {
            panic!("Ask lower {}: {} (act), {} (exp)", i + 1, ask_lower, case.ask_lower_exp);
        }
        if (!approx_eq(ask_upper.into(), case.ask_upper_exp.into(), 1)) {
            panic!("Ask upper {}: {} (act), {} (exp)", i + 1, ask_upper, case.ask_upper_exp);
        }
        i += 1;
    };
}

#[test]
#[should_panic(expected: ('CachedLimitUF',))]
fn test_get_virtual_position_range_cached_limit_underflow() {
    get_virtual_position_range(Trend::Range, 2000000, 10, to_e28(1));
}

#[test]
#[should_panic(expected: ('OracleLimitUF',))]
fn test_get_virtual_position_range_oracle_limit_underflow() {
    get_virtual_position_range(Trend::Range, 2000000, to_e28(1), 10);
}

#[test]
#[should_panic(expected: ('OraclePriceZero',))]
fn test_get_virtual_position_range_oracle_price_zero() {
    get_virtual_position_range(Trend::Range, 1000, to_e28(1), 0);
}
