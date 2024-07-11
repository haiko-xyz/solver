// Core lib imports.
use core::cmp::{min, max};

// Local imports.
use haiko_solver_replicating::libraries::swap_lib;
use haiko_solver_core::types::{MarketState, PositionInfo, SwapParams};
use haiko_solver_replicating::types::MarketParams;

// Haiko imports.
use haiko_lib::math::{price_math, liquidity_math, math};
use haiko_lib::constants::{ONE, MAX_LIMIT_SHIFTED};
use haiko_lib::types::i32::{i32, I32Trait};

////////////////////////////////
// CONSTANTS
///////////////////////////////

pub const DENOMINATOR: u256 = 10000;

////////////////////////////////
// FUNCTIONS
///////////////////////////////

// Calculate virtual bid or ask position to execute swap over.
//
// # Arguments
// `is_bid` - whether to calculate bid or ask position
// `min_spread` - minimum spread to apply
// `delta` - inventory delta (+ve if ask spread, -ve if bid spread)
// `range` - position range
// `oracle_price` - current oracle price (base 10e28)
// `amount` - token amount in reserve
// 
// # Returns
// `position` - virtual liquidity position to execute swap over
pub fn get_virtual_position(
    is_bid: bool, lower_limit: u32, upper_limit: u32, amount: u256,
) -> PositionInfo {
    // Convert position range to sqrt prices.
    let lower_sqrt_price = price_math::limit_to_sqrt_price(lower_limit, 1);
    let upper_sqrt_price = price_math::limit_to_sqrt_price(upper_limit, 1);

    // Calculate liquidity.
    let liquidity = if is_bid {
        liquidity_math::quote_to_liquidity(lower_sqrt_price, upper_sqrt_price, amount, false)
    } else {
        liquidity_math::base_to_liquidity(lower_sqrt_price, upper_sqrt_price, amount, false)
    };

    // Return position.
    PositionInfo { lower_sqrt_price, upper_sqrt_price, liquidity }
}

// Calculate virtual bid or ask position to execute swap over.
//
// # Arguments
// `is_bid` - whether to calculate bid or ask position
// `min_spread` - minimum spread to apply
// `delta` - inventory delta (+ve if ask spread, -ve if bid spread)
//           note `delta` uses a custom i32 implementation that is [-4294967295, 4294967295]
// `range` - position range
// `oracle_price` - current oracle price (base 10e28)
// 
// # Returns
// `lower_limit` - virtual position lower limit
// `upper_limit` - virtual position upper limit
pub fn get_virtual_position_range(
    is_bid: bool, min_spread: u32, delta: i32, range: u32, oracle_price: u256
) -> (u32, u32) {
    // Start with the oracle price, and convert it to limits.
    assert(oracle_price != 0, 'OraclePriceZero');
    let mut limit = price_math::price_to_limit(oracle_price, 1, !is_bid);

    // Apply minimum spread.
    if is_bid {
        assert(limit >= min_spread, 'LimitUF');
        limit -= min_spread;
    } else {
        limit += min_spread;
    }

    // Apply delta.
    if delta.sign {
        assert(limit >= delta.val, 'LimitUF');
        limit -= delta.val;
    } else {
        limit += delta.val;
    }

    // Calculate position range.
    if is_bid {
        assert(limit >= range, 'LimitUF');
        (limit - range, limit)
    } else {
        assert(limit + range <= MAX_LIMIT_SHIFTED, 'LimitOF');
        (limit, limit + range)
    }
}

// Calculate the single-sided spread to add to either the bid or ask positions based on delta,
// i.e. the portfolio imbalance factor.
// 
// # Arguments
// `max_delta` - maximum allowed delta
// `base_reserves` - amount of base assets held in reserve by solver market
// `quote_reserves` - amount of quote assets held in reserve by solver market
// `price` - current price (base 10 ** 28)
//
// # Returns
// `delta` - inventory delta (+ve if ask spread, -ve if bid spread)
//           note `delta` uses a custom i32 implementation that is [-4294967295, 4294967295]
pub fn get_delta(max_delta: u32, base_reserves: u256, quote_reserves: u256, price: u256) -> i32 {
    let (skew, is_skew_bid) = get_skew(base_reserves, quote_reserves, price);
    let spread: u32 = math::mul_div(max_delta.into(), skew, DENOMINATOR, false).try_into().unwrap();

    // Constrain to width and return.
    I32Trait::new(spread, is_skew_bid)
}

// Calculate the portfolio skew of reserves in the market.
//
// # Arguments
// `base_reserves` - amount of base assets held in reserve by solver market
// `quote_reserves` - amount of quote assets held in reserve by solver market
// `price` - current price (base 10 ** 28)
//
// # Returns
// `skew` - portfolio skew, ranging from 0 (50:50) to 10000 (100:0)
// `is_skew_bid` - whether the skew is in the bid or ask direction
pub fn get_skew(base_reserves: u256, quote_reserves: u256, price: u256,) -> (u256, bool) {
    let base_in_quote = math::mul_div(base_reserves, price, ONE, false);
    let diff = max(base_in_quote, quote_reserves) - min(base_in_quote, quote_reserves);
    let sum = base_in_quote + quote_reserves;
    if sum == 0 {
        return (0, false);
    }
    let skew = math::mul_div(DENOMINATOR, diff, sum, false);
    let is_skew_bid = base_in_quote > quote_reserves;
    (skew, is_skew_bid)
}
