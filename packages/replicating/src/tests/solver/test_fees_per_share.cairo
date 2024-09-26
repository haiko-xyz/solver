// Core lib imports.
use starknet::contract_address_const;

// Local imports.
use haiko_solver_core::{
    contracts::solver::SolverComponent,
    interfaces::ISolver::{ISolverDispatcher, ISolverDispatcherTrait}, types::SwapParams,
};
use haiko_solver_replicating::{
    contracts::mocks::mock_pragma_oracle::{
        IMockPragmaOracleDispatcher, IMockPragmaOracleDispatcherTrait
    },
    interfaces::IReplicatingSolver::{
        IReplicatingSolverDispatcher, IReplicatingSolverDispatcherTrait
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
use haiko_lib::helpers::params::{owner, alice, bob};
use haiko_lib::helpers::utils::{to_e18, approx_eq, approx_eq_pct};
use haiko_lib::helpers::actions::token::{fund, approve};

// External imports.
use snforge_std::{
    start_prank, stop_prank, start_warp, declare, spy_events, SpyOn, EventSpy, EventAssertions,
    CheatTarget
};
use openzeppelin::token::erc20::interface::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};

///////////////////////////////////
// TESTS - Success cases (Public)
///////////////////////////////////

#[test]
fn test_fps_public_market_fee_per_shares_correctly_updated() {
    let (
        _base_token, _quote_token, _oracle, _vault_token_class, solver, market_id, _vault_token_opt
    ) =
        before(
        true
    );

    // Deposit initial.
    // after: market fps = 0, owner fps = 0
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let base_amount = to_e18(100);
    let quote_amount = to_e18(500);
    let dep_init = solver.deposit_initial(market_id, base_amount, quote_amount);
    let mut market_fps = solver.fees_per_share(market_id);
    let mut owner_fps = solver.user_fees_per_share(market_id, owner());
    assert(market_fps.base_fps == 0, 'Market base fps init');
    assert(market_fps.quote_fps == 0, 'Market quote fps init');
    assert(owner_fps.base_fps == 0, 'Owner base fps init');
    assert(owner_fps.quote_fps == 0, 'Owner quote fps init');

    // Swap.
    // after: market fps = [1], owner fps = 0
    let params = SwapParams {
        is_buy: false,
        amount: to_e18(10),
        exact_input: true,
        threshold_sqrt_price: Option::None(()),
        threshold_amount: Option::None(()),
        deadline: Option::None(()),
    };
    solver.swap(market_id, params);
    market_fps = solver.fees_per_share(market_id);
    owner_fps = solver.user_fees_per_share(market_id, owner());
    assert(market_fps.base_fps > owner_fps.base_fps, 'Owner fps 1');
    assert(market_fps.quote_fps == owner_fps.quote_fps, 'Owner fps 1');

    // Deposit.
    // after: market fps = [1], owner fps = 0, alice fps = [1]
    start_prank(CheatTarget::One(solver.contract_address), alice());
    let dep = solver.deposit(market_id, base_amount, quote_amount);
    market_fps = solver.fees_per_share(market_id);
    owner_fps = solver.user_fees_per_share(market_id, owner());
    let mut alice_fps = solver.user_fees_per_share(market_id, alice());
    assert(market_fps == alice_fps, 'Market + alice fps 2');
    assert(owner_fps == Default::default(), 'Owner fps 2');

    // Withdraw.
    // after: market fps = [1], owner fps = [1], alice fps = [1]
    start_prank(CheatTarget::One(solver.contract_address), owner());
    solver.withdraw_public(market_id, dep_init.shares);
    market_fps = solver.fees_per_share(market_id);
    owner_fps = solver.user_fees_per_share(market_id, owner());
    alice_fps = solver.user_fees_per_share(market_id, alice());
    assert(market_fps == owner_fps, 'Market fps 3');
    assert(owner_fps == alice_fps, 'Owner fps 3');

    // Swap.
    // after: market fps = [2], owner fps = [1], alice fps = [1]
    let params = SwapParams {
        is_buy: true,
        amount: to_e18(10),
        exact_input: true,
        threshold_sqrt_price: Option::None(()),
        threshold_amount: Option::None(()),
        deadline: Option::None(()),
    };
    solver.swap(market_id, params);
    market_fps = solver.fees_per_share(market_id);
    owner_fps = solver.user_fees_per_share(market_id, owner());
    alice_fps = solver.user_fees_per_share(market_id, alice());
    assert(market_fps.base_fps == owner_fps.base_fps, 'Market + owner base fps 4');
    assert(market_fps.quote_fps > owner_fps.quote_fps, 'Market + owner quote fps 4');
    assert(owner_fps == alice_fps, 'Owner + alice fps 4');

    // Withdraw.
    // after: market fps = [2], owner fps = [1], alice fps = [2]
    start_prank(CheatTarget::One(solver.contract_address), alice());
    solver.withdraw_public(market_id, dep.shares / 2);
    market_fps = solver.fees_per_share(market_id);
    owner_fps = solver.user_fees_per_share(market_id, owner());
    alice_fps = solver.user_fees_per_share(market_id, alice());
    assert(market_fps == alice_fps, 'Alice fps 5');
    assert(market_fps.base_fps == owner_fps.base_fps, 'Market + owner base fps 5');
    assert(market_fps.quote_fps > owner_fps.quote_fps, 'Market + owner quote fps 5');
}

#[test]
fn test_fps_deposit_and_withdraw_to_public_market_with_no_fee_balance() {
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
    start_prank(CheatTarget::One(solver.contract_address), alice());
    let dep = solver.deposit(market_id, base_amount, quote_amount);

    // Withdraw.
    start_prank(CheatTarget::One(solver.contract_address), alice());
    let wd_alice = solver.withdraw_public(market_id, dep.shares);
    assert(approx_eq(wd_alice.base_amount, base_amount, 1), 'Alice base amount');
    assert(approx_eq(wd_alice.quote_amount, quote_amount, 1), 'Alice quote amount');

    // Withdraw.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let wd_owner = solver.withdraw_public(market_id, dep.shares);
    assert(approx_eq(wd_owner.base_amount, base_amount, 1), 'Owner base amount');
    assert(approx_eq(wd_owner.quote_amount, quote_amount, 1), 'Owner quote amount');
}

#[test]
fn test_fps_deposit_to_public_market_with_existing_fee_balance_doesnt_skim_profits() {
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

    // Swap.
    start_prank(CheatTarget::One(solver.contract_address), alice());
    let params = SwapParams {
        is_buy: false,
        amount: to_e18(10),
        exact_input: true,
        threshold_sqrt_price: Option::None(()),
        threshold_amount: Option::None(()),
        deadline: Option::None(()),
    };
    let swap = solver.swap(market_id, params);

    // Deposit.
    start_prank(CheatTarget::One(solver.contract_address), alice());
    let dep = solver.deposit(market_id, base_amount, quote_amount);

    // Get balances.
    let owner = solver.get_user_balances(owner(), market_id);
    let alice = solver.get_user_balances(alice(), market_id);

    // Check balances.
    assert(approx_eq(owner.base_fees, swap.fees, 1), 'Owner base fees');
    assert(owner.quote_fees == 0, 'Owner quote fees');
    assert(alice.base_fees == 0, 'Alice base fees');
    assert(alice.quote_fees == 0, 'Alice quote fees');

    // Withdraw and confirm.
    start_prank(CheatTarget::One(solver.contract_address), alice());
    let wd_alice = solver.withdraw_public(market_id, dep.shares);
    assert(wd_alice.base_fees == 0, 'Alice base fees');
    assert(wd_alice.quote_fees == 0, 'Alice quote fees');

    // Withdraw owner.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let wd_owner = solver.withdraw_public(market_id, dep.shares);
    assert(approx_eq(wd_owner.base_fees, swap.fees, 1), 'Owner base fees');
    assert(wd_owner.quote_fees == 0, 'Owner quote fees');
}

#[test]
fn test_fps_public_market_multiple_lps_base() {
    let (
        _base_token, _quote_token, _oracle, _vault_token_class, solver, market_id, _vault_token_opt
    ) =
        before(
        true
    );

    // Disable max skew.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let mut market_params = default_market_params();
    market_params.max_skew = 0;
    let repl_solver = IReplicatingSolverDispatcher { contract_address: solver.contract_address };
    repl_solver.queue_market_params(market_id, market_params);
    repl_solver.set_market_params(market_id);

    // Deposit initial (owner).
    // ownership: owner = 100%, alice = 0%, bob = 0%
    // base fees: owner = 0, alice = 0, bob = 0
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let base_amount = to_e18(500);
    let quote_amount = to_e18(1000);
    let dep_owner = solver.deposit_initial(market_id, base_amount, quote_amount);

    // Swap.
    // ownership: owner = 100%, alice = 0%, bob = 0%
    // base fees: owner = 0.05, alice = 0, bob = 0
    let params = SwapParams {
        is_buy: false,
        amount: to_e18(10),
        exact_input: true,
        threshold_sqrt_price: Option::None(()),
        threshold_amount: Option::None(()),
        deadline: Option::None(()),
    };
    solver.swap(market_id, params);

    // Deposit (alice).
    // ownership: owner = 50%, alice = 50%, bob = 0%
    // base fees: owner = 0.05, alice = 0, bob = 0
    start_prank(CheatTarget::One(solver.contract_address), alice());
    let mut balances = solver.get_balances(market_id);
    solver.deposit(market_id, balances.base_amount, balances.quote_amount);

    // Swap.
    // ownership: owner = 50%, alice = 50%, bob = 0%
    // base fees: owner = 0.175, alice = 0.125, bob = 0
    let params = SwapParams {
        is_buy: false,
        amount: to_e18(50),
        exact_input: true,
        threshold_sqrt_price: Option::None(()),
        threshold_amount: Option::None(()),
        deadline: Option::None(()),
    };
    solver.swap(market_id, params);

    // Withdraw (owner).
    // ownership: owner = 0%, alice = 100%, bob = 0%
    // base fees: owner = 0, alice = 0.125, bob = 0
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let wd_owner = solver.withdraw_public(market_id, dep_owner.shares);

    // Deposit (bob).
    // ownership: owner = 0%, alice = 66.66%, bob = 33.33%
    // base fees: owner = 0, alice = 0.125, bob = 0
    start_prank(CheatTarget::One(solver.contract_address), bob());
    balances = solver.get_balances(market_id);
    solver.deposit(market_id, balances.base_amount / 2, balances.quote_amount / 2);

    // Deposit again (Alice).
    // ownership: owner = 0%, alice = 75%, bob = 25%
    // base fees: owner = 0, alice = 0, bob = 0
    start_prank(CheatTarget::One(solver.contract_address), alice());
    balances = solver.get_balances(market_id);
    let dep_alice_2 = solver
        .deposit(market_id, balances.base_amount / 3, balances.quote_amount / 3);

    // Swap.
    // ownership: owner = 0%, alice = 75%, bob = 25%
    // base fees: owner = 0, alice = 0.15, bob = 0.05
    let params = SwapParams {
        is_buy: false,
        amount: to_e18(40),
        exact_input: true,
        threshold_sqrt_price: Option::None(()),
        threshold_amount: Option::None(()),
        deadline: Option::None(()),
    };
    solver.swap(market_id, params);

    // Check withdrawn fees.
    assert(approx_eq(wd_owner.base_fees, 175000000000000000, 1), 'Owner withdrawn base fees');
    assert(wd_owner.quote_fees == 0, 'Owner withdrawn quote fees');
    assert(approx_eq(dep_alice_2.base_fees, 125000000000000000, 1), 'Alice deposit 2 base fees');
    assert(dep_alice_2.quote_fees == 0, 'Alice deposit 2 quote fees');

    // Check fee amounts.
    let owner_bal = solver.get_user_balances(owner(), market_id);
    let alice_bal = solver.get_user_balances(alice(), market_id);
    let bob_bal = solver.get_user_balances(bob(), market_id);
    assert(owner_bal.base_fees == 0, 'Owner base fees');
    assert(owner_bal.quote_fees == 0, 'Owner quote fees');
    assert(approx_eq(alice_bal.base_fees, 150000000000000000, 1), 'Alice base fees');
    assert(alice_bal.quote_fees == 0, 'Alice quote fees');
    assert(approx_eq(bob_bal.base_fees, 50000000000000000, 1), 'Bob base fees');
    assert(bob_bal.quote_fees == 0, 'Bob quote fees');
}

#[test]
fn test_fps_public_market_multiple_lps_quote() {
    let (
        _base_token, _quote_token, _oracle, _vault_token_class, solver, market_id, _vault_token_opt
    ) =
        before(
        true
    );

    // Disable max skew.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let mut market_params = default_market_params();
    market_params.max_skew = 0;
    let repl_solver = IReplicatingSolverDispatcher { contract_address: solver.contract_address };
    repl_solver.queue_market_params(market_id, market_params);
    repl_solver.set_market_params(market_id);

    // Deposit initial (owner).
    // ownership: owner = 100%, alice = 0%, bob = 0%
    // quote fees: owner = 0, alice = 0, bob = 0
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let base_amount = to_e18(500);
    let quote_amount = to_e18(1000);
    let dep_owner = solver.deposit_initial(market_id, base_amount, quote_amount);

    // Swap.
    // ownership: owner = 100%, alice = 0%, bob = 0%
    // quote fees: owner = 0.05, alice = 0, bob = 0
    let params = SwapParams {
        is_buy: true,
        amount: to_e18(10),
        exact_input: true,
        threshold_sqrt_price: Option::None(()),
        threshold_amount: Option::None(()),
        deadline: Option::None(()),
    };
    solver.swap(market_id, params);

    // Deposit (alice).
    // ownership: owner = 50%, alice = 50%, bob = 0%
    // quote fees: owner = 0.05, alice = 0, bob = 0
    start_prank(CheatTarget::One(solver.contract_address), alice());
    let mut balances = solver.get_balances(market_id);
    solver.deposit(market_id, balances.base_amount, balances.quote_amount);

    // Swap.
    // ownership: owner = 50%, alice = 50%, bob = 0%
    // quote fees: owner = 0.175, alice = 0.125, bob = 0
    let params = SwapParams {
        is_buy: true,
        amount: to_e18(50),
        exact_input: true,
        threshold_sqrt_price: Option::None(()),
        threshold_amount: Option::None(()),
        deadline: Option::None(()),
    };
    solver.swap(market_id, params);

    // Withdraw (owner).
    // ownership: owner = 0%, alice = 100%, bob = 0%
    // quote fees: owner = 0, alice = 0.125, bob = 0
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let wd_owner = solver.withdraw_public(market_id, dep_owner.shares);

    // Deposit (bob).
    // ownership: owner = 0%, alice = 66.66%, bob = 33.33%
    // quote fees: owner = 0, alice = 0.125, bob = 0
    start_prank(CheatTarget::One(solver.contract_address), bob());
    balances = solver.get_balances(market_id);
    solver.deposit(market_id, balances.base_amount / 2, balances.quote_amount / 2);

    // Deposit again (Alice).
    // ownership: owner = 0%, alice = 75%, bob = 25%
    // quote fees: owner = 0, alice = 0, bob = 0
    start_prank(CheatTarget::One(solver.contract_address), alice());
    balances = solver.get_balances(market_id);
    let dep_alice_2 = solver
        .deposit(market_id, balances.base_amount / 3, balances.quote_amount / 3);

    // Swap.
    // ownership: owner = 0%, alice = 75%, bob = 25%
    // quote fees: owner = 0, alice = 0.15, bob = 0.05
    let params = SwapParams {
        is_buy: true,
        amount: to_e18(40),
        exact_input: true,
        threshold_sqrt_price: Option::None(()),
        threshold_amount: Option::None(()),
        deadline: Option::None(()),
    };
    solver.swap(market_id, params);

    // Check withdrawn fees.
    assert(wd_owner.base_fees == 0, 'Owner withdrawn base fees');
    assert(approx_eq(wd_owner.quote_fees, 175000000000000000, 1), 'Owner withdrawn quote fees');
    assert(dep_alice_2.base_fees == 0, 'Alice deposit 2 base fees');
    assert(approx_eq(dep_alice_2.quote_fees, 125000000000000000, 1), 'Alice deposit 2 quote fees');

    // Check fee amounts.
    let owner_bal = solver.get_user_balances(owner(), market_id);
    let alice_bal = solver.get_user_balances(alice(), market_id);
    let bob_bal = solver.get_user_balances(bob(), market_id);
    assert(owner_bal.base_fees == 0, 'Owner base fees');
    assert(owner_bal.quote_fees == 0, 'Owner quote fees');
    assert(alice_bal.base_fees == 0, 'Alice base fees');
    assert(approx_eq(alice_bal.quote_fees, 150000000000000000, 1), 'Alice quote fees');
    assert(bob_bal.base_fees == 0, 'Bob quote fees');
    assert(approx_eq(bob_bal.quote_fees, 50000000000000000, 1), 'Bob quote fees');
}

#[test]
fn test_fps_public_market_with_withdraw_fees() {
    let (base_token, quote_token, _oracle, _vault_token_class, solver, market_id, vault_token_opt) =
        before(
        true
    );

    // Set withdraw fees.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let withraw_fee_rate = 100;
    solver.set_withdraw_fee(market_id, withraw_fee_rate);

    // Deposit initial.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let base_amount = to_e18(500);
    let quote_amount = to_e18(1000);
    solver.deposit_initial(market_id, base_amount, quote_amount);

    // Swap 1.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let params = SwapParams {
        is_buy: false,
        amount: to_e18(10),
        exact_input: true,
        threshold_sqrt_price: Option::None(()),
        threshold_amount: Option::None(()),
        deadline: Option::None(()),
    };
    solver.swap(market_id, params);

    // Deposit.
    start_prank(CheatTarget::One(solver.contract_address), alice());
    let balances = solver.get_balances(market_id);
    let dep = solver.deposit(market_id, balances.base_amount, balances.quote_amount);

    // Swap 2.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let swap = solver.swap(market_id, params);

    // Snapshot before.
    let vault_token = vault_token_opt.unwrap();
    let bef = snapshot(solver, market_id, base_token, quote_token, vault_token, alice());

    // Withdraw.
    start_prank(CheatTarget::One(solver.contract_address), alice());
    let wd = solver.withdraw_public(market_id, dep.shares);

    // Collect withdraw fees.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let base_withdraw_fees = solver.collect_withdraw_fees(owner(), base_token.contract_address);

    // Snapshot after.
    let aft = snapshot(solver, market_id, base_token, quote_token, vault_token, alice());

    // Check withdrawn fees.
    assert(approx_eq(wd.base_fees, 25000000000000000, 1), 'Base fees');
    assert(wd.quote_fees == 0, 'Quote fees');
    assert(
        approx_eq(
            aft.lp_base_bal - bef.lp_base_bal, (dep.base_amount + swap.amount_in / 2) * 99 / 100, 1
        ),
        'LP base bal'
    );
    assert(
        approx_eq(base_withdraw_fees, (dep.base_amount + swap.amount_in / 2) / 100, 1),
        'Base withdraw fees'
    );
}

