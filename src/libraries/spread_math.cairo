// Core lib imports.
use core::cmp::{min, max};

// Local imports.
use haiko_solver_replicating::libraries::swap_lib;
use haiko_solver_replicating::types::{
    replicating::{MarketState, MarketParams, PositionInfo}, solver::SwapParams
};

// Haiko imports.
use haiko_lib::math::{price_math, liquidity_math, math};
use haiko_lib::constants::ONE;
use haiko_lib::types::i32::{i32, I32Trait};

////////////////////////////////
// CONSTANTS
///////////////////////////////

pub const DENOMINATOR: u256 = 10000;

////////////////////////////////
// FUNCTIONS
///////////////////////////////

// Calculate the amounts swapped in and out.
//
// # Arguments
// `swap_params` - swap parameters
// `position` - virtual liquidity position to execute swap over
//
// # Returns
// `amount_in` - amount swapped in
// `amount_out` - amount swapped out
pub fn get_swap_amounts(swap_params: SwapParams, position: PositionInfo,) -> (u256, u256) {
    // Define start and target prices based on swap direction.
    let (start_sqrt_price, target_sqrt_price) = if swap_params.is_buy {
        (position.lower_sqrt_price, position.upper_sqrt_price)
    } else {
        (position.upper_sqrt_price, position.lower_sqrt_price)
    };
    // Compute swap amounts.
    swap_lib::compute_swap_amounts(
        start_sqrt_price,
        target_sqrt_price,
        position.liquidity,
        swap_params.amount,
        swap_params.exact_input,
    )
}

// Calculate virtual bid or ask position to execute swap over.
//
// # Arguments
// `is_bid` - whether to calculate bid or ask position
// `market_params` - market parameters  
// `oracle_price` - current oracle price (base 10e28)
// `delta` - inventory delta (+ve if ask spread, -ve if bid spread)
// `amount` - token amount in reserve
// 
// # Returns
// `position` - virtual liquidity position to execute swap over
pub fn get_virtual_position(
    is_bid: bool, market_params: MarketParams, oracle_price: u256, delta: i32, amount: u256,
) -> PositionInfo {
    // Start with the oracle price, and convert it to limits.
    let mut limit = price_math::price_to_limit(oracle_price, 1, !is_bid);

    // Apply minimum spread.
    if is_bid {
        limit -= market_params.min_spread;
    } else {
        limit += market_params.min_spread;
    }

    // Apply delta.
    if delta.sign {
        limit -= delta.val;
    } else {
        limit += delta.val;
    }

    // Calculate position range.
    let (lower_sqrt_price, upper_sqrt_price) = if is_bid {
        (
            price_math::limit_to_sqrt_price(limit - market_params.range, 1),
            price_math::limit_to_sqrt_price(limit, 1)
        )
    } else {
        (
            price_math::limit_to_sqrt_price(limit, 1),
            price_math::limit_to_sqrt_price(limit + market_params.range, 1)
        )
    };

    // Calculate liquidity.
    let liquidity = if is_bid {
        liquidity_math::quote_to_liquidity(lower_sqrt_price, upper_sqrt_price, amount, false)
    } else {
        liquidity_math::base_to_liquidity(lower_sqrt_price, upper_sqrt_price, amount, false)
    };

    // Return position.
    PositionInfo { lower_sqrt_price, upper_sqrt_price, liquidity }
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
// `inv_delta` - inventory delta (+ve if ask spread, -ve if bid spread)
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
    let skew = math::mul_div(diff, DENOMINATOR, base_in_quote + quote_reserves, false);
    let is_skew_bid = base_in_quote < quote_reserves;
    (skew, is_skew_bid)
}
