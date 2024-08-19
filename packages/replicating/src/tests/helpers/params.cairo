// Local imports.
use haiko_solver_replicating::types::MarketParams;
use haiko_solver_core::types::governor::GovernorParams;

pub fn default_market_params() -> MarketParams {
    MarketParams {
        min_spread: 50,
        range: 1000,
        max_delta: 500,
        max_skew: 7500,
        base_currency_id: 4543560, // ETH
        quote_currency_id: 1431520323, // USDC
        min_sources: 3,
        max_age: 600,
    }
}

pub fn new_market_params() -> MarketParams {
    MarketParams {
        min_spread: 987,
        range: 12345,
        max_delta: 676,
        max_skew: 9989,
        base_currency_id: 123456,
        quote_currency_id: 789012,
        min_sources: 10,
        max_age: 200,
    }
}

pub fn default_governor_params() -> GovernorParams {
    GovernorParams { quorum: 5000, // 50%
     min_ownership: 1000, // 0.1%
     duration: 86400, }
}
