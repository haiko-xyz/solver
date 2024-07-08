// Core lib imports.
use core::cmp::{min, max};

// Local imports.
use haiko_solver_core::types::PositionInfo;

// Haiko imports.
use haiko_lib::math::{price_math, liquidity_math, math};
use haiko_lib::constants::MAX_LIMIT_SHIFTED;
use haiko_lib::types::i32::{i32, I32Trait};

////////////////////////////////
// FUNCTIONS
///////////////////////////////

// Calculate virtual bid or ask position to execute swap over.
//
// # Arguments
// `is_bid` - whether to calculate bid or ask position
// `spread` - spread to apply to the oracle price
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
// `spread` - spread to apply to the oracle price
// `range` - position range
// `oracle_price` - current oracle price (base 10e28)
// 
// # Returns
// `lower_limit` - virtual position lower limit
// `upper_limit` - virtual position upper limit
pub fn get_virtual_position_range(
    is_bid: bool, spread: u32, range: u32, oracle_price: u256
) -> (u32, u32) {
    // Start with the oracle price, and convert it to limits.
    assert(oracle_price != 0, 'OraclePriceZero');
    let mut limit = price_math::price_to_limit(oracle_price, 1, !is_bid);

    // Apply minimum spread.
    if is_bid {
        assert(limit >= spread, 'LimitUF');
        limit -= spread;
    } else {
        limit += spread;
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