// Core lib imports.
use starknet::syscalls::call_contract_syscall;
use core::starknet::SyscallResultTrait;

// Local imports.
use haiko_solver_core::{
    contracts::governor::{GovernorComponent, GovernorComponent::InternalImpl},
    contracts::mocks::mock_solver::{
        MockSolver, IMockSolverDispatcher, IMockSolverDispatcherTrait, MockMarketParams
    },
    types::governor::GovernorParams,
    interfaces::{
        ISolver::{ISolverDispatcher, ISolverDispatcherTrait},
        IGovernor::{
            IGovernorDispatcher, IGovernorDispatcherTrait, IGovernorHooksDispatcher,
            IGovernorHooksDispatcherTrait
        },
    },
    tests::helpers::{
        utils::{before, before_disable_governance},
        params::{new_market_params, default_market_params, default_governor_params}
    },
};

// Haiko imports.
use haiko_lib::helpers::{
    params::{owner, alice, bob}, utils::{to_e18, to_e18_u128, to_e28, approx_eq, approx_eq_pct},
};

// External imports.
use openzeppelin::token::erc20::interface::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};
use snforge_std::{
    declare, start_warp, start_prank, stop_prank, CheatTarget, spy_events, SpyOn, EventSpy,
    EventAssertions, EventFetcher, ContractClass, ContractClassTrait
};

////////////////////////////////
// TESTS - Success cases
////////////////////////////////

#[test]
fn test_propose_and_vote_passes_after_reaching_quorum() {
    let (_base_token, _quote_token, _vault_token_class, solver, market_id, _vault_token_opt) =
        before(
        true
    );

    // Initialise two depositors, each with 50% share of pool
    start_prank(CheatTarget::One(solver.contract_address), alice());
    solver.deposit_initial(market_id, to_e18(100), to_e18(500));

    start_prank(CheatTarget::One(solver.contract_address), bob());
    solver.deposit(market_id, to_e18(100), to_e18(500));

    // Alice proposes new market params.
    start_prank(CheatTarget::One(solver.contract_address), alice());
    let mock_solver = IMockSolverDispatcher { contract_address: solver.contract_address };
    let new_params = new_market_params();
    mock_solver.propose_market_params(market_id, new_params);

    // Bob votes for new proposal.
    start_prank(CheatTarget::One(solver.contract_address), bob());
    let gov_solver = IGovernorDispatcher { contract_address: solver.contract_address };
    gov_solver.vote_proposed_market_params(market_id);

    // Get market params.
    let params = mock_solver.market_params(market_id);

    // Run checks.
    assert(new_params == params, 'Params unchanged');
}

#[test]
fn test_propose_and_vote_fails_to_pass_quorum() {
    let (_base_token, _quote_token, _vault_token_class, solver, market_id, _vault_token_opt) =
        before(
        true
    );

    // Snapshot existing params.
    let mock_solver = IMockSolverDispatcher { contract_address: solver.contract_address };
    let old_params = mock_solver.market_params(market_id);

    // Initialise two depositors, one with 20% and other with 10% share of pool
    start_prank(CheatTarget::One(solver.contract_address), owner());
    solver.deposit_initial(market_id, to_e18(700), to_e18(3500));
    start_prank(CheatTarget::One(solver.contract_address), alice());
    solver.deposit(market_id, to_e18(200), to_e18(1000));
    start_prank(CheatTarget::One(solver.contract_address), bob());
    solver.deposit(market_id, to_e18(100), to_e18(500));

    // Alice proposes new market params.
    start_warp(CheatTarget::One(solver.contract_address), 1000);
    start_prank(CheatTarget::One(solver.contract_address), alice());
    let new_params = new_market_params();
    mock_solver.propose_market_params(market_id, new_params);

    // Bob votes for new proposal.
    start_prank(CheatTarget::One(solver.contract_address), bob());
    let gov_solver = IGovernorDispatcher { contract_address: solver.contract_address };
    gov_solver.vote_proposed_market_params(market_id);

    // Get market params after vote expires.
    start_warp(CheatTarget::One(solver.contract_address), 100000);
    let params = mock_solver.market_params(market_id);

    // Run checks.
    assert(old_params == params, 'Params changed');
}

