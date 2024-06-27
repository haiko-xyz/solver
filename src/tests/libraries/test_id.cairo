// Core lib imports.
use starknet::contract_address_const;

// Local imports.
use haiko_solver_replicating::libraries::id;
use haiko_solver_replicating::types::core::MarketInfo;

#[test]
fn test_market_id() {
    // Define base market info.
    let mut market_info = MarketInfo {
        base_token: contract_address_const::<0x123>(),
        quote_token: contract_address_const::<0x456>(),
        owner: contract_address_const::<789>(),
        is_public: true,
    };
    let mut market_id = id::market_id(market_info);

    // Vary base token.
    market_info.base_token = contract_address_const::<0x321>();
    let mut last_market_id = market_id;
    market_id = id::market_id(market_info);
    assert(market_id != last_market_id, 'Market id: base token');

    // Vary quote token.
    market_info.quote_token = contract_address_const::<0x654>();
    last_market_id = market_id;
    market_id = id::market_id(market_info);
    assert(market_id != last_market_id, 'Market id: quote token');

    // Vary owner.
    market_info.owner = contract_address_const::<0x987>();
    last_market_id = market_id;
    market_id = id::market_id(market_info);
    assert(market_id != last_market_id, 'Market id: owner');

    // Vary is public.
    market_info.is_public = false;
    last_market_id = market_id;
    market_id = id::market_id(market_info);
    assert(market_id != last_market_id, 'Market id: is public');
}
