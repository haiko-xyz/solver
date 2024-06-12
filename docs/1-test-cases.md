# Test Cases

## Libraries

### `test_spread_math.cairo`

Get virtual position

- `Success` Test get virtual position (bid and ask for each)
  - Zero amount
  - Very small amount
  - Very large amount
  - Lowest limits
  - Highest limits

Get virtual position range

- `Success` Test get virtual position (bid and ask for each)
  - No min spread, no delta, range 1
  - 500 min spread, no delta, range 1000
  - 100000 min spread, no delta, range 1000
  - Max min spread (7905625), no delta, range 1000
  - 500 min spread, 100 bid delta, range 1000
  - 500 min spread, 100 ask delta, range 1000
  - 500 min spread, 5000 bid delta, range 1000
  - 500 min spread, 5000 ask delta, range 1000
  - 500 min spread, max bid delta (7905125), range 1000
  - 500 min spread, max ask delta (7905125), range 1000
  - 500 min spread, no delta, range 1000, very small oracle price (1)
  - 500 min spread, no delta, range 1000, very large oracle price (u256_max)
- `Fail` Limit underflow is caught for bid position
- `Fail` Limit overflow is caught for ask position
- `Fail` Oracle price 0 should throw as invalid
- `Fail` Oracle price overflow is properly handled

Get delta

- Entirely bid
- Entirely ask
- Small token values
- Large token values

### `test_swap_lib.cairo`

- Test get swap amounts
  - `Success` Test swap amount
  - `Success` Test swap amount over zero liquidity
  - `Success` Test cap at threshold price for buy works
  - `Success` Test cap at threshold price for sell works
  - `Fail` Test cap at threshold price below lower price for buy fails
  - `Fail` Test cap at threshold price above upper price for sell fails
- Test compute swap amounts
  - Copy over test cases from `amm` repo

### `test_id.cairo`

- `Success` Test market id

## Solver

### `test_deploy.cairo`

- `Success` Test deploy solver initialises immutables
- `Success` Test deploy vault token initialises immutables

### `test_create_market.cairo`

- `Success` Test create public market initialises immutables and deploys vault token
- `Success` Test create private market initialises immutables
- `Success` Test create public market with empty owner works
- `Event` Test create market emits event
- `Fail` Test create market with empty base token fails
- `Fail` Test create market with empty quote token fails
- `Fail` Test create market with empty owner fails
- `Fail` Test create market with empty base currency id fails
- `Fail` Test create market with empty quote currency id fails
- `Fail` Test create market with 0 min sources fails
- `Fail` Test create market with 0 max age fails
- `Fail` Test create market with zero range fails
- `Fail` Test create duplicate market fails

### `test_deposit_initial.cairo`

- `Success` Test deposit initial public both tokens
- `Success` Test deposit initial public base token only
- `Success` Test deposit initial public quote token only
- `Success` Test deposit initial private both tokens
- `Success` Test deposit initial private base token only
- `Success` Test deposit initial private quote token only
- `Success` Test deposit initial with mismatched token decimals works
- `Event` Test deposit initial emits event
- `Event` Test deposit initial with referrer emits event
- `Fail` Test deposit initial with both zero amount fails
- `Fail` Test deposit initial uninitialised market fails
- `Fail` Test deposit initial on market with existing deposits fails
- `Fail` Test deposit initial fails if market paused
- `Fail` Test deposit initial fails on private market for non-owner caller
- `Fail` Test deposit initial fails if not approved
- `Fail` Test deposit initial fails if invalid oracle price
- `Fail` Test deposit initial fails if it exceeds max skew

### `test_deposit.cairo`

- `Success` Test deposit both tokens at ratio (public vault)
- `Success` Test deposit at above base ratio correctly coerces to ratio (public vault)
- `Success` Test deposit at above quote ratio correctly coerces to ratio (public vault)
- `Success` Test deposit more than available correctly caps at balance (public vault)
- `Success` Test deposit base token only, single sided ask liquidity (public vault)
- `Success` Test deposit quote token only, single sided bid liquidity (public vault)
- `Success` Test deposit both tokens at arbitrary ratio (private vault)
- `Success` Test deposit base token only (private vault)
- `Success` Test deposit quote token only (private vault)
- `Success` Test deposit above max skew that improves skew is allowed (private vault)
- `Event` Test deposit emits event
- `Event` Test deposit with referrer emits event
- `Fail` Test deposit base and quote amounts zero
- `Fail` Test deposit market uninitialised
- `Fail` Test deposit no existing deposits
- `Fail` Test deposit market paused
- `Fail` Test deposit private market for non-owner caller
- `Fail` Test deposit not approved
- `Fail` Test deposit invalid oracle price
- `Fail` Test deposit fails if it exceeds max skew (private vault)