#[test]
fn test_propose_vote_succeeds_after_prior_failed_vote() {
    let (_base_token, _quote_token, _vault_token_class, solver, market_id, _vault_token_opt) =
        before(
        true
    );

    // Snapshot existing params.
    let mock_solver = IMockSolverDispatcher { contract_address: solver.contract_address };
    let old_params = mock_solver.market_params(market_id);

    // Initialise two depositors, one with 20% and other with 10% share of pool
    start_prank(CheatTarget::One(solver.contract_address), owner());
    solver.deposit_initial(market_id, to_e18(700), to_e18(3500));
    start_prank(CheatTarget::One(solver.contract_address), alice());
    solver.deposit(market_id, to_e18(200), to_e18(1000));
    start_prank(CheatTarget::One(solver.contract_address), bob());
    solver.deposit(market_id, to_e18(100), to_e18(500));

    // Alice proposes new market params.
    start_warp(CheatTarget::One(solver.contract_address), 1000);
    start_prank(CheatTarget::One(solver.contract_address), alice());
    let new_params = new_market_params();
    mock_solver.propose_market_params(market_id, new_params);

    // Bob votes for new proposal.
    start_prank(CheatTarget::One(solver.contract_address), bob());
    let gov_solver = IGovernorDispatcher { contract_address: solver.contract_address };
    gov_solver.vote_proposed_market_params(market_id);

    // Check params unchanged.
    let mut params = mock_solver.market_params(market_id);
    assert(old_params == params, 'Params changed');

    // Propose a new vote after the first one fails and expires.
    start_warp(CheatTarget::One(solver.contract_address), 100000);
    start_prank(CheatTarget::One(solver.contract_address), alice());
    mock_solver.propose_market_params(market_id, new_params);

    // Owner votes for new proposal.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    gov_solver.vote_proposed_market_params(market_id);

    // Check params changed
    params = mock_solver.market_params(market_id);
    assert(new_params == params, 'Params unchanged');
}

#[test]
fn test_vote_and_fully_withdraw_from_vault_reduces_vote_weight() {
    let (_base_token, _quote_token, _vault_token_class, solver, market_id, _vault_token_opt) =
        before(
        true
    );

    // Initialise two depositors, one with 20% and other with 80% share of pool
    start_prank(CheatTarget::One(solver.contract_address), owner());
    solver.deposit_initial(market_id, to_e18(800), to_e18(4000));
    start_prank(CheatTarget::One(solver.contract_address), alice());
    let (_, _, shares) = solver.deposit(market_id, to_e18(200), to_e18(1000));

    // Alice proposes new market params.
    start_prank(CheatTarget::One(solver.contract_address), alice());
    let new_params = new_market_params();
    let mock_solver = IMockSolverDispatcher { contract_address: solver.contract_address };
    let proposal_id = mock_solver.propose_market_params(market_id, new_params);

    // Snapshot existing shares.
    let gov_solver = IGovernorDispatcher { contract_address: solver.contract_address };
    let alice_shares_bef = gov_solver.user_votes(alice(), proposal_id);
    let total_shares_bef = gov_solver.total_votes(proposal_id);

    // Alice withdraws from vault
    start_prank(CheatTarget::One(solver.contract_address), alice());
    solver.withdraw_public(market_id, shares);

    // Check vote weight reduced
    let alice_shares_aft = gov_solver.user_votes(alice(), proposal_id);
    let total_shares_aft = gov_solver.total_votes(proposal_id);

    assert(alice_shares_aft == 0, 'Alice vote weight');
    assert(total_shares_bef - total_shares_aft == alice_shares_bef, 'Total vote weight');
}

#[test]
fn test_vote_and_partially_withdraw_from_vault_reduces_vote_weight() {
    let (_base_token, _quote_token, _vault_token_class, solver, market_id, _vault_token_opt) =
        before(
        true
    );

    // Initialise two depositors, one with 20% and other with 80% share of pool
    start_prank(CheatTarget::One(solver.contract_address), owner());
    solver.deposit_initial(market_id, to_e18(800), to_e18(4000));
    start_prank(CheatTarget::One(solver.contract_address), alice());
    let (_, _, shares) = solver.deposit(market_id, to_e18(200), to_e18(1000));

    // Alice proposes new market params.
    start_prank(CheatTarget::One(solver.contract_address), alice());
    let new_params = new_market_params();
    let mock_solver = IMockSolverDispatcher { contract_address: solver.contract_address };
    let proposal_id = mock_solver.propose_market_params(market_id, new_params);

    // Snapshot existing shares.
    let gov_solver = IGovernorDispatcher { contract_address: solver.contract_address };
    let alice_shares_bef = gov_solver.user_votes(alice(), proposal_id);
    let total_shares_bef = gov_solver.total_votes(proposal_id);

    // Alice partially withdraws from vault
    start_prank(CheatTarget::One(solver.contract_address), alice());
    solver.withdraw_public(market_id, shares / 2);

    // Check vote weight reduced
    let alice_shares_aft = gov_solver.user_votes(alice(), proposal_id);
    let total_shares_aft = gov_solver.total_votes(proposal_id);

    assert(alice_shares_aft == alice_shares_bef - shares / 2, 'Alice vote weight');
    assert(total_shares_bef - total_shares_aft == shares / 2, 'Total vote weight');
}

