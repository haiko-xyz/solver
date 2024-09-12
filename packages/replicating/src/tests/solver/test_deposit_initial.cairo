// Core lib imports.
use starknet::contract_address_const;

// Local imports.
use haiko_solver_core::interfaces::ISolver::{ISolverDispatcher, ISolverDispatcherTrait};
use haiko_solver_replicating::{
    contracts::mocks::mock_pragma_oracle::{
        IMockPragmaOracleDispatcher, IMockPragmaOracleDispatcherTrait
    },
    interfaces::{
        IReplicatingSolver::{IReplicatingSolverDispatcher, IReplicatingSolverDispatcherTrait},
    },
    types::MarketParams,
    tests::{
        helpers::{
            actions::{deploy_replicating_solver, deploy_mock_pragma_oracle},
            params::default_market_params,
            utils::{before, before_custom_decimals, before_skip_approve, snapshot},
        },
    },
};

// Haiko imports.
use haiko_lib::helpers::params::{owner, alice};
use haiko_lib::helpers::utils::{to_e18, approx_eq_pct};

// External imports.
use snforge_std::{
    start_prank, start_warp, declare, spy_events, SpyOn, EventSpy, EventAssertions, CheatTarget
};
use openzeppelin::token::erc20::interface::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};

////////////////////////////////
// TESTS - Success cases
////////////////////////////////

#[test]
fn test_deposit_initial_public_both_tokens() {
    let (base_token, quote_token, _oracle, _vault_token_class, solver, market_id, vault_token_opt) =
        before(
        true
    );

    // Snapshot before.
    let vault_token = vault_token_opt.unwrap();
    let bef = snapshot(solver, market_id, base_token, quote_token, vault_token, owner());

    // Deposit initial.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let base_amount = to_e18(100);
    let quote_amount = to_e18(500);
    let dep_init = solver.deposit_initial(market_id, base_amount, quote_amount);

    // Snapshot after.
    let aft = snapshot(solver, market_id, base_token, quote_token, vault_token, owner());

    // Run checks.
    assert(dep_init.base_amount == base_amount, 'Base deposit');
    assert(dep_init.quote_amount == quote_amount, 'Quote deposit');
    assert(dep_init.shares != 0, 'Shares');
    assert(aft.lp_base_bal == bef.lp_base_bal - base_amount, 'LP base bal');
    assert(aft.lp_quote_bal == bef.lp_quote_bal - quote_amount, 'LP quote bal');
    assert(aft.vault_lp_bal == bef.vault_lp_bal + dep_init.shares, 'LP shares');
    assert(aft.vault_total_bal == bef.vault_total_bal + dep_init.shares, 'LP total shares');
    assert(aft.market_state.base_reserves == base_amount, 'Base reserve');
    assert(aft.market_state.quote_reserves == quote_amount, 'Quote reserve');
    assert(
        aft.bid.lower_sqrt_price != 0 && aft.bid.upper_sqrt_price != 0 && aft.bid.liquidity != 0,
        'Bid'
    );
    assert(
        aft.ask.lower_sqrt_price != 0 && aft.ask.upper_sqrt_price != 0 && aft.ask.liquidity != 0,
        'Ask'
    );
}

#[test]
fn test_deposit_initial_public_base_token_only() {
    let (base_token, quote_token, _oracle, _vault_token_class, solver, market_id, vault_token_opt) =
        before(
        true
    );

    // Disable max skew.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let repl_solver = IReplicatingSolverDispatcher { contract_address: solver.contract_address };
    let mut market_params = default_market_params();
    market_params.max_skew = 0;
    repl_solver.queue_market_params(market_id, market_params);
    repl_solver.set_market_params(market_id);

    // Snapshot before.
    let vault_token = vault_token_opt.unwrap();
    let bef = snapshot(solver, market_id, base_token, quote_token, vault_token, owner());

    // Deposit initial.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let base_amount = to_e18(100);
    let quote_amount = 0;
    let dep_init = solver.deposit_initial(market_id, base_amount, quote_amount);

    // Snapshot after.
    let aft = snapshot(solver, market_id, base_token, quote_token, vault_token, owner());

    // Run checks.
    assert(dep_init.base_amount == base_amount, 'Base deposit');
    assert(dep_init.quote_amount == quote_amount, 'Quote deposit');
    assert(dep_init.shares != 0, 'Shares');
    assert(aft.lp_base_bal == bef.lp_base_bal - base_amount, 'LP base bal');
    assert(aft.lp_quote_bal == bef.lp_quote_bal - quote_amount, 'LP quote bal');
    assert(aft.vault_lp_bal == bef.vault_lp_bal + dep_init.shares, 'LP shares');
    assert(aft.vault_total_bal == bef.vault_total_bal + dep_init.shares, 'LP total shares');
    assert(aft.market_state.base_reserves == base_amount, 'Base reserve');
    assert(aft.market_state.quote_reserves == quote_amount, 'Quote reserve');
    assert(
        aft.bid.lower_sqrt_price == 0 && aft.bid.upper_sqrt_price == 0 && aft.bid.liquidity == 0,
        'Bid'
    );
    assert(
        aft.ask.lower_sqrt_price != 0 && aft.ask.upper_sqrt_price != 0 && aft.ask.liquidity != 0,
        'Ask'
    );
}

