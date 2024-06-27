// Core lib imports.
use core::poseidon::poseidon_hash_span;

// Local imports.
use haiko_solver_replicating::types::core::MarketInfo;

// Compute market id.
//   Poseidon(base_token, quote_token, owner, is_public)
//
// # Arguments
// * `base_token` - address of the base token
// * `quote_token` - address of the quote token
// * `owner` - address of the owner, or 0 if unowned
// * `is_public` - whether market is open to public deposits
//
// # Returns
// * `salt` - salt for Starknet contract address
pub fn market_id(market_info: MarketInfo) -> felt252 {
    let mut input: Array<felt252> = array![];
    market_info.base_token.serialize(ref input);
    market_info.quote_token.serialize(ref input);
    market_info.owner.serialize(ref input);
    market_info.is_public.serialize(ref input);
    poseidon_hash_span(input.span())
}
