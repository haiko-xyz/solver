// Core lib imports.
use starknet::ContractAddress;
use starknet::class_hash::ClassHash;

// Local imports.
use haiko_solver_replicating::types::replicating::{MarketParams, MarketState, MarketInfo};

#[starknet::interface]
pub trait IReplicatingSolver<TContractState> {
    // Market id
    fn market_id(self: @TContractState, market_info: MarketInfo) -> felt252;
    
    // Immutable market information
    fn market_info(self: @TContractState, market_id: felt252) -> MarketInfo;

    // Configurable market parameters
    fn market_params(self: @TContractState, market_id: felt252) -> MarketParams;
    
    // Market state
    fn market_state(self: @TContractState, market_id: felt252) -> MarketState;
    
    // Pragma oracle contract address
    fn oracle(self: @TContractState) -> ContractAddress;

    // ERC20 vault token class hash
    fn vault_token_class(self: @TContractState) -> ClassHash; 
    
    // Contract owner
    fn owner(self: @TContractState) -> ContractAddress;

    // Queued contract owner, used for ownership transfers
    fn queued_owner(self: @TContractState) -> ContractAddress;

    // Withdraw fee rate for a given market
    fn withdraw_fee_rate(self: @TContractState, market_id: felt252) -> u16;

    // Accumulated withdraw fee balance for a given asset
    fn withdraw_fees(self: @TContractState, token: ContractAddress) -> u256;

    // Get price from oracle feed.
    // 
    // # Returns
    // * `price` - oracle price
    // * `is_valid` - whether oracle price passes validity checks re number of sources and age
    fn get_oracle_price(self: @TContractState, market_id: felt252) -> (u256, bool);

    // Get total token balances for a given market.
    // 
    // # Arguments
    // * `market_id` - market id
    //
    // # Returns
    // * `base_amount` - total base tokens owned
    // * `quote_amount` - total quote tokens owned
    fn get_balances(self: @TContractState, market_id: felt252) -> (u256, u256);

    // Get total token balances for a list of markets.
    // 
    // # Arguments
    // * `market_ids` - list of market ids
    //
    // # Returns
    // * `base_amount` - base amount held in strategy market
    // * `quote_amount` - quote amount held in strategy market
    fn get_balances_array(
        self: @TContractState, market_ids: Span<felt252>
    ) -> Span<(u256, u256)>;

    // Get user's share of amounts held in market, for a list of users.
    // 
    // # Arguments
    // * `users` - list of user address
    // * `market_ids` - list of market ids
    //
    // # Returns
    // * `base_amount` - base tokens owned by user
    // * `quote_amount` - quote tokens owned by user
    // * `user_shares` - user shares
    // * `total_shares` - total shares of market
    fn get_user_balances(
        self: @TContractState, users: Span<ContractAddress>, market_ids: Span<felt252>
    ) -> Span<(u256, u256, u256, u256)>;

    // Initialise market for solver.
    // At the moment, only callable by contract owner to prevent unwanted claiming of markets. 
    //
    // # Arguments
    // * `market_info` - market info
    // * `params` - solver params
    fn add_market(ref self: TContractState, market_info: MarketInfo, params: MarketParams);

    // Change the parameters of the strategy.
    // Only callable by strategy owner.
    //
    // # Params
    // * `market_id` - market id
    // * `params` - solver params
    fn set_params(ref self: TContractState, market_id: felt252, params: MarketParams);

    // Deposit initial liquidity to market.
    // Should be used whenever total deposits in a strategy are zero. This can happen both
    // when a solver is first initialised, or subsequently whenever all deposits are withdrawn.
    //
    // # Arguments
    // * `market_id` - market id
    // * `base_amount` - base asset to deposit
    // * `quote_amount` - quote asset to deposit
    //
    // # Returns
    // * `shares` - pool shares minted in the form of liquidity
    fn deposit_initial(
        ref self: TContractState, market_id: felt252, base_amount: u256, quote_amount: u256
    ) -> u256;

    // Same as `deposit_initial`, but with a referrer.
    //
    // # Arguments
    // * `market_id` - market id
    // * `base_amount` - base asset to deposit
    // * `quote_amount` - quote asset to deposit
    // * `referrer` - referrer address
    //
    // # Returns
    // * `shares` - pool shares minted in the form of liquidity
    fn deposit_initial_with_referrer(
        ref self: TContractState,
        market_id: felt252,
        base_amount: u256,
        quote_amount: u256,
        referrer: ContractAddress
    ) -> u256;

