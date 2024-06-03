# Test Cases

## Libraries

### `test_spread_math.cairo`

- `Success` Test compute swap amounts
  - Copy over test cases from `amm` repo
- `Success` Test get virtual position
  - No min spread, no delta, range 1
  - Various values for min spread, no delta, range 1
  - Max min spread, no delta, range 1
  - Min spread, bid delta, range 1 (positions should never overlap)
  - Min spread, ask delta, range 1 (positions should never overlap)
  - Min spread, entirely bid, range 1
  - Min spread, entirely ask, range 1
  - Min spread, small token values, range 1
  - Min spread, large token values, range 1
  - Min spread, max delta, range 1
  - Min spread, bid delta, range 1000
  - Min spread, ask delta, range 1000
  - Very small oracle price
  - Very large oracle price
- `Fail` Limit overflow is caught for bid position
- `Fail` Limit underflow is caught for ask position
- `Fail` Oracle price underflow is properly handled
- `Fail` Oracle price 0 should throw as invalid
- `Fail` Oracle price overflow is properly handled

### `test_swap_lib.cairo`

- Copy over test cases from `amm` repo

### `test_id.cairo`

- `Success` Test market id

## Solver

### `test_deploy.cairo`

- `Success` Test deploy solver initialises immutables
- `Success` Test deploy vault token initialises immutables

### `test_create_market.cairo`

- `Success` Test create market initialises immutables
- `Success` Test create market deploys vault token
- `Success` Test create private market works
- `Success` Test create public market works
- `Success` Test create market with empty owner works
- `Success` Test create market with 0 min sources an max age works
- `Success` Test create market emits event
- `Fail` Test create market with empty base token fails
- `Fail` Test create market with empty quote token fails
- `Fail` Test create market with zero range fails
- `Fail` Test create duplicate market fails

### `test_vault_token.cairo`

- `Success` Change vault token class works
- `Success` Change vault token class emits event
- `Fail` Change vault token class fails if not owner
- `Fail` Change vault token class fails if unchanged
- `Fail` Change vault token class fails if zero address

### `test_deposit_initial.cairo`

- `Success` Test deposit initial both tokens
- `Success` Test deposit initial base token only
- `Success` Test deposit initial quote token only
- `Success` Test deposit initial with mismatched token decimals works
- `Success` Test deposit initial emits event
- `Success` Test deposit initial with referrer emits event
- `Fail` Test deposit initial with both zero amount fails
- `Fail` Test deposit initial uninitialised market fails
- `Fail` Test deposit initial on market with existing deposits fails
- `Fail` Test deposit initial fails if market paused
- `Fail` Test deposit initial fails on private market for non-owner caller
- `Fail` Test deposit initial fails if not approved
- `Fail` Test deposit initial fails if invalid oracle price

### `test_deposit.cairo`

- `Success` Test deposit both tokens at ratio (public vault)
- `Success` Test deposit base token only, single sided ask liquidity (public vault)
- `Success` Test deposit quote token only, single sided bid liquidity (public vault)
- `Success` Test deposit more than available base correctly caps at balance (public vault)
- `Success` Test deposit more than available quote correctly caps at balance (public vault)
- `Success` Test deposit at above base ratio correctly coerces to ratio (public vault)
- `Success` Test deposit at above quote ratio correctly coerces to ratio (public vault)
- `Success` Test multiple deposits (public vault)
- `Success` Test deposit both tokens (private vault)
- `Success` Test deposit base token only (private vault)
- `Success` Test deposit quote token only (private vault)
- `Success` Test multiple deposits (private vault)
- `Success` Test deposit emits event
- `Success` Test deposit with referrer emits event
- `Fail` Test deposit base and quote amounts zero
- `Fail` Test deposit not approved
- `Fail` Test deposit market uninitialised
- `Fail` Test deposit no existing deposits
- `Fail` Test deposit market paused
- `Fail` Test deposit private market for non-owner caller

### `test_swap_and_quoting.cairo`

- Loop through test cases and check quote and swap outputs match expected amount (build model)
- Swap should emit event
- TODO: add tests for threshold sqrt price (copy from `aam` repo?)
- TODO: add tests for threshold amount (copy from `aam` repo?)
- `Fail` Test swap fails if market uninitialised
- `Fail` Test swap fails if market paused
- `Fail` Test swap fails if not approved
- `Fail` Test swap fails if invalid oracle price
- `Fail` Test swap fails if zero amount
- `Fail` Test swap fails if zero min amount out

### `test_withdraw.cairo`

Public vault

- `Success` Test withdraw partial shares (public vault)
- `Success` Test withdraw all remaining shares from vault (public vault)
- `Success` Test withdraw allowed even if paused (public vault)
- `Success` Test withdraw emits event (public vault)
- `Fail` Test withdraw zero shares (public vault)
- `Fail` Test withdraw more shares than available (public vault)
- `Fail` Test withdraw market uninitialised (public vault)
- `Fail` Test withdraw custom amounts (public vault)

Private vault

- `Success` Test withdraw partial amounts (private vault)
- `Success` Test withdraw all remaining shares from vault should set shares to 0 (private vault)
- `Success` Test withdraw custom amounts (private vault)
- `Success` Test withdraw more than available correctly caps amount (private vault)
- `Success` Test withdraw emits event (private vault)
- `Fail` Test withdraw zero amounts (private vault)
- `Fail` Test withdraw market uninitialised (private vault)

### `test_strategy_params.cairo`

- `Success` Test setting strategy params updates immutables
- `Success` Test set strategy params emits event
- `Fail` Test set strategy params fails if not strategy owner
- `Fail` Test set strategy params fails if params unchanged
- `Fail` Test set strategy params fails if zero range

### `test_oracle.cairo`

- `Success` Test changing oracle works
- `Fail` Test changing oracle fails if not owner
- `Fail` Test changing oracle fails if unchanged

### `test_withdraw_fees.cairo`

- `Success` Test setting withdraw fees, depositing and withdrawing, and collecting fees
- `Fail` Test set withdraw fee overflow
- `Fail` Test set withdraw fee unchanged
- `Fail` Test set withdraw fee not owner

### `test_pause.cairo`

- `Success` Test pause allows withdraws
- `Success` Test unpause after pause reenables deposits and withdrawals
- `Fail` Test pause prevents non-owner deposits
- `Fail` Test pause prevents owner deposits
- `Fail` Test pause fails if already paused

### `test_ownership.cairo`

- `Success` Test transfer ownership works
- `Success` Test transfer then update owner before accepting works
- `Success` Test transfer ownership emits event
- `Fail` Test transfer ownership fails if not owner
- `Fail` Test transfer ownership fails if accepting from an address that is not new owner

### `test_balances.cairo`

- `Success` Test get balances works
- `Success` Test get balances array works
- `Success` Test get user balances array works

### `test_upgrade.cairo`

- `Success` Test upgrade works
