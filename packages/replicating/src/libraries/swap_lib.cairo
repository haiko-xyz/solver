// Core lib imports.
use core::cmp::{min, max};
use core::integer::{u512, u256_wide_mul};

// Local imports.
use haiko_solver_core::types::{MarketState, PositionInfo, SwapParams};

// Haiko imports.
use haiko_lib::math::{math, fee_math, liquidity_math};
use haiko_lib::constants::{ONE, MAX_SQRT_PRICE};
use haiko_lib::types::i128::I128Trait;

// Calculate the amounts swapped in and out. Wrapper around `compute_swap_amounts`.
//
// # Arguments
// `swap_params` - swap parameters
// `fee_rate` - fee rate
// `position` - virtual liquidity position to execute swap over
//
// # Returns
// `amount_in` - amount swapped in including fees
// `amount_out` - amount swapped out
// `fees` - amount of fees
pub fn get_swap_amounts(
    swap_params: SwapParams, fee_rate: u16, position: PositionInfo,
) -> (u256, u256, u256) {
    // Define start and target prices based on swap direction.
    let start_sqrt_price = if swap_params.is_buy {
        position.lower_sqrt_price
    } else {
        position.upper_sqrt_price
    };
    let target_sqrt_price = if swap_params.is_buy {
        if swap_params.threshold_sqrt_price.is_some() {
            let threshold = swap_params.threshold_sqrt_price.unwrap();
            assert(threshold > position.lower_sqrt_price, 'ThresholdInvalid');
            min(position.upper_sqrt_price, threshold)
        } else {
            position.upper_sqrt_price
        }
    } else {
        if swap_params.threshold_sqrt_price.is_some() {
            let threshold = swap_params.threshold_sqrt_price.unwrap();
            assert(threshold < position.upper_sqrt_price, 'ThresholdInvalid');
            max(position.lower_sqrt_price, threshold)
        } else {
            position.lower_sqrt_price
        }
    };

    // Compute swap amounts.
    let (net_amount_in, amount_out, fees, next_sqrt_price) = compute_swap_amounts(
        start_sqrt_price,
        target_sqrt_price,
        position.liquidity,
        swap_params.amount,
        fee_rate,
        swap_params.exact_input,
    );

    // If liquidity is sufficient to fill entire swap amount, we want to make sure the
    // requested amount is fully consumed for exact input case. 
    let amount_in = if next_sqrt_price != target_sqrt_price
        && position.liquidity != 0
        && swap_params.exact_input {
        swap_params.amount
    } else {
        net_amount_in + fees
    };

    (amount_in, amount_out, fees)
}

// Compute amounts swapped and new price after swapping between two prices.
//
// # Arguments
// * `curr_sqrt_price` - current sqrt price
// * `target_sqrt_price` - target sqrt price
// * `liquidity` - current liquidity
// * `amount` - amount remaining to be swapped
// * `fee_rate` - fee rate
// * `exact_input` - whether swap amount is exact input or output
//  
// # Returns
// * `net_amount_in` - net amount of tokens swapped in
// * `amount_out` - amount of tokens swapped out
// * `fee_amount` - amount of fees
// * `next_sqrt_price` - next sqrt price
pub fn compute_swap_amounts(
    curr_sqrt_price: u256,
    target_sqrt_price: u256,
    liquidity: u128,
    amount: u256,
    fee_rate: u16,
    exact_input: bool,
) -> (u256, u256, u256, u256) {
    // Determine whether swap is a buy or sell.
    let is_buy = target_sqrt_price > curr_sqrt_price;

    // Calculate amounts in and out.
    // We round up amounts in and round down amounts out to prevent protocol insolvency.
    let liquidity_i128 = I128Trait::new(liquidity, false);
    let mut amount_in = if is_buy {
        liquidity_math::liquidity_to_quote(curr_sqrt_price, target_sqrt_price, liquidity_i128, true)
    } else {
        liquidity_math::liquidity_to_base(target_sqrt_price, curr_sqrt_price, liquidity_i128, true)
    }
        .val;

    let mut amount_out = if is_buy {
        liquidity_math::liquidity_to_base(curr_sqrt_price, target_sqrt_price, liquidity_i128, false)
    } else {
        liquidity_math::liquidity_to_quote(
            target_sqrt_price, curr_sqrt_price, liquidity_i128, false
        )
    }
        .val;

    // Calculate next sqrt price.
    let amount_less_fee = fee_math::gross_to_net(amount, fee_rate);
    let filled_max = if exact_input {
        amount_less_fee < amount_in
    } else {
        amount < amount_out
    };

    let next_sqrt_price = if !filled_max {
        target_sqrt_price
    } else {
        if exact_input {
            next_sqrt_price_input(curr_sqrt_price, liquidity, amount_less_fee, is_buy)
        } else {
            next_sqrt_price_output(curr_sqrt_price, liquidity, amount, is_buy)
        }
    };

    // At this point, amounts in and out are assuming target price was reached.
    // If that isn't the case, recalculate amounts using next sqrt price.
    // Rounding applied as above.
    if filled_max {
        amount_in =
            if exact_input {
                amount_less_fee
            } else {
                if is_buy {
                    liquidity_math::liquidity_to_quote(
                        curr_sqrt_price, next_sqrt_price, liquidity_i128, true
                    )
                } else {
                    liquidity_math::liquidity_to_base(
                        next_sqrt_price, curr_sqrt_price, liquidity_i128, true
                    )
                }
                    .val
            };
        amount_out =
            if !exact_input {
                amount
            } else {
                if is_buy {
                    liquidity_math::liquidity_to_base(
                        curr_sqrt_price, next_sqrt_price, liquidity_i128, false
                    )
                } else {
                    liquidity_math::liquidity_to_quote(
                        next_sqrt_price, curr_sqrt_price, liquidity_i128, false
                    )
                }
                    .val
            };
    }

    // Calculate fees. 
    // Amount in is net of fees because we capped amounts by net amount remaining.
    // Fees are rounded down by default to prevent overflow when transferring amounts.
    // Note that in Uniswap, if target price is not reached, LP takes the remainder 
    // of the maximum input as fee. We don't do that here.
    let fees = fee_math::net_to_fee(amount_in, fee_rate);

    // Return amounts.
    (amount_in, amount_out, fees, next_sqrt_price)
}

