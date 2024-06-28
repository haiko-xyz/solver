// Core lib imports.
use starknet::ContractAddress;
use starknet::class_hash::ClassHash;

// Local imports.
use haiko_solver::types::core::{SwapParams, PositionInfo};
use haiko_solver::types::replicating::MarketParams;

#[starknet::interface]
pub trait IReplicatingSolver<TContractState> {
    // Configurable market parameters
    fn market_params(self: @TContractState, market_id: felt252) -> MarketParams;

    // Pragma oracle contract address
    fn oracle(self: @TContractState) -> ContractAddress;

    // Get price from oracle feed.
    // 
    // # Returns
    // * `price` - oracle price
    // * `is_valid` - whether oracle price passes validity checks re number of sources and age
    fn get_oracle_price(self: @TContractState, market_id: felt252) -> (u256, bool);

    // Change parameters of the solver market.
    // Only callable by market owner.
    //
    // # Params
    // * `market_id` - market id
    // * `params` - market params
    fn set_market_params(ref self: TContractState, market_id: felt252, params: MarketParams);

    // Change the oracle contract address.
    //
    // # Arguments
    // * `oracle` - contract address of oracle feed
    fn change_oracle(ref self: TContractState, oracle: ContractAddress);
}
