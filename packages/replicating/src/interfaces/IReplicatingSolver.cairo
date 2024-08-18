// Core lib imports.
use starknet::ContractAddress;
use starknet::class_hash::ClassHash;

// Local imports.
use haiko_solver_core::types::solver::PositionInfo;
use haiko_solver_replicating::types::MarketParams;

#[starknet::interface]
pub trait IReplicatingSolver<TContractState> {
    // Market parameters
    fn market_params(self: @TContractState, market_id: felt252) -> MarketParams;

    // Queued market parameters
    fn queued_market_params(self: @TContractState, market_id: felt252) -> MarketParams;

    // Delay (in seconds) for setting market parameters
    fn delay(self: @TContractState) -> u64;

    // Pragma oracle contract address
    fn oracle(self: @TContractState) -> ContractAddress;

    // Get price from oracle feed.
    // 
    // # Returns
    // * `price` - oracle price
    // * `is_valid` - whether oracle price passes validity checks re number of sources and age
    fn get_oracle_price(self: @TContractState, market_id: felt252) -> (u256, bool);

    // Queue change to the parameters of the solver market.
    // This must be accepted after the set delay in order for the change to be applied.
    // Only callable by market owner.
    //
    // # Params
    // * `market_id` - market id
    // * `params` - market params
    fn queue_market_params(ref self: TContractState, market_id: felt252, params: MarketParams);

    // Confirm and set queued market parameters.
    // Must have been queued for at least the set delay.
    // Only callable by market owner.
    //
    // # Params
    // * `market_id` - market id
    // * `params` - market params
    fn set_market_params(ref self: TContractState, market_id: felt252);

    // Propose market params for a solver market with governance enabled.
    // Only callable by market depositors. Should implement checks of proposed parameters and
    // emit relevant events.
    //
    // # Params
    // * `market_id` - market id
    // * `params` - proposed market params
    //
    // # Returns
    // * `proposal_id` - proposal id
    fn propose_market_params(
        ref self: TContractState, market_id: felt252, params: MarketParams
    ) -> felt252;

    // Set delay (in seconds) for changing market parameters
    // Only callable by owner.
    //
    // # Params
    // * `delay` - delay in blocks
    fn set_delay(ref self: TContractState, delay: u64);


    // Change the oracle contract address.
    //
    // # Arguments
    // * `oracle` - contract address of oracle feed
    fn change_oracle(ref self: TContractState, oracle: ContractAddress);

    // Query virtual liquidity positions against which swaps are executed.
    // 
    // # Arguments
    // * `market_id` - market id
    //
    // # Returns
    // * `bid` - bid position
    // * `ask` - ask position
    fn get_virtual_positions(
        self: @TContractState, market_id: felt252
    ) -> (PositionInfo, PositionInfo);
}