#[test]
fn test_vote_and_deposit_to_vault_does_not_change_vote_weight() {
    let (_base_token, _quote_token, _vault_token_class, solver, market_id, _vault_token_opt) =
        before(
        true
    );

    // Initialise two depositors, one with 20% and other with 80% share of pool
    start_prank(CheatTarget::One(solver.contract_address), owner());
    solver.deposit_initial(market_id, to_e18(800), to_e18(4000));
    start_prank(CheatTarget::One(solver.contract_address), alice());
    let (_, _, shares) = solver.deposit(market_id, to_e18(200), to_e18(1000));

    // Alice proposes new market params.
    start_prank(CheatTarget::One(solver.contract_address), alice());
    let new_params = new_market_params();
    let mock_solver = IMockSolverDispatcher { contract_address: solver.contract_address };
    let proposal_id = mock_solver.propose_market_params(market_id, new_params);

    // Alice deposits more to vault
    solver.deposit(market_id, to_e18(200), to_e18(1000));

    // Check vote weight reduced
    let gov_solver = IGovernorDispatcher { contract_address: solver.contract_address };
    let alice_shares = gov_solver.user_votes(alice(), proposal_id);
    let total_shares = gov_solver.total_votes(proposal_id);

    assert(alice_shares == shares, 'Alice vote weight');
    assert(total_shares == shares, 'Total vote weight');
}

#[test]
fn test_double_voting_does_not_change_vote_weight() {
    let (_base_token, _quote_token, _vault_token_class, solver, market_id, _vault_token_opt) =
        before(
        true
    );

    // Initialise two depositors, one with 20% and other with 10% share of pool
    start_prank(CheatTarget::One(solver.contract_address), owner());
    solver.deposit_initial(market_id, to_e18(700), to_e18(3500));
    start_prank(CheatTarget::One(solver.contract_address), alice());
    solver.deposit(market_id, to_e18(200), to_e18(1000));
    start_prank(CheatTarget::One(solver.contract_address), bob());
    let (_, _, shares) = solver.deposit(market_id, to_e18(100), to_e18(500));

    // Alice proposes new market params.
    start_prank(CheatTarget::One(solver.contract_address), alice());
    let new_params = new_market_params();
    let mock_solver = IMockSolverDispatcher { contract_address: solver.contract_address };
    let proposal_id = mock_solver.propose_market_params(market_id, new_params);

    // Bob votes for new proposal.
    start_prank(CheatTarget::One(solver.contract_address), bob());
    let gov_solver = IGovernorDispatcher { contract_address: solver.contract_address };
    gov_solver.vote_proposed_market_params(market_id);

    // Snapshot shares.
    let bob_shares_bef = gov_solver.user_votes(bob(), proposal_id);
    let total_shares_bef = gov_solver.total_votes(proposal_id);

    // Bob votes again for new proposal.
    gov_solver.vote_proposed_market_params(market_id);

    // Check vote weight.
    let bob_shares_aft = gov_solver.user_votes(bob(), proposal_id);
    let total_shares_aft = gov_solver.total_votes(proposal_id);

    assert(bob_shares_bef == shares, 'Bob vote weight');
    assert(bob_shares_bef == bob_shares_aft, 'Bob vote weight unchanged');
    assert(total_shares_bef == total_shares_aft, 'Total vote weight unchanged');
}

