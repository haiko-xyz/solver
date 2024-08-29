// Core lib imports.
use core::integer::BoundedInt;

// Local imports.
use haiko_solver_core::types::{SwapParams, PositionInfo};
use haiko_solver_reversion::libraries::swap_lib::{
    get_swap_amounts, compute_swap_amounts, next_sqrt_price_input, next_sqrt_price_output
};

// Haiko imports.
use haiko_lib::math::fee_math::gross_to_net;
use haiko_lib::constants::{ONE, MAX};
use haiko_lib::helpers::utils::{
    approx_eq, approx_eq_pct, encode_sqrt_price, to_e18, to_e28, to_e18_u128, to_e28_u128
};

////////////////////////////////
// TESTS - get_swap_amounts
////////////////////////////////

#[test]
fn test_get_swap_amounts_succeeds() {
    let swap_params = SwapParams {
        is_buy: true,
        amount: to_e18(1),
        exact_input: true,
        threshold_sqrt_price: Option::None(()),
        threshold_amount: Option::None(()),
        deadline: Option::None(()),
    };
    let position = PositionInfo {
        lower_sqrt_price: encode_sqrt_price(8, 10),
        upper_sqrt_price: encode_sqrt_price(1, 1),
        liquidity: to_e18_u128(10000),
    };
    let (amount_in, amount_out) = get_swap_amounts(swap_params, position, 0);
    assert(approx_eq(amount_in, 1000000000000000000, 1000), 'Swap amts: amt in');
    assert(approx_eq(amount_out, 1249860261374659470, 1000), 'Swap amts: amt out');
}

#[test]
fn test_get_swap_amounts_over_zero_liquidity() {
    let swap_params = SwapParams {
        is_buy: true,
        amount: to_e18(1),
        exact_input: true,
        threshold_sqrt_price: Option::None(()),
        threshold_amount: Option::None(()),
        deadline: Option::None(()),
    };
    let position = PositionInfo {
        lower_sqrt_price: encode_sqrt_price(1, 1),
        upper_sqrt_price: encode_sqrt_price(12, 10),
        liquidity: 0,
    };
    let (amount_in, amount_out) = get_swap_amounts(swap_params, position, 50);
    assert(amount_in == 0 && amount_out == 0, 'Swap amts: 0 liq');
}

#[test]
fn test_get_swap_amounts_bid_threshold_sqrt_price() {
    let swap_params = SwapParams {
        is_buy: false,
        amount: to_e18(10),
        exact_input: true,
        threshold_sqrt_price: Option::Some(encode_sqrt_price(95, 100)),
        threshold_amount: Option::None(()),
        deadline: Option::None(()),
    };
    let position = PositionInfo {
        lower_sqrt_price: encode_sqrt_price(8, 10),
        upper_sqrt_price: encode_sqrt_price(1, 1),
        liquidity: to_e18_u128(200),
    };
    let (amount_in, amount_out) = get_swap_amounts(swap_params, position, 50);
    println!("Amount in: {}, Amount out: {}", amount_in, amount_out);
    assert(approx_eq_pct(amount_in, 5221779313598832344, 14), 'Amount in');
    assert(approx_eq_pct(amount_out, 5064113103820740000, 14), 'Amount out');
}

#[test]
fn test_get_swap_amounts_ask_threshold_sqrt_price() {
    let swap_params = SwapParams {
        is_buy: true,
        amount: to_e18(10),
        exact_input: true,
        threshold_sqrt_price: Option::Some(encode_sqrt_price(105, 100)),
        threshold_amount: Option::None(()),
        deadline: Option::None(()),
    };
    let position = PositionInfo {
        lower_sqrt_price: encode_sqrt_price(1, 1),
        upper_sqrt_price: encode_sqrt_price(12, 10),
        liquidity: to_e18_u128(200),
    };
    let (amount_in, amount_out) = get_swap_amounts(swap_params, position, 50);
    println!("Amount in: {}, Amount out: {}", amount_in, amount_out);
    assert(approx_eq_pct(amount_in, 4963834491650251256, 14), 'Amount in');
    assert(approx_eq_pct(amount_out, 4819985410293394924, 14), 'Amount out');
}

////////////////////////////////
// TESTS - compute_swap_amounts
////////////////////////////////

