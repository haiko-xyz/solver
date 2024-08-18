use starknet::ContractAddress;
use starknet::contract_address_const;

////////////////////////////////
// TYPES
////////////////////////////////

// Identifying information for a solver market.
//
// * `base_token` - base token address
// * `quote_token` - quote token address
// * `owner` - solver market owner address
// * `is_public` - whether market is open to public deposits
#[derive(Copy, Drop, Serde, starknet::Store)]
pub struct MarketInfo {
    pub base_token: ContractAddress,
    pub quote_token: ContractAddress,
    pub owner: ContractAddress,
    pub is_public: bool,
}

// Solver market state.
//
// * `base_reserves` - base reserves
// * `quote_reserves` - quote reserves
// * `is_paused` - whether market is paused
// * `vault_token` - vault token (or 0 if unset)
#[derive(Drop, Copy, Serde)]
pub struct MarketState {
    pub base_reserves: u256,
    pub quote_reserves: u256,
    pub is_paused: bool,
    pub vault_token: ContractAddress,
}

// Information about a swap.
//
// * `is_buy` - whether swap is buy or sell
// * `amount` - amount swapped in or out
// * `exact_input` - whether amount is exact input or exact output
#[derive(Copy, Drop, Serde)]
pub struct SwapParams {
    pub is_buy: bool,
    pub amount: u256,
    pub exact_input: bool,
    pub threshold_sqrt_price: Option<u256>,
    pub threshold_amount: Option<u256>,
}

// Virtual liquidity position.
//
// * `lower_sqrt_price` - lower limit of position
// * `upper_sqrt_price` - upper limit of position
// * `liquidity` - liquidity of position
#[derive(Drop, Copy, Serde, Default, PartialEq)]
pub struct PositionInfo {
    pub lower_sqrt_price: u256,
    pub upper_sqrt_price: u256,
    pub liquidity: u128,
}

// Execution hooks to extend call functionality.
//
// * `after_swap` - enable after swap hook
// * `after_withdraw` - enable after withdraw hook
// TODO: add store packing
#[derive(Drop, Copy, Serde, Default, starknet::Store)]
pub struct Hooks {
    pub after_swap: bool,
    pub after_withdraw: bool,
}

////////////////////////////////
// IMPLS
////////////////////////////////

pub impl DefaultMarketState of Default<MarketState> {
    fn default() -> MarketState {
        MarketState {
            base_reserves: 0,
            quote_reserves: 0,
            is_paused: false,
            vault_token: contract_address_const::<0x0>(),
        }
    }
}

////////////////////////////////
// PACKED TYPES
////////////////////////////////

// Packed market state.
//
// * `slab0` - base reserves (coerced to felt252)
// * `slab1` - quote reserves (coerced to felt252)
// * `slab2` - vault_token
// * `slab3` - is_paused
#[derive(starknet::Store)]
pub struct PackedMarketState {
    pub slab0: felt252,
    pub slab1: felt252,
    pub slab2: felt252,
    pub slab3: felt252
}
