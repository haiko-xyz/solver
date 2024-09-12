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
// * `base_fees` - base fees
// * `quote_fees` - quote fees
// * `is_paused` - whether market is paused
// * `vault_token` - vault token (or 0 if unset)
#[derive(Drop, Copy, Serde)]
pub struct MarketState {
    pub base_reserves: u256,
    pub quote_reserves: u256,
    pub base_fees: u256,
    pub quote_fees: u256,
    pub is_paused: bool,
    pub vault_token: ContractAddress,
}

// Fees per share.
//
// * `base_fps` - base fees per share
// * `quote_fps` - quote fees per share
#[derive(Drop, Copy, Serde)]
pub struct FeesPerShare {
    pub base_fps: u256,
    pub quote_fps: u256,
}

// Information about a swap.
//
// * `is_buy` - whether swap is buy or sell
// * `amount` - amount swapped in or out
// * `exact_input` - whether amount is exact input or exact output
// * `threshold_sqrt_price` - threshold sqrt price for swap
// * `threshold_amount` - threshold amount for swap
// * `deadline` - deadline for swap
#[derive(Copy, Drop, Serde)]
pub struct SwapParams {
    pub is_buy: bool,
    pub amount: u256,
    pub exact_input: bool,
    pub threshold_sqrt_price: Option<u256>,
    pub threshold_amount: Option<u256>,
    pub deadline: Option<u64>,
}

// Token amounts (function response).
//
// * `base_amount` - base amount deposited
// * `quote_amount` - quote amount deposited
// * `base_fees` - base fees collected at deposit
// * `quote_fees` - quote fees collected at deposit
#[derive(Copy, Drop, Serde, Default)]
pub struct Amounts {
    pub base_amount: u256,
    pub quote_amount: u256,
    pub base_fees: u256,
    pub quote_fees: u256,
}

// Token amounts with shares (function response).
//
// * `base_amount` - base amount deposited
// * `quote_amount` - quote amount deposited
// * `base_fees` - base fees collected at deposit
// * `quote_fees` - quote fees collected at deposit
// * `shares` - number of shares minted
#[derive(Copy, Drop, Serde)]
pub struct AmountsWithShares {
    pub base_amount: u256,
    pub quote_amount: u256,
    pub base_fees: u256,
    pub quote_fees: u256,
    pub shares: u256,
}

// Swap amounts (function response).
//
// * `base_amount` - base amount deposited
// * `quote_amount` - quote amount deposited
// * `base_fees` - base fees collected at deposit
// * `quote_fees` - quote fees collected at deposit
// * `shares` - number of shares minted
#[derive(Copy, Drop, Serde)]
pub struct SwapAmounts {
    pub amount_in: u256,
    pub amount_out: u256,
    pub fees: u256,
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

////////////////////////////////
// IMPLS
////////////////////////////////

pub impl DefaultMarketState of Default<MarketState> {
    fn default() -> MarketState {
        MarketState {
            base_reserves: 0,
            quote_reserves: 0,
            base_fees: 0,
            quote_fees: 0,
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
// * `slab2` - base fees (coerced to felt252)
// * `slab3` - quote fees (coerced to felt252)
// * `slab4` - vault_token
// * `slab5` - is_paused
#[derive(starknet::Store)]
pub struct PackedMarketState {
    pub slab0: felt252,
    pub slab1: felt252,
    pub slab2: felt252,
    pub slab3: felt252,
    pub slab4: felt252,
    pub slab5: felt252,
}

// Packed fees per share.
//
// * `slab0` - base fees per share (coerced to felt252)
// * `slab1` - quote fees per share (coerced to felt252)
#[derive(starknet::Store)]
pub struct PackedFeesPerShare {
    pub slab0: felt252,
    pub slab1: felt252,
}