#[test]
fn test_voting_after_new_deposit_updates_balance_to_new_weight() {
    let (_base_token, _quote_token, _vault_token_class, solver, market_id, _vault_token_opt) =
        before(
        true
    );

    // Initialise two depositors, one with 20% and other with 10% share of pool
    start_prank(CheatTarget::One(solver.contract_address), owner());
    solver.deposit_initial(market_id, to_e18(700), to_e18(3500));
    start_prank(CheatTarget::One(solver.contract_address), alice());
    solver.deposit(market_id, to_e18(200), to_e18(1000));
    start_prank(CheatTarget::One(solver.contract_address), bob());
    let (_, _, shares) = solver.deposit(market_id, to_e18(100), to_e18(500));

    // Alice proposes new market params.
    start_prank(CheatTarget::One(solver.contract_address), alice());
    let new_params = new_market_params();
    let mock_solver = IMockSolverDispatcher { contract_address: solver.contract_address };
    let proposal_id = mock_solver.propose_market_params(market_id, new_params);

    // Bob votes for new proposal.
    start_prank(CheatTarget::One(solver.contract_address), bob());
    let gov_solver = IGovernorDispatcher { contract_address: solver.contract_address };
    gov_solver.vote_proposed_market_params(market_id);

    // Bob deposits more to vault
    let (_, _, new_shares) = solver.deposit(market_id, to_e18(100), to_e18(500));

    // Bob votes again for new proposal.
    gov_solver.vote_proposed_market_params(market_id);

    // Check vote weight.
    let bob_shares = gov_solver.user_votes(bob(), proposal_id);
    assert(bob_shares == shares + new_shares, 'Bob vote weight');
}

////////////////////////////////
// TESTS - Events
////////////////////////////////

fn test_propose_vote_emits_event() {
    let (_base_token, _quote_token, _vault_token_class, solver, market_id, _vault_token_opt) =
        before(
        true
    );

    // Initialise two depositors, one with 20% and other with 80% share of pool
    start_prank(CheatTarget::One(solver.contract_address), owner());
    solver.deposit_initial(market_id, to_e18(800), to_e18(4000));
    start_prank(CheatTarget::One(solver.contract_address), alice());
    solver.deposit(market_id, to_e18(200), to_e18(1000));

    // Spy on events.
    let mut spy = spy_events(SpyOn::One(solver.contract_address));

    // Alice proposes new market params.
    start_prank(CheatTarget::One(solver.contract_address), alice());
    let new_params = new_market_params();
    let mock_solver = IMockSolverDispatcher { contract_address: solver.contract_address };
    let proposal_id = mock_solver.propose_market_params(market_id, new_params);

    // Check events emitted.
    spy
        .assert_emitted(
            @array![
                (
                    solver.contract_address,
                    MockSolver::Event::ProposeMarketParams(
                        MockSolver::ProposeMarketParams {
                            market_id, proposal_id, foo: new_params.foo, bar: new_params.bar,
                        }
                    )
                )
            ]
        );
}

fn test_vote_for_proposal_emits_event() {
    let (_base_token, _quote_token, _vault_token_class, solver, market_id, _vault_token_opt) =
        before(
        true
    );

    // Initialise two depositors, one with 20% and other with 10% share of pool
    start_prank(CheatTarget::One(solver.contract_address), owner());
    solver.deposit_initial(market_id, to_e18(700), to_e18(3500));
    start_prank(CheatTarget::One(solver.contract_address), alice());
    solver.deposit(market_id, to_e18(200), to_e18(1000));
    start_prank(CheatTarget::One(solver.contract_address), bob());
    let (_, _, shares) = solver.deposit(market_id, to_e18(100), to_e18(500));

    // Alice proposes new market params.
    start_prank(CheatTarget::One(solver.contract_address), alice());
    let new_params = new_market_params();
    let mock_solver = IMockSolverDispatcher { contract_address: solver.contract_address };
    let proposal_id = mock_solver.propose_market_params(market_id, new_params);

    // Spy on events.
    let mut spy = spy_events(SpyOn::One(solver.contract_address));

    // Bob votes for new proposal.
    start_prank(CheatTarget::One(solver.contract_address), bob());
    let gov_solver = IGovernorDispatcher { contract_address: solver.contract_address };
    gov_solver.vote_proposed_market_params(market_id);

    // Check events emitted.
    spy
        .assert_emitted(
            @array![
                (
                    solver.contract_address,
                    GovernorComponent::Event::VoteMarketParams(
                        GovernorComponent::VoteMarketParams {
                            market_id, proposal_id, caller: bob(), shares,
                        }
                    )
                )
            ]
        );
}