// Calculates next sqrt price after swapping in certain amount of tokens at given starting 
// sqrt price and liquidity.
//
// # Arguments
// * `curr_sqrt_price` - current sqrt price
// * `liquidity` - current liquidity
// * `amount_in` - amount of tokens to swap in
// * `is_buy` - whether swap is a buy or sell
//
// # Returns
// * `next_sqrt_price` - next sqrt price
pub fn next_sqrt_price_input(
    curr_sqrt_price: u256, liquidity: u128, amount_in: u256, is_buy: bool,
) -> u256 {
    // Input validation.
    assert(curr_sqrt_price != 0, 'PriceZero');
    assert(liquidity != 0, 'LiqZero');

    if is_buy {
        // Buy case: sqrt_price + amount * ONE / liquidity.
        // Round down to avoid overflow near max price.
        let next = curr_sqrt_price + math::mul_div(amount_in, ONE, liquidity.into(), false);
        assert(next <= MAX_SQRT_PRICE, 'PriceOF');
        next
    } else {
        // Sell case: switches between a more precise and less precise formula depending on overflow.
        // Round up to avoid underflow near min price.
        if amount_in == 0 {
            return curr_sqrt_price;
        }
        let product: u512 = u256_wide_mul(amount_in, curr_sqrt_price);
        if product.limb2 == 0 && product.limb3 == 0 {
            // Case 1 (more precise): 
            // liquidity * sqrt_price / (liquidity + (amount_in * sqrt_price / ONE))
            let product = u256 { low: product.limb0, high: product.limb1 };
            math::mul_div(liquidity.into(), curr_sqrt_price, liquidity.into() + product / ONE, true)
        } else {
            // Case 2 (less precise): 
            // liquidity * ONE / ((liquidity * ONE / sqrt_price) + amount_in)   
            math::mul_div(
                liquidity.into(),
                ONE,
                math::mul_div(liquidity.into(), ONE, curr_sqrt_price, false) + amount_in,
                true
            )
        }
    }
}

// Calculates next sqrt price after swapping out certain amount of tokens at given starting sqrt price 
// and liquidity.
//
// # Arguments
// * `curr_sqrt_price` - current sqrt price
// * `liquidity` - current liquidity
// * `amount_out` - amount of tokens to swap out
// * `is_buy` - whether swap is a buy or sell
//
// # Returns
// * `next_sqrt_price` - next sqrt price
pub fn next_sqrt_price_output(
    curr_sqrt_price: u256, liquidity: u128, amount_out: u256, is_buy: bool,
) -> u256 {
    // Input validation.
    assert(curr_sqrt_price != 0, 'PriceZero');
    assert(liquidity != 0, 'LiqZero');

    if is_buy {
        // Buy case: liquidity * sqrt_price / (liquidity - (amount_out * sqrt_price / ONE))
        let product_wide: u512 = u256_wide_mul(amount_out, curr_sqrt_price);
        let product = math::mul_div(amount_out, curr_sqrt_price, ONE, true);
        assert(
            product_wide.limb2 == 0 && product_wide.limb3 == 0 && liquidity.into() > product,
            'PriceOF'
        );
        math::mul_div(liquidity.into(), curr_sqrt_price, liquidity.into() - product, true)
    } else {
        // Sell case: sqrt_price - amount * ONE / liquidity
        curr_sqrt_price - math::mul_div(amount_out, ONE, liquidity.into(), true)
    }
}
