// Local imports.
use haiko_solver_reversion::types::{MarketParams, ModelParams, Trend};

pub fn default_market_params() -> MarketParams {
    MarketParams {
        fee_rate: 50,
        base_currency_id: 4543560, // ETH
        quote_currency_id: 1431520323, // USDC
        min_sources: 3,
        max_age: 600,
    }
}
pub fn new_market_params() -> MarketParams {
    MarketParams {
        fee_rate: 987,
        base_currency_id: 123456,
        quote_currency_id: 789012,
        min_sources: 10,
        max_age: 200,
    }
}

pub fn default_model_params() -> ModelParams {
    ModelParams { cached_price: 0, cached_decimals: 0, trend: Trend::Range, range: 1000, }
}
