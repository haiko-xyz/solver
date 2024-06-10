// Core lib imports.
use starknet::contract_address_const;

// Local imports.
use haiko_solver_replicating::{
    contracts::solver::ReplicatingSolver,
    contracts::mocks::mock_pragma_oracle::{
        IMockPragmaOracleDispatcher, IMockPragmaOracleDispatcherTrait
    },
    interfaces::{
        IVaultToken::{IVaultTokenDispatcher, IVaultTokenDispatcherTrait},
        IReplicatingSolver::{IReplicatingSolverDispatcher, IReplicatingSolverDispatcherTrait},
    },
    types::replicating::{MarketInfo, MarketParams},
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
use haiko_lib::helpers::utils::{to_e18, approx_eq, approx_eq_pct};
use haiko_lib::helpers::actions::token::{fund, approve};

// External imports.
use snforge_std::{
    start_prank, start_warp, declare, spy_events, SpyOn, EventSpy, EventAssertions, CheatTarget
};
use openzeppelin::token::erc20::interface::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};

////////////////////////////////
// TESTS - Success cases
////////////////////////////////

#[test]
fn test_deposit_public_vault_both_tokens_at_ratio() {
    let (base_token, quote_token, _oracle, _vault_token_class, solver, market_id, vault_token_opt) =
        before(
        true
    );

    // Deposit initial.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let base_amount = to_e18(100);
    let quote_amount = to_e18(500);
    let (_, _, shares_init) = solver.deposit_initial(market_id, base_amount, quote_amount);

    // Snapshot before.
    let vault_token = vault_token_opt.unwrap();
    let bef = snapshot(solver, market_id, base_token, quote_token, vault_token, alice());

    // Deposit.
    start_prank(CheatTarget::One(solver.contract_address), alice());
    let (base_deposit, quote_deposit, shares) = solver
        .deposit(market_id, base_amount, quote_amount);

    // Snapshot after.
    let aft = snapshot(solver, market_id, base_token, quote_token, vault_token, alice());

    // Run checks.
    assert(base_deposit == base_amount, 'Base deposit');
    assert(quote_deposit == quote_amount, 'Quote deposit');
    assert(shares == shares_init, 'Shares');
    assert(aft.lp_base_bal == bef.lp_base_bal - base_amount, 'LP base bal');
    assert(aft.lp_quote_bal == bef.lp_quote_bal - quote_amount, 'LP quote bal');
    assert(aft.vault_lp_bal == bef.vault_lp_bal + shares, 'LP shares');
    assert(aft.vault_total_bal == bef.vault_total_bal + shares, 'LP total shares');
    assert(
        aft.market_state.base_reserves == bef.market_state.base_reserves + base_amount,
        'Base reserve'
    );
    assert(
        aft.market_state.quote_reserves == bef.market_state.quote_reserves + quote_amount,
        'Quote reserve'
    );
    assert(aft.bid.lower_sqrt_price == bef.bid.lower_sqrt_price, 'Bid lower sqrt price');
    assert(aft.bid.upper_sqrt_price == bef.bid.upper_sqrt_price, 'Bid upper sqrt price');
    assert(
        approx_eq(aft.bid.liquidity.into(), bef.bid.liquidity.into() * 2, 1000), 'Bid liquidity'
    );
    assert(aft.ask.lower_sqrt_price == bef.ask.lower_sqrt_price, 'Ask lower sqrt price');
    assert(aft.ask.upper_sqrt_price == bef.ask.upper_sqrt_price, 'Ask upper sqrt price');
    assert(
        approx_eq(aft.ask.liquidity.into(), bef.ask.liquidity.into() * 2, 1000), 'Ask liquidity'
    );
}

#[test]
fn test_deposit_public_vault_both_tokens_above_base_ratio() {
    let (
        _base_token, _quote_token, _oracle, _vault_token_class, solver, market_id, _vault_token_opt
    ) =
        before(
        true
    );

    // Deposit initial.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let base_amount = to_e18(100);
    let quote_amount = to_e18(500);
    let (_, _, shares_init) = solver.deposit_initial(market_id, base_amount, quote_amount);

    // Deposit.
    start_prank(CheatTarget::One(solver.contract_address), alice());
    let (base_deposit, quote_deposit, shares) = solver
        .deposit(market_id, base_amount + to_e18(50), quote_amount);

    // Run checks.
    assert(base_deposit == base_amount, 'Base deposit');
    assert(quote_deposit == quote_amount, 'Quote deposit');
    assert(shares == shares_init, 'Shares');
}