#[test]
fn test_fps_swap_with_0_fps_works() {
    let (
        _base_token, _quote_token, _oracle, _vault_token_class, solver, market_id, _vault_token_opt
    ) =
        before(
        true
    );

    // Deposit initial.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let base_amount = to_e18(500);
    let quote_amount = to_e18(1000);
    solver.deposit_initial(market_id, base_amount, quote_amount);

    // Snapshot fps before.
    let market_fps_bef = solver.fees_per_share(market_id);
    let user_fps_bef = solver.user_fees_per_share(market_id, owner());

    // Swap.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let params = SwapParams {
        is_buy: false,
        amount: 10,
        exact_input: true,
        threshold_sqrt_price: Option::None(()),
        threshold_amount: Option::None(()),
        deadline: Option::None(()),
    };
    solver.swap(market_id, params);

    // Snapshot fps after.
    let market_fps_aft = solver.fees_per_share(market_id);
    let user_fps_aft = solver.user_fees_per_share(market_id, owner());

    // Check fps.
    assert(market_fps_bef.base_fps == user_fps_bef.base_fps, 'Market fps before');
    assert(market_fps_bef.quote_fps == user_fps_bef.quote_fps, 'Market fps before');
    assert(market_fps_aft.base_fps == user_fps_aft.base_fps, 'Market fps after');
    assert(market_fps_aft.quote_fps == user_fps_aft.quote_fps, 'Market fps after');
}