#[test]
fn test_deposit_initial_public_quote_token_only() {
    let (base_token, quote_token, _oracle, _vault_token_class, solver, market_id, vault_token_opt) =
        before(
        true
    );

    // Disable max skew.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let repl_solver = IReplicatingSolverDispatcher { contract_address: solver.contract_address };
    let mut market_params = default_market_params();
    market_params.max_skew = 0;
    repl_solver.queue_market_params(market_id, market_params);
    repl_solver.set_market_params(market_id);

    // Snapshot before.
    let vault_token = vault_token_opt.unwrap();
    let bef = snapshot(solver, market_id, base_token, quote_token, vault_token, owner());

    // Deposit initial.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let base_amount = 0;
    let quote_amount = to_e18(500);
    let dep_init = solver.deposit_initial(market_id, base_amount, quote_amount);

    // Snapshot after.
    let aft = snapshot(solver, market_id, base_token, quote_token, vault_token, owner());

    // Run checks.
    assert(dep_init.base_amount == base_amount, 'Base deposit');
    assert(dep_init.quote_amount == quote_amount, 'Quote deposit');
    assert(dep_init.shares != 0, 'Shares');
    assert(aft.lp_base_bal == bef.lp_base_bal - base_amount, 'LP base bal');
    assert(aft.lp_quote_bal == bef.lp_quote_bal - quote_amount, 'LP quote bal');
    assert(aft.vault_lp_bal == bef.vault_lp_bal + dep_init.shares, 'LP shares');
    assert(aft.vault_total_bal == bef.vault_total_bal + dep_init.shares, 'LP total shares');
    assert(aft.market_state.base_reserves == base_amount, 'Base reserve');
    assert(aft.market_state.quote_reserves == quote_amount, 'Quote reserve');
    assert(
        aft.bid.lower_sqrt_price != 0 && aft.bid.upper_sqrt_price != 0 && aft.bid.liquidity != 0,
        'Bid'
    );
    assert(
        aft.ask.lower_sqrt_price == 0 && aft.ask.upper_sqrt_price == 0 && aft.ask.liquidity == 0,
        'Ask'
    );
}

#[test]
fn test_deposit_initial_private_both_tokens() {
    let (
        base_token, quote_token, _oracle, _vault_token_class, solver, market_id, _vault_token_opt
    ) =
        before(
        false
    );

    // Snapshot before.
    let vault_token = contract_address_const::<0x0>();
    let bef = snapshot(solver, market_id, base_token, quote_token, vault_token, owner());

    // Deposit initial.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let base_amount = to_e18(100);
    let quote_amount = to_e18(500);
    let dep_init = solver.deposit_initial(market_id, base_amount, quote_amount);

    // Snapshot after.
    let aft = snapshot(solver, market_id, base_token, quote_token, vault_token, owner());

    // Run checks.
    assert(dep_init.base_amount == base_amount, 'Base deposit');
    assert(dep_init.quote_amount == quote_amount, 'Quote deposit');
    assert(dep_init.shares != 0, 'Shares');
    assert(aft.lp_base_bal == bef.lp_base_bal - base_amount, 'LP base bal');
    assert(aft.lp_quote_bal == bef.lp_quote_bal - quote_amount, 'LP quote bal');
    assert(aft.market_state.base_reserves == base_amount, 'Base reserve');
    assert(aft.market_state.quote_reserves == quote_amount, 'Quote reserve');
    assert(
        aft.bid.lower_sqrt_price != 0 && aft.bid.upper_sqrt_price != 0 && aft.bid.liquidity != 0,
        'Bid'
    );
    assert(
        aft.ask.lower_sqrt_price != 0 && aft.ask.upper_sqrt_price != 0 && aft.ask.liquidity != 0,
        'Ask'
    );
}