#[test]
fn test_deposit_public_vault_both_tokens_above_quote_ratio() {
    let (
        _base_token, _quote_token, _oracle, _vault_token_class, solver, market_id, _vault_token_opt
    ) =
        before(
        true
    );

    // Deposit initial.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let base_amount = to_e18(100);
    let quote_amount = to_e18(500);
    let (_, _, shares_init) = solver.deposit_initial(market_id, base_amount, quote_amount);

    // Deposit.
    start_prank(CheatTarget::One(solver.contract_address), alice());
    let (base_deposit, quote_deposit, shares) = solver
        .deposit(market_id, base_amount, quote_amount + to_e18(500));

    // Run checks.
    assert(base_deposit == base_amount, 'Base deposit');
    assert(quote_deposit == quote_amount, 'Quote deposit');
    assert(shares == shares_init, 'Shares');
}

#[test]
fn test_deposit_public_vault_both_tokens_above_available() {
    let (
        _base_token, _quote_token, _oracle, _vault_token_class, solver, market_id, _vault_token_opt
    ) =
        before(
        true
    );

    // Deposit initial.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let base_amount = to_e18(10000000);
    let quote_amount = to_e18(2000000000000);
    solver.deposit_initial(market_id, base_amount, quote_amount);

    // Deposit.
    start_prank(CheatTarget::One(solver.contract_address), alice());
    let (base_deposit, quote_deposit, _) = solver.deposit(market_id, base_amount, quote_amount);

    // Run checks.
    let base_exp = to_e18(5000000);
    let quote_exp = to_e18(1000000000000);
    assert(base_deposit == base_exp, 'Base deposit');
    assert(quote_deposit == quote_exp, 'Quote deposit');
}

#[test]
fn test_deposit_public_vault_base_token_only() {
    let (base_token, quote_token, _oracle, _vault_token_class, solver, market_id, vault_token_opt) =
        before(
        true
    );

    // Deposit initial.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let base_amount = to_e18(100);
    let quote_amount = 0;
    let (_, _, shares_init) = solver.deposit_initial(market_id, base_amount, quote_amount);

    // Snapshot before.
    let vault_token = vault_token_opt.unwrap();
    let bef = snapshot(solver, market_id, base_token, quote_token, vault_token, alice());

    // Deposit.
    start_prank(CheatTarget::One(solver.contract_address), alice());
    let (base_deposit, quote_deposit, shares) = solver
        .deposit(market_id, base_amount, quote_amount);

    // Snapshot after.
    let aft = snapshot(solver, market_id, base_token, quote_token, vault_token, alice());

    // Run checks.
    assert(base_deposit == base_amount, 'Base deposit');
    assert(quote_deposit == quote_amount, 'Quote deposit');
    assert(shares == shares_init, 'Shares');

    assert(aft.lp_base_bal == bef.lp_base_bal - base_amount, 'LP base bal');
    assert(aft.lp_quote_bal == bef.lp_quote_bal - quote_amount, 'LP quote bal');
    assert(aft.vault_lp_bal == bef.vault_lp_bal + shares, 'LP shares');
    assert(aft.vault_total_bal == bef.vault_total_bal + shares, 'LP total shares');
    assert(
        aft.market_state.base_reserves == bef.market_state.base_reserves + base_amount,
        'Base reserve'
    );
    assert(
        aft.market_state.quote_reserves == bef.market_state.quote_reserves + quote_amount,
        'Quote reserve'
    );
    assert(aft.bid.lower_sqrt_price == bef.bid.lower_sqrt_price, 'Bid lower sqrt price');
    assert(aft.bid.upper_sqrt_price == bef.bid.upper_sqrt_price, 'Bid upper sqrt price');
    assert(aft.bid.liquidity == bef.bid.liquidity, 'Bid liquidity');
    assert(aft.ask.lower_sqrt_price == bef.ask.lower_sqrt_price, 'Ask lower sqrt price');
    assert(aft.ask.upper_sqrt_price == bef.ask.upper_sqrt_price, 'Ask upper sqrt price');
    assert(
        approx_eq(aft.ask.liquidity.into(), bef.ask.liquidity.into() * 2, 1000), 'Ask liquidity'
    );
}