#[test]
fn test_fps_mismatched_decimals_extreme_fps_values() {
    let (
        _base_token, _quote_token, oracle, _vault_token_class, solver, market_id, _vault_token_opt
    ) =
        before_custom_decimals(
        true, 18, 6
    );

    // Disable max skew.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let mut market_params = default_market_params();
    market_params.max_skew = 0;
    let repl_solver = IReplicatingSolverDispatcher { contract_address: solver.contract_address };
    repl_solver.queue_market_params(market_id, market_params);
    repl_solver.set_market_params(market_id);

    // Set oracle price.
    start_warp(CheatTarget::One(oracle.contract_address), 1000);
    oracle.set_data_with_USD_hop('ETH', 'USDC', 100000, 8, 999, 5);

    // Deposit initial.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let base_amount = to_e18(1);
    let quote_amount = to_e18(1);
    solver.deposit_initial(market_id, base_amount, quote_amount);

    // Swap.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let params = SwapParams {
        is_buy: true,
        amount: 100000,
        exact_input: true,
        threshold_sqrt_price: Option::None(()),
        threshold_amount: Option::None(()),
        deadline: Option::None(()),
    };
    solver.swap(market_id, params);

    // Check fps and shares.
    let balances = solver.get_user_balances(owner(), market_id);
    assert(balances.quote_fees > 0 && balances.quote_fees < 500, 'Quote fees');
}

