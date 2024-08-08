// Core lib imports.
use starknet::ContractAddress;
use starknet::class_hash::ClassHash;

// Local imports.
use haiko_solver_core::types::PositionInfo;
use haiko_solver_reversion::types::{Trend, MarketParams};
use haiko_solver_reversion::interfaces::pragma::PragmaPricesResponse;

#[starknet::interface]
pub trait IReversionSolver<TContractState> {
    // Market parameters
    fn market_params(self: @TContractState, market_id: felt252) -> MarketParams;

    // Queued market parameters
    fn queued_market_params(self: @TContractState, market_id: felt252) -> MarketParams;

    // Delay (in seconds) for setting market parameters
    fn delay(self: @TContractState) -> u64;

    // Pragma oracle contract address
    fn oracle(self: @TContractState) -> ContractAddress;

    // Trend setter contract address
    fn trend_setter(self: @TContractState) -> ContractAddress;
    
    // Get trend of solver market.
    fn trend(self: @TContractState, market_id: felt252) -> Trend;

    // Get unscaled oracle price from oracle feed.
    // 
    // # Arguments
    // * `market_id` - market id
    //
    // # Returns
    // * `output` - Pragma oracle price response
    fn get_unscaled_oracle_price(self: @TContractState, market_id: felt252) -> PragmaPricesResponse;

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

    // Set delay (in seconds) for changing market parameters
    // Only callable by owner.
    //
    // # Params
    // * `delay` - delay in blocks
    fn set_delay(ref self: TContractState, delay: u64);

    // Change trend of the solver market.
    // Only callable by market owner.
    //
    // # Params
    // * `market_id` - market id
    // * `trend - market trend
    fn set_trend(ref self: TContractState, market_id: felt252, trend: Trend);

    // Change the oracle contract address.
    //
    // # Arguments
    // * `oracle` - contract address of oracle feed
    fn change_oracle(ref self: TContractState, oracle: ContractAddress);

    // Change the trend setter.
    //
    // # Arguments
    // * `trend_setter` - contract address of trend setter admin
    fn change_trend_setter(ref self: TContractState, trend_setter: ContractAddress);

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