#[test]
fn test_deposit_public_vault_quote_token_only() {
    let (base_token, quote_token, _oracle, _vault_token_class, solver, market_id, vault_token_opt) =
        before(
        true
    );

    // Deposit initial.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let base_amount = 0;
    let quote_amount = to_e18(500);
    let (_, _, shares_init) = solver.deposit_initial(market_id, base_amount, quote_amount);

    // Snapshot before.
    let vault_token = vault_token_opt.unwrap();
    let bef = snapshot(solver, market_id, base_token, quote_token, vault_token, alice());

    // Deposit.
    start_prank(CheatTarget::One(solver.contract_address), alice());
    let (base_deposit, quote_deposit, shares) = solver
        .deposit(market_id, base_amount, quote_amount);

    // Snapshot after.
    let aft = snapshot(solver, market_id, base_token, quote_token, vault_token, alice());

    // Run checks.
    assert(base_deposit == base_amount, 'Base deposit');
    assert(quote_deposit == quote_amount, 'Quote deposit');
    assert(shares == shares_init, 'Shares');

    assert(aft.lp_base_bal == bef.lp_base_bal - base_amount, 'LP base bal');
    assert(aft.lp_quote_bal == bef.lp_quote_bal - quote_amount, 'LP quote bal');
    assert(aft.vault_lp_bal == bef.vault_lp_bal + shares, 'LP shares');
    assert(aft.vault_total_bal == bef.vault_total_bal + shares, 'LP total shares');
    assert(
        aft.market_state.base_reserves == bef.market_state.base_reserves + base_amount,
        'Base reserve'
    );
    assert(
        aft.market_state.quote_reserves == bef.market_state.quote_reserves + quote_amount,
        'Quote reserve'
    );
    assert(aft.bid.lower_sqrt_price == bef.bid.lower_sqrt_price, 'Bid lower sqrt price');
    assert(aft.bid.upper_sqrt_price == bef.bid.upper_sqrt_price, 'Bid upper sqrt price');
    assert(
        approx_eq(aft.bid.liquidity.into(), bef.bid.liquidity.into() * 2, 1000), 'Bid liquidity'
    );
    assert(aft.ask.lower_sqrt_price == bef.ask.lower_sqrt_price, 'Ask lower sqrt price');
    assert(aft.ask.upper_sqrt_price == bef.ask.upper_sqrt_price, 'Ask upper sqrt price');
    assert(aft.ask.liquidity == bef.ask.liquidity, 'Ask liquidity');
}

#[test]
fn test_deposit_private_vault_both_tokens_at_arbitrary_ratio() {
    let (
        base_token, quote_token, _oracle, _vault_token_class, solver, market_id, _vault_token_opt
    ) =
        before(
        false
    );

    // Deposit initial.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let base_deposit_init = to_e18(100);
    let quote_deposit_init = to_e18(500);
    solver.deposit_initial(market_id, base_deposit_init, quote_deposit_init);

    // Snapshot before.
    let vault_token = contract_address_const::<0x0>();
    let bef = snapshot(solver, market_id, base_token, quote_token, vault_token, owner());

    // Deposit at arbitrary ratio.
    let base_deposit = to_e18(50);
    let quote_deposit = to_e18(600);
    let (base_amount, quote_amount, shares) = solver
        .deposit(market_id, base_deposit, quote_deposit);

    // Snapshot after.
    let aft = snapshot(solver, market_id, base_token, quote_token, vault_token, owner());

    // Run checks.
    assert(base_deposit == base_amount, 'Base deposit');
    assert(quote_deposit == quote_amount, 'Quote deposit');
    assert(shares == 0, 'Shares');
    assert(aft.lp_base_bal == bef.lp_base_bal - base_amount, 'LP base bal');
    assert(aft.lp_quote_bal == bef.lp_quote_bal - quote_amount, 'LP quote bal');
    assert(aft.vault_lp_bal == bef.vault_lp_bal + shares, 'LP shares');
    assert(aft.vault_total_bal == bef.vault_total_bal + shares, 'LP total shares');
    assert(
        aft.market_state.base_reserves == bef.market_state.base_reserves + base_amount,
        'Base reserve'
    );
    assert(
        aft.market_state.quote_reserves == bef.market_state.quote_reserves + quote_amount,
        'Quote reserve'
    );
    // Portfolio now more skewed towards quote asset, so we expect a bid skew.
    assert(aft.bid.lower_sqrt_price < bef.bid.lower_sqrt_price, 'Bid lower sqrt price');
    assert(aft.bid.upper_sqrt_price < bef.bid.upper_sqrt_price, 'Bid upper sqrt price');
    assert(aft.bid.liquidity > bef.bid.liquidity, 'Bid liquidity');
    assert(aft.ask.lower_sqrt_price < bef.ask.lower_sqrt_price, 'Ask lower sqrt price');
    assert(aft.ask.upper_sqrt_price < bef.ask.upper_sqrt_price, 'Ask upper sqrt price');
    assert(aft.ask.liquidity > bef.ask.liquidity, 'Ask liquidity');
}