#[test]
fn test_compute_swap_amounts_buy_exact_input_reaches_price_target() {
    let curr_sqrt_price = encode_sqrt_price(1, 1);
    let target_sqrt_price = encode_sqrt_price(101, 100);
    let liquidity = to_e28_u128(2);
    let amount_rem = to_e28(1);

    let (amount_in, amount_out, next_sqrt_price) = compute_swap_amounts(
        curr_sqrt_price, target_sqrt_price, liquidity, amount_rem, true
    );
    let next_sqrt_price_full_amount = next_sqrt_price_input(
        curr_sqrt_price, liquidity, amount_rem, true
    );

    assert(amount_in == 99751242241780540438529824, 'comp_swap buy/in/cap in');
    assert(amount_out == 99256195800217286694524923, 'comp_swap buy/in/cap out');
    assert(next_sqrt_price == 10049875621120890270219264912, 'comp_swap buy/in/cap price');
    assert(next_sqrt_price == target_sqrt_price, 'comp_swap buy/in/cap target P');
    assert(next_sqrt_price < next_sqrt_price_full_amount, 'comp_swap buy/in/cap target Q');
    assert(amount_rem > amount_in, 'comp_swap buy/in/cap amount_rem');
}

#[test]
fn test_compute_swap_amounts_buy_exact_output_reaches_price_target() {
    let curr_sqrt_price = encode_sqrt_price(1, 1);
    let target_sqrt_price = encode_sqrt_price(101, 100);
    let liquidity = to_e28_u128(2);
    let amount_rem = to_e28(1);

    let (amount_in, amount_out, next_sqrt_price) = compute_swap_amounts(
        curr_sqrt_price, target_sqrt_price, liquidity, amount_rem, false
    );
    let next_sqrt_price_full_amount = next_sqrt_price_output(
        curr_sqrt_price, liquidity, amount_rem, true
    );

    assert(amount_in == 99751242241780540438529824, 'comp_swap buy/out/cap in');
    assert(amount_out == 99256195800217286694524923, 'comp_swap buy/out/cap out');
    assert(next_sqrt_price == 10049875621120890270219264912, 'comp_swap buy/in/cap price');
    assert(next_sqrt_price == target_sqrt_price, 'comp_swap buy/out/cap target P');
    assert(next_sqrt_price < next_sqrt_price_full_amount, 'comp_swap buy/out/cap target Q');
    assert(amount_rem > amount_out, 'comp_swap buy/out/cap rem');
}

#[test]
fn test_compute_swap_amounts_buy_exact_input_filled_max() {
    let curr_sqrt_price = encode_sqrt_price(1, 1);
    let target_sqrt_price = encode_sqrt_price(1000, 100);
    let liquidity = to_e28_u128(2);
    let amount_rem = to_e28(1);

    let (amount_in, amount_out, next_sqrt_price) = compute_swap_amounts(
        curr_sqrt_price, target_sqrt_price, liquidity, amount_rem, true
    );
    let next_sqrt_price_full_amount = next_sqrt_price_input(
        curr_sqrt_price, liquidity, amount_rem, true
    );

    assert(amount_in == 10000000000000000000000000000, 'comp_swap buy/in/full in');
    assert(amount_out == 6666666666666666666666666666, 'comp_swap buy/in/full out');
    assert(next_sqrt_price == 15000000000000000000000000000, 'comp_swap buy/in/cap price');
    assert(next_sqrt_price < target_sqrt_price, 'comp_swap buy/in/full target P');
    assert(next_sqrt_price == next_sqrt_price_full_amount, 'comp_swap buy/in/full target Q');
}

#[test]
fn test_compute_swap_amounts_buy_exact_output_filled_max() {
    let curr_sqrt_price = encode_sqrt_price(1, 1);
    let target_sqrt_price = encode_sqrt_price(10000, 100);
    let liquidity = to_e28_u128(2);
    let amount_rem = to_e28(1);

    let (amount_in, amount_out, next_sqrt_price) = compute_swap_amounts(
        curr_sqrt_price, target_sqrt_price, liquidity, amount_rem, false
    );
    let next_sqrt_price_full_amount = next_sqrt_price_output(
        curr_sqrt_price, liquidity, amount_rem, true
    );

    assert(amount_in == 20000000000000000000000000000, 'comp_swap buy/out/full in');
    assert(amount_out == 10000000000000000000000000000, 'comp_swap buy/out/full out');
    assert(next_sqrt_price == 20000000000000000000000000000, 'comp_swap buy/out/full price');
    assert(next_sqrt_price < target_sqrt_price, 'comp_swap buy/out/full target P');
    assert(next_sqrt_price == next_sqrt_price_full_amount, 'comp_swap buy/out/full target Q');
    assert(amount_rem == amount_out, 'comp_swap buy/out/full rem');
}

