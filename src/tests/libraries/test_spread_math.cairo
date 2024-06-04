// Core lib imports.
use core::integer::BoundedInt;

// Local imports.
use haiko_solver_replicating::libraries::{
    spread_math::{get_virtual_position, get_virtual_position_range, get_delta, get_skew}, 
    swap_lib::get_swap_amounts
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
    min_spread: u32,
    delta: i32,
    range: u32,
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
        let bid = get_virtual_position(
            true, case.lower_limit, case.upper_limit, case.amount
        );
        let ask = get_virtual_position(
            false, case.lower_limit, case.upper_limit, case.amount
        );
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
            panic!("Bid liquidity {}: {} (act), {} (exp)", i + 1, bid.liquidity, case.bid_liquidity_exp);
        }
        if (if ask.liquidity < ONE {
            !approx_eq(ask.liquidity.into(), case.ask_liquidity_exp.into(), 10000)
        } else {
            !approx_eq_pct(ask.liquidity.into(), case.ask_liquidity_exp.into(), 22)
        }) {
            panic!("Ask liquidity {}: {} (act), {} (exp)", i + 1, ask.liquidity, case.ask_liquidity_exp);
        }
        i += 1;
    };
}

#[test]
fn test_get_virtual_position_range_cases() {
    // Define test cases.
    let cases: Span<PositionRangeTestCase> = array![
        // Case 1: No min spread, no delta, range 1
        PositionRangeTestCase {
            min_spread: 0,
            delta: I32Trait::new(0, false),
            range: 1,
            oracle_price: to_e28(1),
            bid_lower_exp: 7906624,
            bid_upper_exp: 7906625,
            ask_lower_exp: 7906625,
            ask_upper_exp: 7906626,
        },
        // Case 2: 500 min spread, no delta, range 1000
        PositionRangeTestCase {
            min_spread: 500,
            delta: I32Trait::new(0, false),
            range: 1000,
            oracle_price: to_e28(1),
            bid_lower_exp: 7905125,
            bid_upper_exp: 7906125,
            ask_lower_exp: 7907125,
            ask_upper_exp: 7908125,
        },
        // Case 3: 100000 min spread, no delta, range 1000
        PositionRangeTestCase {
            min_spread: 100000,
            delta: I32Trait::new(0, false),
            range: 1000,
            oracle_price: to_e28(1),
            bid_lower_exp: 7805625,
            bid_upper_exp: 7806625,
            ask_lower_exp: 8006625,
            ask_upper_exp: 8007625,
        },
        // Case 4: Max min spread, no delta, range 1000
        PositionRangeTestCase {
            min_spread: 7905625,
            delta: I32Trait::new(0, false),
            range: 1000,
            oracle_price: to_e28(1),
            bid_lower_exp: 0,
            bid_upper_exp: 1000,
            ask_lower_exp: MAX_LIMIT_SHIFTED - 1000,
            ask_upper_exp: MAX_LIMIT_SHIFTED,
        },
        // Case 5: 500 min spread, 100 bid delta, range 1000
        PositionRangeTestCase {
            min_spread: 500,
            delta: I32Trait::new(100, true),
            range: 1000,
            oracle_price: to_e28(1),
            bid_lower_exp: 7905025,
            bid_upper_exp: 7906025,
            ask_lower_exp: 7907025,
            ask_upper_exp: 7908025,
        },
        // Case 6: 500 min spread, 100 ask delta, range 1000
        PositionRangeTestCase {
            min_spread: 500,
            delta: I32Trait::new(100, false),
            range: 1000,
            oracle_price: to_e28(1),
            bid_lower_exp: 7905225,
            bid_upper_exp: 7906225,
            ask_lower_exp: 7907225,
            ask_upper_exp: 7908225,
        },
        // Case 7: 500 min spread, 5000 bid delta, range 1000
        PositionRangeTestCase {
            min_spread: 500,
            delta: I32Trait::new(5000, true),
            range: 1000,
            oracle_price: to_e28(1),
            bid_lower_exp: 7900125,
            bid_upper_exp: 7901125,
            ask_lower_exp: 7902125,
            ask_upper_exp: 7903125,
        },
        // Case 8: 500 min spread, 5000 ask delta, range 1000
        PositionRangeTestCase {
            min_spread: 500,
            delta: I32Trait::new(5000, false),
            range: 1000,
            oracle_price: to_e28(1),
            bid_lower_exp: 7910125,
            bid_upper_exp: 7911125,
            ask_lower_exp: 7912125,
            ask_upper_exp: 7913125,
        },
        // Case 9: 500 min spread, max bid delta (7905125), range 1000
        PositionRangeTestCase {
            min_spread: 500,
            delta: I32Trait::new(7905125, true),
            range: 1000,
            oracle_price: to_e28(1),
            bid_lower_exp: 0,
            bid_upper_exp: 1000,
            ask_lower_exp: 2000,
            ask_upper_exp: 3000,
        },
        // Case 10: 500 min spread, max ask delta (7905125), range 1000
        PositionRangeTestCase {
            min_spread: 500,
            delta: I32Trait::new(7905125, false),
            range: 1000,
            oracle_price: to_e28(1),
            bid_lower_exp: MAX_LIMIT_SHIFTED - 3000,
            bid_upper_exp: MAX_LIMIT_SHIFTED - 2000,
            ask_lower_exp: MAX_LIMIT_SHIFTED - 1000,
            ask_upper_exp: MAX_LIMIT_SHIFTED,
        },
        // Case 11: 500 min spread, no delta, range 1000, very small oracle price
        PositionRangeTestCase {
            min_spread: 500,
            delta: I32Trait::new(0, false), 
            range: 1000,
            oracle_price: 1, // limit: 1459354
            bid_lower_exp: 1457854,
            bid_upper_exp: 1458854,
            ask_lower_exp: 1459855,
            ask_upper_exp: 1460855,
        },
        // Case 12: 500 min spread, no delta, range 1000, very large oracle price
        PositionRangeTestCase {
            min_spread: 500,
            delta: I32Trait::new(0, false), 
            range: 1000,
            oracle_price: 214459684708337062817548134114224826295263805072231182393896500, // limit: 7905125 (roundup)
            bid_lower_exp: MAX_LIMIT_SHIFTED - 3000,
            bid_upper_exp: MAX_LIMIT_SHIFTED - 2000,
            ask_lower_exp: MAX_LIMIT_SHIFTED - 1000,
            ask_upper_exp: MAX_LIMIT_SHIFTED,
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
        let (bid_lower, bid_upper) = get_virtual_position_range(
            true, case.min_spread, case.delta, case.range, case.oracle_price
        );
        let (ask_lower, ask_upper) = get_virtual_position_range(
            false, case.min_spread, case.delta, case.range, case.oracle_price
        );
        if (!approx_eq(bid_lower.into(), case.bid_lower_exp.into(), 1)) {
            panic!(
                "Bid lower {}: {} (act), {} (exp)",
                i + 1,
                bid_lower,
                case.bid_lower_exp
            );
        }
        if (!approx_eq(bid_upper.into(), case.bid_upper_exp.into(), 1)) {
            panic!(
                "Bid upper {}: {} (act), {} (exp)",
                i + 1,
                bid_upper,
                case.bid_upper_exp
            );
        }
        if (!approx_eq(ask_lower.into(), case.ask_lower_exp.into(), 1)) {
            panic!(
                "Ask lower {}: {} (act), {} (exp)",
                i + 1,
                ask_lower,
                case.ask_lower_exp
            );
        }
        if (!approx_eq(ask_upper.into(), case.ask_upper_exp.into(), 1)) {
            panic!(
                "Ask upper {}: {} (act), {} (exp)",
                i + 1,
                ask_upper,
                case.ask_upper_exp
            );
        }
        i += 1;
    };
}

#[test]
#[should_panic(expected: ('LimitUF',))]
fn test_get_virtual_position_range_bid_limit_underflow() {
    get_virtual_position_range(true, 0, I32Trait::new(0, false), 2000000, 1);
}

#[test]
#[should_panic(expected: ('ShiftLimitOF',))]
fn test_get_virtual_position_range_ask_limit_overflow() {
    get_virtual_position_range(false, 10, I32Trait::new(0, false), 0, 217702988461462792141570404997617821806367875652638254199700027);
}

#[test]
#[should_panic(expected: ('OraclePriceZero',))]
fn test_get_virtual_position_range_oracle_price_zero() {
    get_virtual_position_range(true, 0, I32Trait::new(0, false), 0, 0);
}

#[test]
#[should_panic(expected: ('ShiftLimitOF',))]
fn test_get_virtual_position_range_oracle_price_overflow() {
    get_virtual_position_range(true, 0, I32Trait::new(0, false), 0, 217713873828591030783410061480731509152483726437928216295905367);
}

#[test]
fn test_get_delta() {
    // Equal amounts
    let mut max_delta = 2000;
    let mut base_amount = to_e18(1);
    let mut quote_amount = to_e18(2000);
    let mut price = to_e28(2000);
    let mut inv_delta = get_delta(max_delta, base_amount, quote_amount, price);
    assert(inv_delta == I32Trait::new(0, false), 'Inv delta 1');

    // Skewed to base
    base_amount = to_e18(2);
    inv_delta = get_delta(max_delta, base_amount, quote_amount, price);
    assert(inv_delta == I32Trait::new(666, false), 'Inv delta 2');

    // Skewed to quote
    base_amount = to_e18(1);
    quote_amount = to_e18(3600);
    inv_delta = get_delta(max_delta, base_amount, quote_amount, price);
    assert(inv_delta == I32Trait::new(571, true), 'Inv delta 3');

    // All base
    quote_amount = 0;
    inv_delta = get_delta(max_delta, base_amount, quote_amount, price);
    assert(inv_delta == I32Trait::new(2000, false), 'Inv delta 4');

    // All quote
    quote_amount = to_e18(2000);
    base_amount = 0;
    inv_delta = get_delta(max_delta, base_amount, quote_amount, price);
    assert(inv_delta == I32Trait::new(2000, true), 'Inv delta 5');

    // Small token values
    base_amount = 1;
    quote_amount = 3;
    price = to_e28(2);
    inv_delta = get_delta(max_delta, base_amount, quote_amount, price);
    assert(inv_delta == I32Trait::new(400, true), 'Inv delta 6');

    // Large token values
    base_amount = to_e28(1000);
    quote_amount = to_e28(20000);
    inv_delta = get_delta(max_delta, base_amount, quote_amount, price);
    assert(inv_delta == I32Trait::new(1636, true), 'Inv delta 7');

    // Near max delta
    base_amount = to_e18(50);
    quote_amount = 0;
    max_delta = 7906600;
    inv_delta = get_delta(max_delta, base_amount, quote_amount, price);
    assert(inv_delta == I32Trait::new(7906600, false), 'Inv delta 8');

    // Zero delta
    max_delta = 0;
    inv_delta = get_delta(max_delta, base_amount, quote_amount, price);
    assert(inv_delta == I32Trait::new(0, false), 'Inv delta 9');
// TODO: price 0

// TODO: very small price

// TODO: very large price
}