#[test]
fn test_deposit_initial_private_base_token_only() {
    let (
        base_token, quote_token, _oracle, _vault_token_class, solver, market_id, _vault_token_opt
    ) =
        before(
        false
    );

    // Disable max skew.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let repl_solver = IReplicatingSolverDispatcher { contract_address: solver.contract_address };
    let mut market_params = default_market_params();
    market_params.max_skew = 0;
    repl_solver.queue_market_params(market_id, market_params);
    repl_solver.set_market_params(market_id);

    // Snapshot before.
    let vault_token = contract_address_const::<0x0>();
    let bef = snapshot(solver, market_id, base_token, quote_token, vault_token, owner());

    // Deposit initial.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let base_amount = to_e18(100);
    let quote_amount = 0;
    let dep_init = solver.deposit_initial(market_id, base_amount, quote_amount);

    // Snapshot after.
    let aft = snapshot(solver, market_id, base_token, quote_token, vault_token, owner());

    // Run checks.
    assert(dep_init.base_amount == base_amount, 'Base deposit');
    assert(dep_init.quote_amount == quote_amount, 'Quote deposit');
    assert(dep_init.shares != 0, 'Shares');
    assert(aft.lp_base_bal == bef.lp_base_bal - base_amount, 'LP base bal');
    assert(aft.lp_quote_bal == bef.lp_quote_bal - quote_amount, 'LP quote bal');
    assert(aft.market_state.base_reserves == base_amount, 'Base reserve');
    assert(aft.market_state.quote_reserves == quote_amount, 'Quote reserve');
    assert(
        aft.bid.lower_sqrt_price == 0 && aft.bid.upper_sqrt_price == 0 && aft.bid.liquidity == 0,
        'Bid'
    );
    assert(
        aft.ask.lower_sqrt_price != 0 && aft.ask.upper_sqrt_price != 0 && aft.ask.liquidity != 0,
        'Ask'
    );
}

#[test]
fn test_deposit_initial_private_quote_token_only() {
    let (
        base_token, quote_token, _oracle, _vault_token_class, solver, market_id, _vault_token_opt
    ) =
        before(
        false
    );

    // Disable max skew.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let repl_solver = IReplicatingSolverDispatcher { contract_address: solver.contract_address };
    let mut market_params = default_market_params();
    market_params.max_skew = 0;
    repl_solver.queue_market_params(market_id, market_params);
    repl_solver.set_market_params(market_id);

    // Snapshot before.
    let vault_token = contract_address_const::<0x0>();
    let bef = snapshot(solver, market_id, base_token, quote_token, vault_token, owner());

    // Deposit initial.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let base_amount = 0;
    let quote_amount = to_e18(500);
    let dep_init = solver.deposit_initial(market_id, base_amount, quote_amount);

    // Snapshot after.
    let aft = snapshot(solver, market_id, base_token, quote_token, vault_token, owner());

    // Run checks.
    assert(dep_init.base_amount == base_amount, 'Base deposit');
    assert(dep_init.quote_amount == quote_amount, 'Quote deposit');
    assert(dep_init.shares != 0, 'Shares');
    assert(aft.lp_base_bal == bef.lp_base_bal - base_amount, 'LP base bal');
    assert(aft.lp_quote_bal == bef.lp_quote_bal - quote_amount, 'LP quote bal');
    assert(aft.market_state.base_reserves == base_amount, 'Base reserve');
    assert(aft.market_state.quote_reserves == quote_amount, 'Quote reserve');
    assert(
        aft.bid.lower_sqrt_price != 0 && aft.bid.upper_sqrt_price != 0 && aft.bid.liquidity != 0,
        'Bid'
    );
    assert(
        aft.ask.lower_sqrt_price == 0 && aft.ask.upper_sqrt_price == 0 && aft.ask.liquidity == 0,
        'Ask'
    );
}

#[test]
fn test_deposit_initial_public_mismatched_token_decimals() {
    let (base_token, quote_token, _oracle, _vault_token_class, solver, market_id, vault_token_opt) =
        before_custom_decimals(
        true, 18, 6
    );

    // Deposit initial.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let base_amount = to_e18(100);
    let quote_amount = 1000_000000;
    solver.deposit_initial(market_id, base_amount, quote_amount);

    // Snapshot after.
    let vault_token = vault_token_opt.unwrap();
    let aft = snapshot(solver, market_id, base_token, quote_token, vault_token, owner());

    // Check positions.
    let sqrt_price = 31622776601683793319988; // sqrt price corresponding to 10
    assert(aft.bid.lower_sqrt_price < sqrt_price, 'bid lower sqrt price');
    assert(aft.bid.upper_sqrt_price <= sqrt_price, 'bid upper sqrt price');
    assert(aft.bid.liquidity != 0, 'bid liquidity');
    assert(aft.ask.lower_sqrt_price >= sqrt_price, 'ask lower sqrt price');
    assert(aft.ask.upper_sqrt_price > sqrt_price, 'ask upper sqrt price');
    assert(aft.ask.liquidity != 0, 'ask liquidity');
    // Liquidity should be similar.
    assert(approx_eq_pct(aft.bid.liquidity.into(), aft.ask.liquidity.into(), 2), 'ask liquidity');
}
