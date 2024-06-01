// TODO: move this to a central repo

use haiko_solver_replicating::types::core::SwapParams;

#[starknet::interface]
pub trait ISolver<TContractState> {
    // Obtain quote for swap through a market.
    // 
    // # Arguments
    // * `market_id` - market id
    // * `swap_params` - swap parameters
    //
    // # Returns
    // * `amount_in` - amount in
    // * `amount_out` - amount out
    fn quote(self: @TContractState, market_id: felt252, swap_params: SwapParams,) -> (u256, u256);

    // Swap through a market.
    // 
    // # Arguments
    // * `market_id` - market id
    // * `swap_params` - swap parameters
    //
    // # Returns
    // * `amount_in` - amount in
    // * `amount_out` - amount out
    fn swap(ref self: TContractState, market_id: felt252, swap_params: SwapParams,) -> (u256, u256);
}
