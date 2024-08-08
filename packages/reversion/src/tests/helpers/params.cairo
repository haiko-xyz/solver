// Local imports.
use haiko_solver_reversion::types::MarketParams;

pub fn default_market_params() -> MarketParams {
    MarketParams {
        spread: 50,
        range: 1000,
        base_currency_id: 4543560, // ETH
        quote_currency_id: 1431520323, // USDC
        min_sources: 3,
        max_age: 600,
    }
}