#[test]
fn test_deposit_private_vault_base_token_only() {
    let (
        base_token, quote_token, _oracle, _vault_token_class, solver, market_id, _vault_token_opt
    ) =
        before(
        false
    );

    // Deposit initial.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let base_deposit_init = to_e18(100);
    let quote_deposit_init = to_e18(500);
    solver.deposit_initial(market_id, base_deposit_init, quote_deposit_init);

    // Snapshot before.
    let vault_token = contract_address_const::<0x0>();
    let bef = snapshot(solver, market_id, base_token, quote_token, vault_token, owner());

    // Deposit at arbitrary ratio.
    let base_deposit = to_e18(50);
    let quote_deposit = 0;
    let (base_amount, quote_amount, shares) = solver
        .deposit(market_id, base_deposit, quote_deposit);

    // Snapshot after.
    let aft = snapshot(solver, market_id, base_token, quote_token, vault_token, owner());

    // Run checks.
    assert(base_deposit == base_amount, 'Base deposit');
    assert(quote_deposit == quote_amount, 'Quote deposit');
    assert(shares == 0, 'Shares');
    assert(aft.lp_base_bal == bef.lp_base_bal - base_amount, 'LP base bal');
    assert(aft.lp_quote_bal == bef.lp_quote_bal - quote_amount, 'LP quote bal');
    assert(aft.vault_lp_bal == bef.vault_lp_bal + shares, 'LP shares');
    assert(aft.vault_total_bal == bef.vault_total_bal + shares, 'LP total shares');
    assert(
        aft.market_state.base_reserves == bef.market_state.base_reserves + base_amount,
        'Base reserve'
    );
    assert(
        aft.market_state.quote_reserves == bef.market_state.quote_reserves + quote_amount,
        'Quote reserve'
    );
    // Portfolio now more skewed towards base asset, so we expect a ask skew.
    assert(aft.bid.lower_sqrt_price > bef.bid.lower_sqrt_price, 'Bid lower sqrt price');
    assert(aft.bid.upper_sqrt_price > bef.bid.upper_sqrt_price, 'Bid upper sqrt price');
    assert(aft.ask.lower_sqrt_price > bef.ask.lower_sqrt_price, 'Ask lower sqrt price');
    assert(aft.ask.upper_sqrt_price > bef.ask.upper_sqrt_price, 'Ask upper sqrt price');
}

