// Core lib imports.
use starknet::contract_address_const;

// Local imports.
use haiko_solver_replicating::{
    contracts::core::solver::SolverComponent,
    contracts::mocks::mock_pragma_oracle::{
        IMockPragmaOracleDispatcher, IMockPragmaOracleDispatcherTrait
    },
    interfaces::{
        ISolver::{ISolverDispatcher, ISolverDispatcherTrait},
        IVaultToken::{IVaultTokenDispatcher, IVaultTokenDispatcherTrait},
        IReplicatingSolver::{IReplicatingSolverDispatcher, IReplicatingSolverDispatcherTrait},
    },
    types::{core::MarketInfo, replicating::MarketParams},
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
    start_prank, stop_prank, start_warp, declare, spy_events, SpyOn, EventSpy, EventAssertions,
    CheatTarget
};
use openzeppelin::token::erc20::interface::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};

////////////////////////////////
// TESTS - Success cases
////////////////////////////////

#[test]
fn test_set_withdraw_fees() {
    let (
        _base_token, _quote_token, _oracle, _vault_token_class, solver, market_id, _vault_token_opt
    ) =
        before(
        true
    );

    // Set withdraw fees.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let new_fee_rate = 95;
    solver.set_withdraw_fee(market_id, new_fee_rate);

    // Get withdraw fees.
    let fee_rate = solver.withdraw_fee_rate(market_id);

    // Run checks.
    assert(fee_rate == new_fee_rate, 'Fee rate');
}

#[test]
fn test_collect_withdraw_fees() {
    let (
        base_token, quote_token, _oracle, _vault_token_class, solver, market_id, _vault_token_opt
    ) =
        before(
        false
    );

    // Set withdraw fees.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let new_fee_rate = 100;
    solver.set_withdraw_fee(market_id, new_fee_rate);

    // Deposit initial.
    let base_amount = to_e18(100);
    let quote_amount = to_e18(500);
    solver.deposit_initial(market_id, base_amount, quote_amount);

    // Withdraw.
    solver.withdraw(market_id, base_amount, quote_amount);

    // Collect withdraw fees.
    let base_fees = solver.collect_withdraw_fees(owner(), base_token.contract_address);
    let quote_fees = solver.collect_withdraw_fees(owner(), quote_token.contract_address);

    // Run checks.
    assert(base_fees == base_amount / 100, 'Base fees');
    assert(quote_fees == quote_amount / 100, 'Quote fees');
}

////////////////////////////////
// TESTS - Events
////////////////////////////////

#[test]
fn test_set_withdraw_fees_emits_event() {
    let (
        _base_token, _quote_token, _oracle, _vault_token_class, solver, market_id, _vault_token_opt
    ) =
        before(
        true
    );

    // Spy on events.
    let mut spy = spy_events(SpyOn::One(solver.contract_address));

    // Set withdraw fees.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let new_fee_rate = 95;
    solver.set_withdraw_fee(market_id, new_fee_rate);

    // Check events emitted.
    spy
        .assert_emitted(
            @array![
                (
                    solver.contract_address,
                    SolverComponent::Event::SetWithdrawFee(
                        SolverComponent::SetWithdrawFee { market_id, fee_rate: new_fee_rate }
                    )
                )
            ]
        );
}


#[test]
fn test_collect_withdraw_fees_emits_event() {
    let (
        base_token, quote_token, _oracle, _vault_token_class, solver, market_id, _vault_token_opt
    ) =
        before(
        false
    );

    // Set withdraw fees.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let new_fee_rate = 100;
    solver.set_withdraw_fee(market_id, new_fee_rate);

    // Deposit initial.
    let base_amount = to_e18(100);
    let quote_amount = to_e18(500);
    solver.deposit_initial(market_id, base_amount, quote_amount);

    // Spy on events.
    let mut spy = spy_events(SpyOn::One(solver.contract_address));

    // Withdraw.
    solver.withdraw(market_id, base_amount, quote_amount);

    // Collect withdraw fees.
    let base_fees = solver.collect_withdraw_fees(owner(), base_token.contract_address);
    let quote_fees = solver.collect_withdraw_fees(owner(), quote_token.contract_address);

    // Check events emitted.
    spy
        .assert_emitted(
            @array![
                (
                    solver.contract_address,
                    SolverComponent::Event::WithdrawFeeEarned(
                        SolverComponent::WithdrawFeeEarned {
                            market_id, token: base_token.contract_address, amount: base_fees
                        }
                    )
                ),
                (
                    solver.contract_address,
                    SolverComponent::Event::WithdrawFeeEarned(
                        SolverComponent::WithdrawFeeEarned {
                            market_id, token: quote_token.contract_address, amount: quote_fees
                        }
                    )
                ),
                (
                    solver.contract_address,
                    SolverComponent::Event::CollectWithdrawFee(
                        SolverComponent::CollectWithdrawFee {
                            receiver: owner(), token: base_token.contract_address, amount: base_fees
                        }
                    )
                ),
                (
                    solver.contract_address,
                    SolverComponent::Event::CollectWithdrawFee(
                        SolverComponent::CollectWithdrawFee {
                            receiver: owner(),
                            token: quote_token.contract_address,
                            amount: quote_fees
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
#[should_panic(expected: ('FeeOF',))]
fn test_withdraw_fee_overflow() {
    let (
        _base_token, _quote_token, _oracle, _vault_token_class, solver, market_id, _vault_token_opt
    ) =
        before(
        true
    );

    // Set withdraw fees.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    solver.set_withdraw_fee(market_id, 10001);
}

#[test]
#[should_panic(expected: ('FeeUnchanged',))]
fn test_withdraw_fee_unchanged() {
    let (
        _base_token, _quote_token, _oracle, _vault_token_class, solver, market_id, _vault_token_opt
    ) =
        before(
        true
    );

    // Set withdraw fees.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let fee_rate = solver.withdraw_fee_rate(market_id);
    solver.set_withdraw_fee(market_id, fee_rate);
}

#[test]
#[should_panic(expected: ('OnlyOwner',))]
fn test_withdraw_fee_not_owner() {
    let (
        _base_token, _quote_token, _oracle, _vault_token_class, solver, market_id, _vault_token_opt
    ) =
        before(
        true
    );

    // Set withdraw fees.
    start_prank(CheatTarget::One(solver.contract_address), alice());
    solver.set_withdraw_fee(market_id, 5000);
}