### `test_swap_and_quoting.cairo`

- `Success` Swap over full range liquidity, no spread, price at 1
- `Success` Swap over full range liquidity, no spread, price at 0.1
- `Success` Swap over full range liquidity, no spread, price at 10
- `Success` Swap over concentrated liquidity, no spread, price at 1
- `Success` Swap over concentrated liquidity, 100 spread, price at 1
- `Success` Swap over concentrated liquidity, 50000 spread, price at 10
- `Success` Swap over concentrated liquidity, 100 spread, price at 1, 500 max delta
- `Success` Swap over concentrated liquidity, 100 spread, price at 0.1, 20000 max delta
- `Success` Swap with liquidity exhausted
- `Success` Swap with very high oracle price
- `Success` Swap with very low oracle price
- `Success` Swap buy with capped at threshold sqrt price
- `Success` Swap sell with capped at threshold sqrt price
- `Success` Swap buy with capped at threshold amount
- `Success` Swap sell with capped at threshold amount
- `Success` Test swap above max skew that improves skew is allowed
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
- `Fail` Test swap fails if limit overflows
- `Fail` Test swap fails if limit underflows
- `Fail` Test swap buy above max skew is disallowed
- `Fail` Test swap sell above max skew is disallowed
- `Fail` Test change in oracle price above max skew prevents swap

### `test_withdraw.cairo`

Public vault

- `Success` Test withdraw partial shares (public vault)
- `Success` Test withdraw all remaining shares from vault (public vault)
- `Success` Test withdraw allowed even if paused (public vault)
- `Event` Test withdraw emits event (public vault)
- `Fail` Test withdraw zero shares (public vault)
- `Fail` Test withdraw more shares than available (public vault)
- `Fail` Test withdraw market uninitialised (public vault)
- `Fail` Test withdraw custom amounts fails for public vault

Private vault

- `Success` Test withdraw partial amounts (private vault)
- `Success` Test withdraw base only (private vault)
- `Success` Test withdraw quote only (private vault)
- `Success` Test withdraw all remaining shares from vault should set shares to 0 (private vault)
- `Success` Test withdraw more than available correctly caps amount (private vault)
- `Event` Test withdraw emits event (private vault)
- `Fail` Test withdraw zero amounts (private vault)
- `Fail` Test withdraw market uninitialised (private vault)
- `Fail` Test withdraw custom amounts fails if max skew exceeded for private vault

### `test_set_market_params.cairo`

- `Success` Test setting market params updates immutables
- `Success` Test set market params emits event
- `Fail` Test set market params fails if not market owner
- `Fail` Test set market params fails if params unchanged
- `Fail` Test set market params fails if zero range
- `Fail` Test set market params fails if zero min sources
- `Fail` Test set market params fails if zero max age
- `Fail` Test set market params fails if zero base currency id
- `Fail` Test set market params fails if zero quote currency id

### `test_oracle.cairo`

- `Success` Test changing oracle works
- `Event` Test changing oracle emits event
- `Fail` Test changing oracle fails if not owner
- `Fail` Test changing oracle fails if unchanged

### `test_vault_token.cairo`

- `Success` Change vault token class works
- `Event` Change vault token class emits event
- `Fail` Change vault token class fails if not owner
- `Fail` Change vault token class fails if unchanged
- `Fail` Change vault token class fails if zero address
- `Fail` Change mint vault token fails from non-owner
- `Fail` Change burn vault token fails from non-owner

### `test_withdraw_fees.cairo`

- `Success` Test set withdraw fees
- `Success` Test collect withdraw fees
- `Event` Test set withdraw fees emits event
- `Event` Test collect withdraw fees emits event
- `Fail` Test set withdraw fee overflow
- `Fail` Test set withdraw fee unchanged
- `Fail` Test set withdraw fee not owner

### `test_pause.cairo`

- `Success` Test pause allows withdraws
- `Success` Test unpause after pause reenables deposits and withdrawals
- `Event` Test pause emits event
- `Event` Test unpause emits event
- `Fail` Test pause prevents non-owner deposits
- `Fail` Test pause prevents owner deposits
- `Fail` Test pause fails if already paused
- `Fail` Test unpause fails if already unpaused

### `test_ownership.cairo`

- `Success` Test transfer ownership works
- `Success` Test transfer then update owner before accepting works
- `Event` Test transfer ownership emits event
- `Fail` Test transfer ownership fails if unchanged
- `Fail` Test transfer ownership fails if not owner
- `Fail` Test transfer ownership fails if accepting from an address that is not new owner

### `test_balances.cairo`

- `Success` Test get balances works
- `Success` Test get balances array works
- `Success` Test get user balances array works

### `test_upgrade.cairo`

- `Success` Test upgrade works