#[test]
fn test_deposit_private_vault_quote_token_only() {
    let (
        base_token, quote_token, _oracle, _vault_token_class, solver, market_id, _vault_token_opt
    ) =
        before(
        false
    );

    // Deposit initial.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let base_deposit_init = to_e18(100);
    let quote_deposit_init = to_e18(500);
    solver.deposit_initial(market_id, base_deposit_init, quote_deposit_init);

    // Snapshot before.
    let vault_token = contract_address_const::<0x0>();
    let bef = snapshot(solver, market_id, base_token, quote_token, vault_token, owner());

    // Deposit at arbitrary ratio.
    let base_deposit = 0;
    let quote_deposit = to_e18(600);
    let (base_amount, quote_amount, shares) = solver
        .deposit(market_id, base_deposit, quote_deposit);

    // Snapshot after.
    let aft = snapshot(solver, market_id, base_token, quote_token, vault_token, owner());

    // Run checks.
    assert(base_deposit == base_amount, 'Base deposit');
    assert(quote_deposit == quote_amount, 'Quote deposit');
    assert(shares == 0, 'Shares');
    assert(aft.lp_base_bal == bef.lp_base_bal - base_amount, 'LP base bal');
    assert(aft.lp_quote_bal == bef.lp_quote_bal - quote_amount, 'LP quote bal');
    assert(aft.vault_lp_bal == bef.vault_lp_bal + shares, 'LP shares');
    assert(aft.vault_total_bal == bef.vault_total_bal + shares, 'LP total shares');
    assert(
        aft.market_state.base_reserves == bef.market_state.base_reserves + base_amount,
        'Base reserve'
    );
    assert(
        aft.market_state.quote_reserves == bef.market_state.quote_reserves + quote_amount,
        'Quote reserve'
    );
    // Portfolio now more skewed towards quote asset, so we expect a bid skew.
    assert(aft.bid.lower_sqrt_price < bef.bid.lower_sqrt_price, 'Bid lower sqrt price');
    assert(aft.bid.upper_sqrt_price < bef.bid.upper_sqrt_price, 'Bid upper sqrt price');
    assert(aft.ask.lower_sqrt_price < bef.ask.lower_sqrt_price, 'Ask lower sqrt price');
    assert(aft.ask.upper_sqrt_price < bef.ask.upper_sqrt_price, 'Ask upper sqrt price');
}

////////////////////////////////
// TESTS - Events
////////////////////////////////

#[test]
fn test_deposit_emits_event() {
    let (
        _base_token, _quote_token, _oracle, _vault_token_class, solver, market_id, _vault_token_opt
    ) =
        before(
        true
    );

    // Deposit initial.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let base_amount = to_e18(100);
    let quote_amount = 1000_000000;
    solver.deposit_initial(market_id, base_amount, quote_amount);

    // Spy on events.
    let mut spy = spy_events(SpyOn::One(solver.contract_address));

    // Deposit.
    let (base_deposit, quote_deposit, shares) = solver
        .deposit(market_id, base_amount, quote_amount);

    // Check events emitted.
    spy
        .assert_emitted(
            @array![
                (
                    solver.contract_address,
                    ReplicatingSolver::Event::Deposit(
                        ReplicatingSolver::Deposit {
                            market_id,
                            caller: owner(),
                            base_amount: base_deposit,
                            quote_amount: quote_deposit,
                            shares
                        }
                    )
                )
            ]
        );
}

#[test]
fn test_deposit_with_referrer_emits_event() {
    let (
        _base_token, _quote_token, _oracle, _vault_token_class, solver, market_id, _vault_token_opt
    ) =
        before(
        true
    );

    // Deposit initial.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let base_amount = to_e18(100);
    let quote_amount = 1000_000000;
    solver.deposit_initial(market_id, base_amount, quote_amount);

    // Spy on events.
    let mut spy = spy_events(SpyOn::One(solver.contract_address));

    // Deposit.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let (base_deposit, quote_deposit, shares) = solver
        .deposit_with_referrer(market_id, base_amount, quote_amount, alice());

    // Check events emitted.
    spy
        .assert_emitted(
            @array![
                (
                    solver.contract_address,
                    ReplicatingSolver::Event::Referral(
                        ReplicatingSolver::Referral { caller: owner(), referrer: alice(), }
                    )
                ),
                (
                    solver.contract_address,
                    ReplicatingSolver::Event::Deposit(
                        ReplicatingSolver::Deposit {
                            market_id,
                            caller: owner(),
                            base_amount: base_deposit,
                            quote_amount: quote_deposit,
                            shares
                        }
                    )
                )
            ]
        );
}

////////////////////////////////
// TESTS - Failure cases
////////////////////////////////