fn test_passing_proposal_emits_event() {
    let (_base_token, _quote_token, _vault_token_class, solver, market_id, _vault_token_opt) =
        before(
        true
    );

    // Initialise two depositors, one with 20% and other with 80% share of pool
    start_prank(CheatTarget::One(solver.contract_address), alice());
    solver.deposit_initial(market_id, to_e18(200), to_e18(1000));
    start_prank(CheatTarget::One(solver.contract_address), bob());
    solver.deposit(market_id, to_e18(800), to_e18(4000));

    // Alice proposes new market params.
    start_prank(CheatTarget::One(solver.contract_address), alice());
    let new_params = new_market_params();
    let mock_solver = IMockSolverDispatcher { contract_address: solver.contract_address };
    mock_solver.propose_market_params(market_id, new_params);

    // Spy on events.
    let mut spy = spy_events(SpyOn::One(solver.contract_address));

    // Bob votes for new proposal.
    start_prank(CheatTarget::One(solver.contract_address), bob());
    let gov_solver = IGovernorDispatcher { contract_address: solver.contract_address };
    gov_solver.vote_proposed_market_params(market_id);

    // Check events emitted.
    spy
        .assert_emitted(
            @array![
                (
                    solver.contract_address,
                    MockSolver::Event::SetMarketParams(
                        MockSolver::SetMarketParams {
                            market_id, foo: new_params.foo, bar: new_params.bar,
                        }
                    )
                ),
            ]
        );
}

////////////////////////////////
// TESTS - Fail cases
////////////////////////////////

#[test]
#[should_panic(expected: ('NotEnabled',))]
fn test_propose_fails_if_governor_not_enabled_for_market() {
    let (_base_token, _quote_token, _vault_token_class, solver, market_id, _vault_token_opt) =
        before_disable_governance(
        true
    );

    // Set governance params.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let gov_solver = IGovernorDispatcher { contract_address: solver.contract_address };
    gov_solver.change_governor_params(default_governor_params());

    // Deposit shares.
    solver.deposit_initial(market_id, to_e18(200), to_e18(1000));

    // Propose new market params.
    let new_params = new_market_params();
    let mock_solver = IMockSolverDispatcher { contract_address: solver.contract_address };
    mock_solver.propose_market_params(market_id, new_params);
}

#[test]
#[should_panic(expected: ('ParamsNotSet',))]
fn test_propose_fails_if_governor_params_not_set() {
    let (_base_token, _quote_token, _vault_token_class, solver, market_id, _vault_token_opt) =
        before_disable_governance(
        true
    );

    // Enable governance.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let gov_solver = IGovernorDispatcher { contract_address: solver.contract_address };
    gov_solver.toggle_governor_enabled(market_id);

    // Deposit shares.
    solver.deposit_initial(market_id, to_e18(200), to_e18(1000));

    // Propose new market params.
    let new_params = new_market_params();
    let mock_solver = IMockSolverDispatcher { contract_address: solver.contract_address };
    mock_solver.propose_market_params(market_id, new_params);
}

#[test]
#[should_panic(expected: ('NotPublic',))]
fn test_propose_fails_if_market_private() {
    let (_base_token, _quote_token, _vault_token_class, solver, market_id, _vault_token_opt) =
        before(
        false
    );

    // Deposit shares.
    solver.deposit_initial(market_id, to_e18(200), to_e18(1000));

    // Propose new market params.
    let new_params = new_market_params();
    let mock_solver = IMockSolverDispatcher { contract_address: solver.contract_address };
    mock_solver.propose_market_params(market_id, new_params);
}

#[test]
#[should_panic(expected: ('ParamsUnchanged',))]
fn test_propose_fails_if_proposed_params_unchanged() {
    let (_base_token, _quote_token, _vault_token_class, solver, market_id, _vault_token_opt) =
        before(
        true
    );

    // Deposit shares.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    solver.deposit_initial(market_id, to_e18(200), to_e18(1000));

    // Propose new market params.
    let mock_solver = IMockSolverDispatcher { contract_address: solver.contract_address };
    mock_solver.propose_market_params(market_id, default_market_params());
}