    // Deposit liquidity to strategy.
    // For public markets, this will take the lower of requested and available balances, 
    // and refund any excess tokens remaining after coercing to the prevailing vault token 
    // ratio. For private markets, will deposit the exact requested amounts.
    //
    // # Arguments
    // * `market_id` - market id
    // * `base_requested` - base asset requested to be deposited
    // * `quote_requested` - quote asset requested to be deposited
    //
    // # Returns
    // * `base_amount` - base asset deposited
    // * `quote_amount` - quote asset deposited
    // * `shares` - pool shares minted
    fn deposit(
        ref self: TContractState, market_id: felt252, base_amount: u256, quote_amount: u256
    ) -> (u256, u256, u256);

    // Same as `deposit`, but with a referrer.
    //
    // # Arguments
    // * `market_id` - market id
    // * `base_amount` - base asset desired
    // * `quote_amount` - quote asset desired
    // * `referrer` - referrer address
    //
    // # Returns
    // * `base_amount` - base asset deposited
    // * `quote_amount` - quote asset deposited
    // * `shares` - pool shares minted
    fn deposit_with_referrer(
        ref self: TContractState,
        market_id: felt252,
        base_amount: u256,
        quote_amount: u256,
        referrer: ContractAddress
    ) -> (u256, u256, u256);

    // Burn pool shares and withdraw funds from strategy.
    // Called when vault has multiple owners.
    //
    // # Arguments
    // * `market_id` - market id
    // * `shares` - pool shares to burn
    //
    // # Returns
    // * `base_amount` - base asset withdrawn
    // * `quote_amount` - quote asset withdrawn
    fn withdraw_at_ratio(ref self: TContractState, market_id: felt252, shares: u256) -> (u256, u256);

    // Withdraw funds from strategy.
    // Allows user to withdraw a specific amount of tokens. 
    //
    // # Arguments
    // * `market_id` - market id
    // * `base_amount` - amount of base asset to withdraw
    // * `quote_amount` - amount of quote asset to withdraw
    //
    // # Returns
    // * `base_amount` - base asset withdrawn
    // * `quote_amount` - quote asset withdrawn
    fn withdraw_amounts(
        ref self: TContractState, market_id: felt252, base_amount: u256, quote_amount: u256
    ) -> (u256, u256);

    // Collect withdrawal fees.
    // Only callable by contract owner.
    //
    // # Arguments
    // * `receiver` - address to receive fees
    // * `token` - token to collect fees for
    // * `amount` - amount of fees requested
    fn collect_withdraw_fees(
        ref self: TContractState, receiver: ContractAddress, token: ContractAddress, amount: u256
    ) -> u256;

    // Set withdraw fee for a given market.
    // Only callable by contract owner.
    //
    // # Arguments
    // * `market_id` - market id
    // * `fee_rate` - fee rate
    fn set_withdraw_fee(ref self: TContractState, market_id: felt252, fee_rate: u16);

    // Change the oracle contract address.
    //
    // # Arguments
    // * `oracle` - contract address of oracle feed
    // * `oracle_summary` - contract address of oracle summary
    fn change_oracle(ref self: TContractState, oracle: ContractAddress);

    // Set vault token class hash
    //
    // # Arguments
    // * `new_class_hash` - new class hash of vault token
    fn change_vault_token_class(ref self: TContractState, new_class_hash: ClassHash); 

    // Request transfer ownership of the contract.
    // Part 1 of 2 step process to transfer ownership.
    //
    // # Arguments
    // * `new_owner` - New owner of the contract
    fn transfer_owner(ref self: TContractState, new_owner: ContractAddress);

    // Called by new owner to accept ownership of the contract.
    // Part 2 of 2 step process to transfer ownership.
    fn accept_owner(ref self: TContractState);

    // Pause strategy. 
    // Only callable by strategy owner. 
    // 
    // # Arguments
    // * `market_id` - market id of strategy
    fn pause(ref self: TContractState, market_id: felt252);

    // Unpause strategy.
    // Only callable by strategy owner.
    //
    // # Arguments
    // * `market_id` - market id of strategy
    fn unpause(ref self: TContractState, market_id: felt252);

    // Upgrade contract class.
    // Callable by owner only.
    //
    // # Arguments
    // * `new_class_hash` - new class hash of contract
    fn upgrade(ref self: TContractState, new_class_hash: ClassHash);
}