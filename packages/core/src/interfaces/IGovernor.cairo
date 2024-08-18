use starknet::ContractAddress;
use haiko_solver_core::types::governor::{GovernorParams, Proposal};

#[starknet::interface]
pub trait IGovernor<TContractState> {
    // Get governance parameters.
    //
    // # Returns
    // * `params` - governance params
    fn governor_params(self: @TContractState) -> GovernorParams;

    // Check if market-level governance is enabled.
    //
    // # Params
    // * `market_id` - market id
    //
    // # Returns
    // * `enabled` - whether governance is enabled
    fn governor_enabled(self: @TContractState, market_id: felt252) -> bool;

    // Get current proposal id for market.
    // This can be the current active proposal, or the last expired one.
    //
    // # Params
    // * `market_id` - market id
    //
    // # Returns
    // * `proposal_id` - proposal id
    fn current_proposal(self: @TContractState, market_id: felt252) -> felt252;

    // Get market param proposal.
    //
    // # Params
    // * `proposal_id` - proposal id
    //
    // # Returns
    // * `proposal` - proposal details
    fn proposal(self: @TContractState, proposal_id: felt252) -> Proposal;

    // Get user vote weight for proposal.
    //
    // # Params
    // * `caller` - caller address
    // * `proposal_id` - proposal id
    //
    // # Returns
    // * `shares` - user vote weight
    fn user_votes(
        self: @TContractState, caller: ContractAddress, proposal_id: felt252
    ) -> u256;

    // Get total votes for proposal.
    //
    // # Params
    // `proposal_id` - proposal id
    //
    // # Returns
    // * `total_votes` - total votes for proposal
    fn total_votes(self: @TContractState, proposal_id: felt252) -> u256;

    // Get last assigned proposal id.
    //
    // # Returns
    // * `last_proposal_id` - last proposal id
    fn last_proposal_id(self: @TContractState) -> felt252;

    // Enable or disable governor for market.
    //
    // # Params
    // * `market_id` - market id
    fn toggle_governor_enabled(ref self: TContractState, market_id: felt252);

    // Change quorum, minimum vote ownership or vote duration.
    // Only callable by market owner.
    // 
    // # Params
    // * `params` - governance params
    fn change_governor_params(ref self: TContractState, params: GovernorParams);

    // Vote for the current active proposed market params.
    // Autotomatically passes params if quorum is reached.
    //
    // # Params
    // * `market_id` - market id
    fn vote_proposed_market_params(ref self: TContractState, market_id: felt252);

    // After withdraw hook call to be called by solver implementation to update vote balances
    // when depositor withdraws.
    //
    // # Params
    // * `market_id` - market id
    // * `depositor` - depositor address
    // * `shares` - shares withdrawn
    fn after_withdraw_governor(
        ref self: TContractState, market_id: felt252, depositor: ContractAddress, shares: u256
    );
}

#[starknet::interface]
pub trait IGovernorHooks<TContractState> {
    // Hook called to set a passed market param.
    // Should be implemented by solver to set the passed market params in state.
    // Should emit any relevant events.
    //
    // # Params
    // * `market_id` - market id
    fn set_passed_market_params(ref self: TContractState, market_id: felt252, proposal_id: felt252);
// In addition, the solver should implement `propose_market_params`, defined over its unique 
// market param type. This is currently not explicit defined in the IGovernanceHooks interface
// because Starknet interfaces do not support generics. Illustrative example below:
//
// # Params
// * `market_id` - market id
// * `params` - proposed market params
// fn propose_market_params(
//     ref self: ContractState, market_id: felt252, params: MarketParams
// ) -> felt252 {}
}
