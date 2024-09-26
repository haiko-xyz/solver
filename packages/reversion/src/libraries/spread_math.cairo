// Core lib imports.
use core::cmp::{min, max};

// Local imports.
use haiko_solver_core::types::PositionInfo;
use haiko_solver_reversion::types::Trend;

// Haiko imports.
use haiko_lib::math::{price_math, liquidity_math, math};
use haiko_lib::constants::MAX_LIMIT_SHIFTED;

////////////////////////////////
// FUNCTIONS
///////////////////////////////

// Calculate virtual bid or ask position to execute swap over.
//
// # Arguments
// `is_bid` - whether to calculate bid or ask position
// `lower_limit` - lower limit price
// `upper_limit` - upper limit price
// `amount` - amount to swap
// 
// # Returns
// `position` - virtual liquidity position to execute swap over
pub fn get_virtual_position(
    is_bid: bool, lower_limit: u32, upper_limit: u32, amount: u256,
) -> PositionInfo {
    // Handle 0 case.
    if lower_limit == 0 && upper_limit == 0 {
        return Default::default();
    }

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
// In an uptrend, the ask position is always disabled, but we can still quote for ask side
// liquidity if the oracle price has fallen below the last cached price. Similarly, in a
// downtrend the bid position is always disabled, but we can still quote for bid side liquidity
// if the oracle price has risen above the last cached price. In a ranging market, we quote
// for both bid and ask sides as usual.
//
// # Arguments
// `trend` - current market trend
// `range` - position range
// `cached_price` - cached oracle price (base 10e28)
// `oracle_price` - current oracle price (base 10e28)
// 
// # Returns
// `bid_lower` - virtual bid lower limit
// `bid_upper` - virtual bid upper limit
// `ask_lower` - virtual ask lower limit
// `ask_upper` - virtual ask upper limit
pub fn get_virtual_position_range(
    trend: Trend, range: u32, cached_price: u256, oracle_price: u256
) -> (u32, u32, u32, u32) {
    assert(oracle_price != 0, 'OraclePriceZero');

    // Calculate position ranges on the new oracle price.
    let oracle_limit = price_math::price_to_limit(oracle_price, 1, false);
    assert(oracle_limit >= range, 'OracleLimitUF');
    let new_bid_lower = oracle_limit - range;
    let new_bid_upper = oracle_limit;
    let new_ask_lower = oracle_limit;
    let new_ask_upper = oracle_limit + range;

    // Handle special case. If cached price is unset, set it to the oracle price.
    let mut cached_price_set = cached_price;
    if cached_price == 0 {
        cached_price_set = oracle_price;
    }

    // Calculate position ranges on the cached price.
    let cached_limit = price_math::price_to_limit(cached_price_set, 1, false);
    assert(cached_limit >= range, 'CachedLimitUF');
    let bid_lower = cached_limit - range;
    let bid_upper = cached_limit;
    let ask_lower = cached_limit;
    let ask_upper = cached_limit + range;

    println!("oracle_limit: {}, cached_limit: {}", oracle_limit, cached_limit);
    println!(
        "new_bid_lower: {}, new_bid_upper: {}, new_ask_lower: {}, new_ask_upper: {}",
        new_bid_lower,
        new_bid_upper,
        new_ask_lower,
        new_ask_upper
    );
    println!(
        "bid_lower: {}, bid_upper: {}, ask_lower: {}, ask_upper: {}",
        bid_lower,
        bid_upper,
        ask_lower,
        ask_upper
    );

    // Otherwise, cap bid upper or ask lower at oracle price and apply conditions for 
    // quoting single sided liquidity.
    // A) If price is trending UP and:
    //   A1. oracle price > bid position, disable ask and recalculate bid ranges over new oracle price
    //   A2. oracle price < bid position, disable bid and quote for ask side liquidity over bid range
    //   A3. otherwise, quote for both bid and ask over bid range
    // B) If price is trending DOWN and:
    //   B1. oracle price < ask position, disable bid and recalculate ask ranges over new oracle price
    //   B2. oracle price > ask position, disable ask and quote for bid side liquidity over ask range
    //   B3. otherwise, quote for both bid and ask over ask range
    // If price is RANGING, quote for both bid and ask.
    // Note that if a position should be disabled, ranges are returned as 0.
    match trend {
        Trend::Up => {
            if new_bid_upper > bid_upper {
                println!("[case U1] new_bid_upper: {}, bid_upper: {}", new_bid_upper, bid_upper);
                (new_bid_lower, new_bid_upper, 0, 0)
            } else if new_bid_upper <= bid_lower {
                println!("[case U2] new_bid_upper: {}, bid_lower: {}", new_bid_upper, bid_lower);
                (0, 0, bid_lower, bid_upper)
            } else {
                // Handle special case: oracle limit + spread can exceed bid upper, so disable ask
                if new_ask_lower >= bid_upper {
                    println!(
                        "[case U3] new_bid_upper: {}, new_ask_lower: {}, bid_upper: {}",
                        new_bid_upper,
                        new_ask_lower,
                        bid_upper
                    );
                    (bid_lower, new_bid_upper, 0, 0)
                } else {
                    println!(
                        "[case U4] bid_lower: {}, new_bid_upper: {}, new_ask_lower: {}, bid_upper: {}",
                        bid_lower,
                        new_bid_upper,
                        new_ask_lower,
                        bid_upper
                    );
                    (bid_lower, new_bid_upper, new_ask_lower, bid_upper)
                }
            }
        },
        Trend::Down => {
            if new_ask_lower < ask_lower {
                println!("[case D1] new_ask_lower: {}, ask_lower: {}", new_ask_lower, ask_lower);
                (0, 0, new_ask_lower, new_ask_upper)
            } else if new_ask_lower >= ask_upper {
                println!("[case D2] new_ask_lower: {}, ask_upper: {}", new_ask_lower, ask_upper);
                (ask_lower, ask_upper, 0, 0)
            } else {
                // Handle special case: oracle limit - spread can be less than ask lower, disable bid
                if new_bid_upper <= ask_lower {
                    println!(
                        "[case D3] new_bid_upper: {}, ask_lower: {}", new_bid_upper, ask_lower
                    );
                    (0, 0, new_ask_lower, ask_upper)
                } else {
                    println!(
                        "[case D4] ask_lower: {}, ask_upper: {}, new_bid_upper: {}, new_ask_lower: {}",
                        ask_lower,
                        ask_upper,
                        new_bid_upper,
                        new_ask_lower
                    );
                    (ask_lower, new_bid_upper, new_ask_lower, ask_upper)
                }
            }
        },
        Trend::Range => {
            println!(
                "[case R] new_bid_lower: {}, new_bid_upper: {}, new_ask_lower: {}, new_ask_upper: {}",
                new_bid_lower,
                new_bid_upper,
                new_ask_lower,
                new_ask_upper
            );
            (new_bid_lower, new_bid_upper, new_ask_lower, new_ask_upper)
        },
    }
}
