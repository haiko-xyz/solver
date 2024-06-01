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

    // Get token amounts held in reserve for a list of markets.
    // 
    // # Arguments
    // * `market_ids` - list of market ids
    //
    // # Returns
    // * `balances` - list of base and quote token amounts
    fn get_balances_array(self: @TContractState, market_ids: Span<felt252>) -> Span<(u256, u256)>;

    // Get token amounts and shares held in solver market for a list of users.
    // 
    // # Arguments
    // * `users` - list of user address
    // * `market_ids` - list of market ids
    //
    // # Returns
    // * `base_amount` - base tokens owned by user
    // * `quote_amount` - quote tokens owned by user
    // * `user_shares` - user shares
    // * `total_shares` - total shares in market
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

    // Change parameters of the solver market.
    // Only callable by market owner.
    //
    // # Params
    // * `market_id` - market id
    // * `params` - market params
    fn set_params(ref self: TContractState, market_id: felt252, params: MarketParams);

    // Deposit initial liquidity to market.
    // Should be used whenever total deposits in a market are zero. This can happen both
    // when a market is first initialised, or subsequently whenever all deposits are withdrawn.
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

    // Deposit liquidity to market.
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
    // * `base_deposit` - base asset deposited
    // * `quote_deposit` - quote asset deposited
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

    // Burn pool shares and withdraw funds from market.
    // Called for public vaults. For private vaults, use `withdraw_amount`.
    //
    // # Arguments
    // * `market_id` - market id
    // * `shares` - pool shares to burn
    //
    // # Returns
    // * `base_amount` - base asset withdrawn
    // * `quote_amount` - quote asset withdrawn
    fn withdraw_at_ratio(
        ref self: TContractState, market_id: felt252, shares: u256
    ) -> (u256, u256);

    // Withdraw exact token amounts from market.
    // Called for private vaults. For public vaults, use `withdraw_at_ratio`.
    //
    // # Arguments
    // * `market_id` - market id
    // * `base_amount` - base amount requested
    // * `quote_amount` - quote amount requested
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

    // Pause solver market. 
    // Only callable by market owner. 
    // 
    // # Arguments
    // * `market_id` - market id
    fn pause(ref self: TContractState, market_id: felt252);

    // Unpause solver market.
    // Only callable by market owner.
    //
    // # Arguments
    // * `market_id` - market id
    fn unpause(ref self: TContractState, market_id: felt252);

    // Upgrade contract class.
    // Callable by owner only.
    //
    // # Arguments
    // * `new_class_hash` - new class hash of contract
    fn upgrade(ref self: TContractState, new_class_hash: ClassHash);
}
