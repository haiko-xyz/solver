// Core lib imports.
use starknet::ContractAddress;
use starknet::class_hash::ClassHash;

// Local imports.
use haiko_solver_replicating::types::core::{MarketState, MarketInfo, PositionInfo, SwapParams};

#[starknet::interface]
pub trait ISolver<TContractState> {
    // Get the name of the solver.
    // 
    // # Returns
    // * `name` - solver name
    fn name(self: @TContractState) -> ByteArray;

    // Get the symbol of the solver.
    // 
    // # Returns
    // * `symbol` - solver symbol
    fn symbol(self: @TContractState) -> ByteArray;

    // Market id
    fn market_id(self: @TContractState, market_info: MarketInfo) -> felt252;

    // Immutable market information
    fn market_info(self: @TContractState, market_id: felt252) -> MarketInfo;

    // Market state
    fn market_state(self: @TContractState, market_id: felt252) -> MarketState;

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
    fn get_user_balances_array(
        self: @TContractState, users: Span<ContractAddress>, market_ids: Span<felt252>
    ) -> Span<(u256, u256, u256, u256)>;

    // Create market for solver.
    // At the moment, only callable by contract owner to prevent unwanted claiming of markets. 
    // Each market must be unique in `market_info`.
    //
    // # Arguments
    // * `market_info` - market info
    //
    // # Returns
    // * `market_id` - market id
    // * `vault_token` (optional) - vault token address (if public market)
    fn create_market(
        ref self: TContractState, market_info: MarketInfo
    ) -> (felt252, Option<ContractAddress>);

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

    // Deposit initial liquidity to market.
    // Should be used whenever total deposits in a market are zero. This can happen both
    // when a market is first initialised, or subsequently whenever all deposits are withdrawn.
    //
    // # Arguments
    // * `market_id` - market id
    // * `base_requested` - base asset requested to be deposited
    // * `quote_requested` - quote asset requested to be deposited
    //
    // # Returns
    // * `base_deposit` - base asset deposited
    // * `quote_deposit` - quote asset deposited
    // * `shares` - pool shares minted in the form of liquidity
    fn deposit_initial(
        ref self: TContractState, market_id: felt252, base_amount: u256, quote_amount: u256
    ) -> (u256, u256, u256);

    // Same as `deposit_initial`, but with a referrer.
    //
    // # Arguments
    // * `market_id` - market id
    // * `base_requested` - base asset requested to be deposited
    // * `quote_requested` - quote asset requested to be deposited
    // * `referrer` - referrer address
    //
    // # Returns
    // * `base_deposit` - base asset deposited
    // * `quote_deposit` - quote asset deposited
    // * `shares` - pool shares minted in the form of liquidity
    fn deposit_initial_with_referrer(
        ref self: TContractState,
        market_id: felt252,
        base_amount: u256,
        quote_amount: u256,
        referrer: ContractAddress
    ) -> (u256, u256, u256);

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
    fn withdraw(
        ref self: TContractState, market_id: felt252, base_amount: u256, quote_amount: u256
    ) -> (u256, u256);

    // Collect withdrawal fees.
    // Only callable by contract owner.
    //
    // # Arguments
    // * `receiver` - address to receive fees
    // * `token` - token to collect fees for
    fn collect_withdraw_fees(
        ref self: TContractState, receiver: ContractAddress, token: ContractAddress
    ) -> u256;

    // Set withdraw fee for a given market.
    // Only callable by contract owner.
    //
    // # Arguments
    // * `market_id` - market id
    // * `fee_rate` - fee rate
    fn set_withdraw_fee(ref self: TContractState, market_id: felt252, fee_rate: u16);

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

// Solvers must implement the `ISolverQuoter` interface, which returns the quote for a swap.
#[starknet::interface]
pub trait ISolverQuoter<TContractState> {
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