///////////////////////////////////
// TESTS - Success cases (Private)
///////////////////////////////////

#[test]
fn test_fps_private_market_withdraws_full_balance() {
    let (
        _base_token, _quote_token, _oracle, _vault_token_class, solver, market_id, _vault_token_opt
    ) =
        before(
        false
    );

    // Deposit initial.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let base_amount = to_e18(500);
    let quote_amount = to_e18(1000);
    solver.deposit_initial(market_id, base_amount, quote_amount);
    let mut market_fps = solver.fees_per_share(market_id);
    let mut user_fps = solver.user_fees_per_share(market_id, owner());
    assert(market_fps.base_fps == 0 && market_fps.quote_fps == 0, 'Market fps init');
    assert(user_fps.base_fps == 0 && user_fps.quote_fps == 0, 'User fps init');

    // Swap.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let params = SwapParams {
        is_buy: false,
        amount: to_e18(10),
        exact_input: true,
        threshold_sqrt_price: Option::None(()),
        threshold_amount: Option::None(()),
        deadline: Option::None(()),
    };
    let swap = solver.swap(market_id, params);
    market_fps = solver.fees_per_share(market_id);
    user_fps = solver.user_fees_per_share(market_id, owner());
    assert(market_fps.base_fps == 0 && market_fps.quote_fps == 0, 'Market fps after swap');
    assert(user_fps.base_fps == 0 && user_fps.quote_fps == 0, 'User fps after swap');

    // Withdraw.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let balances = solver.get_balances(market_id);
    let wd = solver.withdraw_private(market_id, balances.base_amount, balances.quote_amount);
    market_fps = solver.fees_per_share(market_id);
    user_fps = solver.user_fees_per_share(market_id, owner());
    assert(market_fps.base_fps == 0 && market_fps.quote_fps == 0, 'Market fps after withdraw');
    assert(user_fps.base_fps == 0 && user_fps.quote_fps == 0, 'User fps after withdraw');

    // Check withdraw.
    assert(approx_eq(wd.base_fees, swap.fees, 1), 'Base fees');
    assert(wd.quote_fees == 0, 'Quote fees');
}