#[test]
#[should_panic(expected: ('AmountsZero',))]
fn test_deposit_both_amounts_zero_fails() {
    let (
        _base_token, _quote_token, _oracle, _vault_token_class, solver, market_id, _vault_token_opt
    ) =
        before(
        true
    );

    // Deposit initial.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let base_amount = 0;
    let quote_amount = 0;
    solver.deposit_initial(market_id, base_amount, quote_amount);

    // Deposit.
    solver.deposit(market_id, 0, 0);
}

#[test]
#[should_panic(expected: ('MarketNull',))]
fn test_deposit_market_uninitialised() {
    let (
        _base_token, _quote_token, _oracle, _vault_token_class, solver, market_id, _vault_token_opt
    ) =
        before(
        true
    );

    // Deposit initial.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let base_amount = to_e18(100);
    let quote_amount = to_e18(500);
    solver.deposit_initial(market_id, base_amount, quote_amount);

    // Deposit.
    solver.deposit(1, base_amount, quote_amount);
}

#[test]
#[should_panic(expected: ('UseDepositInitial',))]
fn test_deposit_no_existing_deposits() {
    let (
        _base_token, _quote_token, _oracle, _vault_token_class, solver, market_id, _vault_token_opt
    ) =
        before(
        true
    );

    // Deposit.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let base_amount = to_e18(100);
    let quote_amount = to_e18(500);
    solver.deposit(market_id, base_amount, quote_amount);
}

#[test]
#[should_panic(expected: ('Paused',))]
fn test_deposit_paused() {
    let (
        _base_token, _quote_token, _oracle, _vault_token_class, solver, market_id, _vault_token_opt
    ) =
        before(
        true
    );

    // Deposit initial.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let base_amount = to_e18(100);
    let quote_amount = to_e18(500);
    solver.deposit_initial(market_id, base_amount, quote_amount);

    // Pause.
    solver.pause(market_id);

    // Deposit.
    start_prank(CheatTarget::One(solver.contract_address), alice());
    solver.deposit(market_id, base_amount, quote_amount);
}

#[test]
#[should_panic(expected: ('OnlyMarketOwner',))]
fn test_deposit_private_market_for_non_owner_caller() {
    let (
        _base_token, _quote_token, _oracle, _vault_token_class, solver, market_id, _vault_token_opt
    ) =
        before(
        false
    );

    // Deposit initial.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let base_amount = to_e18(100);
    let quote_amount = to_e18(500);
    solver.deposit_initial(market_id, base_amount, quote_amount);

    // Deposit.
    start_prank(CheatTarget::One(solver.contract_address), alice());
    solver.deposit(market_id, base_amount, quote_amount);
}

#[test]
#[should_panic(expected: ('BaseAllowance',))]
fn test_deposit_initial_not_approved() {
    let (
        base_token, quote_token, _oracle, _vault_token_class, solver, market_id, _vault_token_opt
    ) =
        before_skip_approve(
        false
    );

    // Deposit initial.
    let base_amount = to_e18(100);
    let quote_amount = to_e18(500);
    approve(base_token, alice(), solver.contract_address, base_amount);
    approve(quote_token, alice(), solver.contract_address, quote_amount);
    start_prank(CheatTarget::One(solver.contract_address), owner());
    solver.deposit_initial(market_id, base_amount, quote_amount);

    // Deposit.
    start_prank(CheatTarget::One(solver.contract_address), alice());
    solver.deposit(market_id, base_amount, quote_amount);
}


#[test]
#[should_panic(expected: ('InvalidOraclePrice',))]
fn test_deposit_initial_invalid_oracle_price() {
    let (
        _base_token, _quote_token, oracle, _vault_token_class, solver, market_id, _vault_token_opt
    ) =
        before(
        false
    );

    // Set oracle price with invalid quorum.
    start_warp(CheatTarget::One(oracle.contract_address), 1000);
    oracle.set_data_with_USD_hop('ETH', 'USDC', 1000000000, 8, 999, 1); // 10

    // Deposit initial.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let base_amount = to_e18(100);
    let quote_amount = to_e18(500);
    solver.deposit_initial(market_id, base_amount, quote_amount);

    // Set oracle price with invalid age.
    start_warp(CheatTarget::One(oracle.contract_address), 1000);
    oracle.set_data_with_USD_hop('ETH', 'USDC', 1000000000, 8, 0, 3); // 10

    // Deposit.
    solver.deposit(market_id, base_amount, quote_amount);
}
