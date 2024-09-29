# Test Cases

## Libraries

### `test_spread_math.cairo`

- `Success` Get virtual position (bid and ask for each)
  - Copy cases from replicating solver
  - Add case for `lower_limit = upper_limit = 0`
- `Success` Get virtual position range
  - Uptrend
    - Oracle price is outside (above) bid position
    - Oracle price is equal to cached price
    - Oracle price is inside bid position
    - Oracle price is at bid lower
    - Oracle price is outside (below) bid position
    - Cache price unset
  - Downtrend
    - Oracle price is outside (below) ask position
    - Oracle price is equal to cached price
    - Oracle price is inside ask position
    - Oracle price is at ask upper
    - Oracle price is outside (above) ask position
    - Cache price unset
  - Ranging (always quoted at latest price, ignore cached)
    - Oracle price is equal to cached price
    - Oracle price is greater than cached price
    - Oracle price is less than cached price

### `test_swap_lib.cairo`

- Copy from `replicating_solver`

### `test_store_packing.cairo`

- Base on `replicating_solver`

## Solver

### `test_deploy.cairo`

- Test deploy reversion solver initialises immutables

### `test_set_trend.cairo`

- `Success` Test new solver market has ranging trend by default
- `Success` Test set trend for solver market updates state
- `Success` Test set trend is callable by market owner
- `Success` Test set trend is callable by trend setter
- `Event` Test set trend emits event
- `Fail` Test set trend fails if market does not exist
- `Fail` Test set trend fails if trend unchanged
- `Fail` Test set trend fails if caller is not market owner

## `test_oracle.cairo`

- Copy from `replicating_solver`

## `test_trend_setter.cairo`

- `Success` Test changing trend setter works
- `Event` Test changing trend setter emits event
- `Fail` Test changing trend setter fails if not owner
- `Fail` Test changing trend setter fails if unchanged

## `test_market_params.cairo`

- `Success` Test setting market params updates immutables
- `Event` Test set market params emits event
- `Fail` Test set market params fails if not market owner
- `Fail` Test set market params fails if params unchanged
- `Fail` Test set market params fails if zero range
- `Fail` Test set market params fails if zero min sources
- `Fail` Test set market params fails if zero max age
- `Fail` Test set market params fails if zero base currency id
- `Fail` Test set market params fails if zero quote currency id

## `test_swap.cairo`

Static cases

- `Success` Swap over full range liquidity, no spread, price at 1
- `Success` Swap over full range liquidity, no spread, price at 0.1
- `Success` Swap over full range liquidity, no spread, price at 10
- `Success` Swap over concentrated liquidity, no spread, price at 1
- `Success` Swap over concentrated liquidity, 100 spread, price at 1
- `Success` Swap over concentrated liquidity, 50000 spread, price at 10
- `Success` Swap with liquidity exhausted
- `Success` Swap with very high oracle price
- `Success` Swap with very low oracle price
- `Success` Swap buy with capped at threshold sqrt price
- `Success` Swap sell with capped at threshold sqrt price
- `Success` Swap buy with capped at threshold amount
- `Success` Swap sell with capped at threshold amount
- `Event` Swap should emit event
- `Fail` Test swap fails if market uninitialised
- `Fail` Test swap fails if market paused
- `Fail` Test swap fails if not approved
- `Fail` Test swap fails if invalid oracle price
- `Fail` Test swap fails if zero amount
- `Fail` Test swap fails if zero min amount out
- `Fail` Swap buy with zero liquidity
- `Fail` Swap sell with zero liquidity
- `Fail` Swap buy below threshold amount
- `Fail` Swap sell below threshold amount
- `Fail` Swap buy in uptrend at cached price
- `Fail` Swap sell in downtrend at cached price
- `Fail` Swap sell when price is at virtual bid lower
- `Fail` Swap buy when price is at virutal ask upper
- `Fail` Test swap fails if limit overflows
- `Fail` Test swap fails if limit underflows
- `Fail` Test swap fails for non solver caller

Sequential cases

- `Success` In an uptrend, if price rises above last cached price, cached price is updated and price is quoted at latest oracle price
- `Success` In an uptrend, if price falls below last cached price and rises back to the same level, cached price is unchanged
- `Success` In an uptrend, if price falls below bid position, cached price is unchanged and no quote is available for sells
- `Success` In a downtrend, if price falls below last cached price, cached price is updated and price is quoted at latest oracle price
- `Success` In a downtrend, if price falls above last cached price and falls back to the same level, cached price is unchanged
- `Success` In a downtrend, if price rises above ask position, cached price is unchanged and no quote is available for buys
- `Success` In a ranging market, buying then selling is always quoted at latest oracle price
- `Success` If trend changes from up to ranging, price is quoted at latest oracle price rather even if cached price is stale
- `Success` If trend changes from down to ranging, price is quoted at latest oracle price even if cached price is stale
- `Success` Swap after trend change from uptrend to downtrend
- `Success` Swap after trend change from downtrend to uptrend
- `Success` Swap after trend change from ranging to uptrend
- `Success` Swap after trend change from ranging to downtrend
- `Fail` Swap sell exhausts bid liquidity and prevents further sell swaps (TODO)
- `Fail` Swap buy exhausts ask liquidity and prevents further buy swaps (TODO)