#[test]
#[should_panic(expected: ('VoteOngoing',))]
fn test_propose_fails_if_existing_vote_ongoing() {
    let (_base_token, _quote_token, _vault_token_class, solver, market_id, _vault_token_opt) =
        before(
        true
    );

    // Deposit shares for two LPs.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    solver.deposit_initial(market_id, to_e18(200), to_e18(1000));
    start_prank(CheatTarget::One(solver.contract_address), alice());
    solver.deposit(market_id, to_e18(200), to_e18(1000));

    // First LP proposes new market params.
    start_prank(CheatTarget::One(solver.contract_address), alice());
    let mock_solver = IMockSolverDispatcher { contract_address: solver.contract_address };
    mock_solver.propose_market_params(market_id, new_market_params());

    // Second LP proposes new market params.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    mock_solver.propose_market_params(market_id, new_market_params());
}

#[test]
#[should_panic(expected: ('SharesTooLow',))]
fn test_propose_fails_if_not_vault_owner() {
    let (_base_token, _quote_token, _vault_token_class, solver, market_id, _vault_token_opt) =
        before(
        true
    );

    // Non-depositor proposes new market params.
    start_prank(CheatTarget::One(solver.contract_address), alice());
    let mock_solver = IMockSolverDispatcher { contract_address: solver.contract_address };
    mock_solver.propose_market_params(market_id, new_market_params());
}

#[test]
#[should_panic(expected: ('SharesTooLow',))]
fn test_propose_fails_if_caller_below_min_ownership_threshold() {
    let (_base_token, _quote_token, _vault_token_class, solver, market_id, _vault_token_opt) =
        before(
        true
    );

    // Deposit shares for two LPs.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    solver.deposit_initial(market_id, to_e18(200), to_e18(1000));
    start_prank(CheatTarget::One(solver.contract_address), alice());
    solver.deposit(market_id, 20, 1000);

    // Depositor below min threshold proposes new market params.
    let mock_solver = IMockSolverDispatcher { contract_address: solver.contract_address };
    mock_solver.propose_market_params(market_id, new_market_params());
}

#[test]
#[should_panic(expected: ('OnlyOwner',))]
fn test_change_governor_params_fails_if_not_owner() {
    let (_base_token, _quote_token, _vault_token_class, solver, _market_id, _vault_token_opt) =
        before(
        true
    );

    // Change governor params.
    start_prank(CheatTarget::One(solver.contract_address), alice());
    let gov_solver = IGovernorDispatcher { contract_address: solver.contract_address };
    gov_solver.change_governor_params(default_governor_params());
}

#[test]
#[should_panic(expected: ('ParamsUnchanged',))]
fn test_change_governor_params_fails_if_unchanged() {
    let (_base_token, _quote_token, _vault_token_class, solver, _market_id, _vault_token_opt) =
        before(
        true
    );

    // Change governor params.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let gov_solver = IGovernorDispatcher { contract_address: solver.contract_address };
    gov_solver.change_governor_params(default_governor_params());
}

#[test]
#[should_panic(expected: ('QuorumZero',))]
fn test_change_governor_params_fails_if_quorum_zero() {
    let (_base_token, _quote_token, _vault_token_class, solver, _market_id, _vault_token_opt) =
        before(
        true
    );

    // Change governor params.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let gov_solver = IGovernorDispatcher { contract_address: solver.contract_address };
    let mut params = default_governor_params();
    params.quorum = 0;
    gov_solver.change_governor_params(params);
}

#[test]
#[should_panic(expected: ('QuorumOF',))]
fn test_change_governor_params_fails_if_quorum_overflow() {
    let (_base_token, _quote_token, _vault_token_class, solver, _market_id, _vault_token_opt) =
        before(
        true
    );

    // Change governor params.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let gov_solver = IGovernorDispatcher { contract_address: solver.contract_address };
    let mut params = default_governor_params();
    params.quorum = 10001;
    gov_solver.change_governor_params(params);
}

#[test]
#[should_panic(expected: ('OwnershipZero',))]
fn test_change_governor_params_fails_if_min_ownership_zero() {
    let (_base_token, _quote_token, _vault_token_class, solver, _market_id, _vault_token_opt) =
        before(
        true
    );

    // Change governor params.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let gov_solver = IGovernorDispatcher { contract_address: solver.contract_address };
    let mut params = default_governor_params();
    params.min_ownership = 0;
    gov_solver.change_governor_params(params);
}

#[test]
#[should_panic(expected: ('OwnershipOF',))]
fn test_change_governor_params_fails_if_min_ownership_overflow() {
    let (_base_token, _quote_token, _vault_token_class, solver, _market_id, _vault_token_opt) =
        before(
        true
    );

    // Change governor params.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let gov_solver = IGovernorDispatcher { contract_address: solver.contract_address };
    let mut params = default_governor_params();
    params.min_ownership = 1000001;
    gov_solver.change_governor_params(params);
}

