
// Local imports.
use haiko_solver_core::{
    types::GovernorParams,
    interfaces::{
        ISolver::{ISolverDispatcher, ISolverDispatcherTrait},
        IGovernor::{IGovernorDispatcher, IGovernorDispatcherTrait, IGovernorHooksDispatcher, IGovernorHooksDispatcherTrait},
    },
};
use haiko_solver_replicating::{
    interfaces::IReplicatingSolver::{IReplicatingSolverDispatcher, IReplicatingSolverDispatcherTrait},
    types::MarketParams,
    tests::helpers::utils::before
};

// Haiko imports.
use haiko_lib::helpers::{
    params::{owner, alice, bob},
    utils::{to_e18, to_e18_u128, to_e28, approx_eq, approx_eq_pct},
};

// External imports.
use openzeppelin::token::erc20::interface::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};
use snforge_std::{
    declare, start_warp, start_prank, stop_prank, CheatTarget, spy_events, SpyOn, EventSpy,
    EventAssertions, EventFetcher, ContractClass, ContractClassTrait
};

// Success cases
//   - Propose and vote passes after reaching quorum
//   - Propose and vote failed before reaching quorum
//   - Propose and vote succeeds after prior failed + expired vote
//   - Propose and vote succeeds after prior succeeded vote (before expiry)
//   - Vote and fully withdraw from vault reduces vote weight
//   - Vote and partially withdraw from vault reduces vote weight
//   - Vote and deposit to vault does not change vote weight
//   - Double voting has no change to vote weight
//   - Voting again after deposit updates balance to new weight
// Events
//   - Emits event after proposing
//   - Emits event after voting
//   - Emits event after vote passes and new params set
// Fail cases
//   - Propose fails if governor not enabled for market
//   - Propose fails if governance params not set
//   - Propose fails if market not public
//   - Propose fails if proposed params unchanged
//   - Propose fails if existing vote ongoing
//   - Propose fails if not vault owner
//   - Propose fails if below min threshold of ownership
//   - Change governor params fails if not owner
//   - Change governor params fails if unchanged
//   - Change governor params fails if quorum zero
//   - Change governor params fails if quorum overflow
//   - Change governor params fails if min ownership zero
//   - Change governor params fails if min ownership overflow
//   - Change governor params fails if duration 0
//   - Vote fails if no shares
//   - Vote fails if no proposal ongoing
//   - Vote fails if proposal expired

////////////////////////////////
// TESTS - Success cases
////////////////////////////////

#[test]
fn test_propose_and_vote() {
    let (
        _base_token, _quote_token, _oracle, _vault_token_class, solver, market_id, _vault_token_opt
    ) =
        before(
        true
    );

    // Set governance params.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let gov_solver = IGovernorDispatcher { contract_address: solver.contract_address };
    gov_solver.change_governor_params(GovernorParams {
        quorum: 5000, // 50%
        min_ownership: 1000, // 0.1%
        duration: 86400,
    });

    // Enable governance for market.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    gov_solver.toggle_governor_enabled(market_id);

    // Initialise two depositors, each with 50% share of pool
    start_prank(CheatTarget::One(solver.contract_address), alice());
    solver.deposit_initial(market_id, to_e18(100), to_e18(500));
    start_prank(CheatTarget::One(solver.contract_address), bob());
    solver.deposit(market_id, to_e18(100), to_e18(500));
    
    // Alice proposes new market params.
    start_prank(CheatTarget::One(solver.contract_address), alice());
    let repl_solver = IReplicatingSolverDispatcher { contract_address: solver.contract_address };
    let new_params = MarketParams {
        min_spread: 987,
        range: 12345,
        max_delta: 676,
        max_skew: 9989,
        base_currency_id: 123456,
        quote_currency_id: 789012,
        min_sources: 10,
        max_age: 200,
    };
    repl_solver.propose_market_params(market_id, new_params);
    
    // Bob votes for new proposal.
    start_prank(CheatTarget::One(solver.contract_address), bob());
    let gov_solver = IGovernorDispatcher{ contract_address: solver.contract_address };
    gov_solver.vote_proposed_market_params(market_id);

    // Get market params.
    let params = repl_solver.market_params(market_id);

    // Run checks.
    assert(new_params.min_spread == params.min_spread, 'Min spread');
    assert(new_params.range == params.range, 'Range');
    assert(new_params.max_delta == params.max_delta, 'Max delta');
    assert(new_params.max_skew == params.max_skew, 'Max skew');
    assert(new_params.base_currency_id == params.base_currency_id, 'Base currency ID');
    assert(new_params.quote_currency_id == params.quote_currency_id, 'Quote currency ID');
    assert(new_params.min_sources == params.min_sources, 'Min sources');
    assert(new_params.max_age == params.max_age, 'Max age');
}