#[test]
fn test_compute_swap_amounts_sell_exact_input_reached_price_target() {
    let curr_sqrt_price = 15000000000000000000000000000;
    let target_sqrt_price = to_e28(1);
    let liquidity = to_e28_u128(2);
    let amount_rem = to_e28(1);

    let (amount_in, amount_out, next_sqrt_price) = compute_swap_amounts(
        curr_sqrt_price, target_sqrt_price, liquidity, amount_rem, true
    );
    assert(amount_in == 6666666666666666666666666667, 'comp_swap sell/in/cap in');
    assert(amount_out == 10000000000000000000000000000, 'comp_swap sell/in/cap out');
    assert(next_sqrt_price == 10000000000000000000000000000, 'comp_swap sell/in/cap price');
}

#[test]
fn test_compute_swap_amounts_sell_exact_output_reached_price_target() {
    let curr_sqrt_price = to_e28(12) / 10;
    let target_sqrt_price = to_e28(1);
    let liquidity = to_e28_u128(2);
    let amount_rem = to_e28(1);

    let (amount_in, amount_out, next_sqrt_price) = compute_swap_amounts(
        curr_sqrt_price, target_sqrt_price, liquidity, amount_rem, false
    );
    assert(amount_in == 3333333333333333333333333334, 'comp_swap sell/out/cap in');
    assert(amount_out == 4000000000000000000000000000, 'comp_swap sell/out/cap out');
    assert(next_sqrt_price == 10000000000000000000000000000, 'comp_swap sell/out/cap price');
}

#[test]
fn test_compute_swap_amounts_sell_exact_input_filled_max() {
    let curr_sqrt_price = encode_sqrt_price(1000, 100);
    let target_sqrt_price = encode_sqrt_price(1, 1);
    let liquidity = to_e28_u128(2);
    let amount_rem = to_e28(1);

    let (amount_in, amount_out, next_sqrt_price) = compute_swap_amounts(
        curr_sqrt_price, target_sqrt_price, liquidity, amount_rem, true
    );
    assert(amount_in == 10000000000000000000000000000, 'comp_swap sell/in/full in');
    assert(amount_out == 38742588672279311066629784812, 'comp_swap sell/in/full out');
    assert(next_sqrt_price == 12251482265544137786674043038, 'comp_swap sell/in/full price');
}

#[test]
fn test_compute_swap_amounts_sell_exact_output_filled_max() {
    let curr_sqrt_price = to_e28(3);
    let target_sqrt_price = to_e28(1);
    let liquidity = to_e28_u128(2);
    let amount_rem = to_e28(1);

    let (amount_in, amount_out, next_sqrt_price) = compute_swap_amounts(
        curr_sqrt_price, target_sqrt_price, liquidity, amount_rem, false
    );
    assert(amount_in == 1333333333333333333333333334, 'comp_swap sell/out/full in');
    assert(amount_out == 10000000000000000000000000000, 'comp_swap sell/out/full out');
    assert(next_sqrt_price == 25000000000000000000000000000, 'comp_swap sell/out/full price');
}

#[test]
fn test_compute_swap_amounts_buy_exact_output_intermediate_insufficient_liquidity() {
    let curr_sqrt_price = 2560000000000000000000000000000;
    let target_sqrt_price = 2816000000000000000000000000000;
    let liquidity = 1024;
    let amount_rem = 4;

    let (amount_in, amount_out, next_sqrt_price) = compute_swap_amounts(
        curr_sqrt_price, target_sqrt_price, liquidity, amount_rem, false
    );

    assert(amount_in == 26215, 'comp_swap buy/out/iil in');
    assert(amount_out == 0, 'comp_swap buy/out/iil out');
    assert(next_sqrt_price == 2816000000000000000000000000000, 'comp_swap buy/out/iil price');
}

#[test]
fn test_compute_swap_amounts_sell_exact_output_intermediate_insufficient_liquidity() {
    let curr_sqrt_price = 2560000000000000000000000000000;
    let target_sqrt_price = 2304000000000000000000000000000;
    let liquidity = 1024;
    let amount_rem = 263000;

    let (amount_in, amount_out, next_sqrt_price) = compute_swap_amounts(
        curr_sqrt_price, target_sqrt_price, liquidity, amount_rem, false
    );

    assert(amount_in == 1, 'comp_swap sell/out/iil in');
    assert(amount_out == 26214, 'comp_swap sell/out/iil out');
    assert(next_sqrt_price == target_sqrt_price, 'comp_swap sell/out/iil price');
}