#[test]
#[should_panic(expected: ('DurationZero',))]
fn test_change_governor_params_fails_if_duration_zero() {
    let (_base_token, _quote_token, _vault_token_class, solver, _market_id, _vault_token_opt) =
        before(
        true
    );

    // Change governor params.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let gov_solver = IGovernorDispatcher { contract_address: solver.contract_address };
    let mut params = default_governor_params();
    params.duration = 0;
    gov_solver.change_governor_params(params);
}

#[test]
#[should_panic(expected: ('NoShares',))]
fn test_vote_fails_if_caller_has_no_shares() {
    let (_base_token, _quote_token, _vault_token_class, solver, market_id, _vault_token_opt) =
        before(
        true
    );

    // Deposit shares for 2 LPs.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    solver.deposit_initial(market_id, to_e18(200), to_e18(1000));
    start_prank(CheatTarget::One(solver.contract_address), alice());
    solver.deposit(market_id, to_e18(800), to_e18(4000));

    // Propose new market params.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let mock_solver = IMockSolverDispatcher { contract_address: solver.contract_address };
    mock_solver.propose_market_params(market_id, new_market_params());

    // Vote for proposal.
    start_prank(CheatTarget::One(solver.contract_address), bob());
    let gov_solver = IGovernorDispatcher { contract_address: solver.contract_address };
    gov_solver.vote_proposed_market_params(market_id);
}

#[test]
#[should_panic(expected: ('NoProposal',))]
fn test_vote_fails_if_no_proposal_ongoing() {
    let (_base_token, _quote_token, _vault_token_class, solver, market_id, _vault_token_opt) =
        before(
        true
    );

    // Deposit shares.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    solver.deposit_initial(market_id, to_e18(200), to_e18(1000));

    // Vote for non-existent proposal.
    let gov_solver = IGovernorDispatcher { contract_address: solver.contract_address };
    gov_solver.vote_proposed_market_params(market_id);
}

#[test]
#[should_panic(expected: ('ProposalExpired',))]
fn test_vote_fails_if_proposal_expired() {
    let (_base_token, _quote_token, _vault_token_class, solver, market_id, _vault_token_opt) =
        before(
        true
    );

    // Deposit shares for 2 LPs.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    solver.deposit_initial(market_id, to_e18(200), to_e18(1000));
    start_prank(CheatTarget::One(solver.contract_address), alice());
    solver.deposit(market_id, to_e18(800), to_e18(4000));

    // Propose new market params.
    start_warp(CheatTarget::One(solver.contract_address), 1000);
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let mock_solver = IMockSolverDispatcher { contract_address: solver.contract_address };
    mock_solver.propose_market_params(market_id, new_market_params());

    // Vote for proposal.
    start_warp(CheatTarget::One(solver.contract_address), 100000);
    start_prank(CheatTarget::One(solver.contract_address), alice());
    let gov_solver = IGovernorDispatcher { contract_address: solver.contract_address };
    gov_solver.vote_proposed_market_params(market_id);
}

#[test]
#[should_panic(expected: ('NoEntryPoint',))]
fn test_non_contract_caller_cannot_call_propose_market_params_internal_fn() {
    let (_base_token, _quote_token, _vault_token_class, solver, market_id, _vault_token_opt) =
        before(
        true
    );

    // Non-contract calls set market params internal fn.
    start_prank(CheatTarget::One(solver.contract_address), alice());
    match call_contract_syscall(
        solver.contract_address, selector!("_propose_market_params"), array![market_id].span(),
    ) {
        Result::Ok(_) => (),
        Result::Err(_) => assert(false, 'NoEntryPoint'),
    }
}

#[test]
#[should_panic(expected: ('NotSolver',))]
fn test_non_contract_caller_cannot_call_after_withdraw_governor_hook() {
    let (_base_token, _quote_token, _vault_token_class, solver, market_id, _vault_token_opt) =
        before(
        true
    );

    // Non-contract calls after withdraw hook.
    start_prank(CheatTarget::One(solver.contract_address), alice());
    let gov_solver = IGovernorDispatcher { contract_address: solver.contract_address };
    gov_solver.after_withdraw_governor(market_id, alice(), to_e18(100));
}
