use haiko_solver_core::contracts::mocks::mock_solver::MockMarketParams;
use haiko_solver_core::types::governor::GovernorParams;

pub fn default_market_params() -> MockMarketParams {
    MockMarketParams { foo: 1, bar: 2, }
}

pub fn new_market_params() -> MockMarketParams {
    MockMarketParams { foo: 999, bar: 888, }
}

pub fn default_governor_params() -> GovernorParams {
    GovernorParams { quorum: 5000, // 50%
     min_ownership: 1000, // 0.1%
     duration: 86400, }
}