/////////////////////////////////////
// TESTS - next_sqrt_price_input
/////////////////////////////////////

#[test]
fn test_next_sqrt_price_in_cases() {
    let one: u128 = 10000000000000000000000000000;
    assert(
        next_sqrt_price_input(1, 1, BoundedInt::max(), false) == 1, 'next_sqrt_price_in amt max'
    );
    assert(next_sqrt_price_input(256, 100, 0, false) == 256, 'next_sqrt_price_in buy amt 0');
    assert(next_sqrt_price_input(256, 100, 0, true) == 256, 'next_sqrt_price_in sell amt_0');
    assert(
        next_sqrt_price_input(MAX, BoundedInt::max(), BoundedInt::max(), false) == 1,
        'next_sqrt_price_in all MAX'
    );
    assert(
        next_sqrt_price_input(ONE, one, ONE / 10, true) == 11000000000000000000000000000,
        'next_sqrt_price_in buy amt 0.1'
    );
    assert(
        next_sqrt_price_input(ONE, one, ONE / 10, false) == 9090909090909090909090909091,
        'next_sqrt_price_in sell amt 0.1'
    );
    assert(
        next_sqrt_price_input(ONE, 1, BoundedInt::max() / 2, false) == 1,
        'next_sqrt_price_in sell rtns 1'
    );
}

#[test]
#[should_panic(expected: ('PriceZero',))]
fn test_next_sqrt_price_in_price_0() {
    next_sqrt_price_input(0, 100, 1, true);
}

#[test]
#[should_panic(expected: ('LiqZero',))]
fn test_next_sqrt_price_in_liq_0() {
    next_sqrt_price_input(100, 0, 1, true);
}

#[test]
#[should_panic(expected: ('PriceOF',))]
fn test_next_sqrt_price_in_price_overflow() {
    next_sqrt_price_input(MAX, 1, 1, true);
}

/////////////////////////////////////
// TESTS - next_sqrt_price_output
/////////////////////////////////////

#[test]
fn test_next_sqrt_price_out_cases() {
    let one: u128 = 10000000000000000000000000000;
    assert(
        next_sqrt_price_output(to_e28(256), 1024, 262143, false) == 9765625000000000000000000,
        'next_sqrt_price_in_amt_max_1'
    );
    assert(next_sqrt_price_output(256, 100, 0, false) == 256, 'next_sqrt_price_out_buy_amt_0');
    assert(next_sqrt_price_output(256, 100, 0, true) == 256, 'next_sqrt_price_out_sell_amt_0');
    assert(
        next_sqrt_price_output(ONE, one, ONE / 10, true) == 11111111111111111111111111112,
        'next_sqrt_price_out_buy_0.1'
    );
    assert(
        next_sqrt_price_output(ONE, one, ONE / 10, false) == 9000000000000000000000000000,
        'next_sqrt_price_out_sell_0.1'
    );
}

#[test]
#[should_panic(expected: ('PriceZero',))]
fn test_next_sqrt_price_out_price_0() {
    next_sqrt_price_output(0, 100, 1, true);
}

#[test]
#[should_panic(expected: ('LiqZero',))]
fn test_next_sqrt_price_out_liq_0() {
    next_sqrt_price_output(100, 0, 1, true);
}

#[test]
#[should_panic(expected: ('PriceOF',))]
fn test_next_sqrt_price_out_buy_price_overflow() {
    next_sqrt_price_output(ONE, 1, BoundedInt::max(), true);
}

#[test]
#[should_panic(expected: ('MulDivOF',))]
fn test_next_sqrt_price_out_sell_price_overflow() {
    next_sqrt_price_output(ONE, 1, BoundedInt::max(), false);
}

#[test]
#[should_panic(expected: ('u256_sub Overflow',))]
fn test_next_sqrt_price_out_output_eq_quote_reserves() {
    next_sqrt_price_output(256, 1024, 262144, false);
}

#[test]
#[should_panic(expected: ('u256_sub Overflow',))]
fn test_next_sqrt_price_out_output_gt_quote_reserves() {
    next_sqrt_price_output(256, 1024, 262145, false);
}

#[test]
#[should_panic(expected: ('u256_sub Overflow',))]
fn test_next_sqrt_price_out_output_eq_base_reserves() {
    next_sqrt_price_output(256, 1024, 4, false);
}

#[test]
#[should_panic(expected: ('u256_sub Overflow',))]
fn test_next_sqrt_price_out_output_gt_base_reserves() {
    next_sqrt_price_output(256, 1024, 5, false);
}

