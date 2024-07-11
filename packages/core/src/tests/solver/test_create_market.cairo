// Core lib imports.
use starknet::contract_address_const;

// Local imports.
use haiko_solver_core::{
    contracts::solver::SolverComponent,
    interfaces::{
        IVaultToken::{IVaultTokenDispatcher, IVaultTokenDispatcherTrait},
        ISolver::{ISolverDispatcher, ISolverDispatcherTrait},
    },
    types::MarketInfo, tests::helpers::utils::before,
};

// Haiko imports.
use haiko_lib::helpers::params::{owner, alice};

// External imports.
use snforge_std::{start_prank, declare, spy_events, SpyOn, EventSpy, EventAssertions, CheatTarget};
use openzeppelin::token::erc20::interface::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};

////////////////////////////////
// TESTS - Success cases
////////////////////////////////

#[test]
fn test_create_public_market_initialises_immutables_and_deploys_vault_token() {
    let (base_token, quote_token, _vault_token_class, solver, _market_id, _vault_token_opt) =
        before(
        true
    );

    // Create a new market with alice as owner.
    // Create market.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let market_info = MarketInfo {
        base_token: base_token.contract_address,
        quote_token: quote_token.contract_address,
        owner: alice(),
        is_public: true,
    };
    let (market_id, vault_token_opt) = solver.create_market(market_info);
    let vault_token = vault_token_opt.unwrap();

    // Fetch market.
    let market_info_ret = solver.market_info(market_id);
    let market_state_ret = solver.market_state(market_id);

    // Check market info.
    assert(market_info_ret.base_token == market_info.base_token, 'Base token');
    assert(market_info_ret.quote_token == market_info.quote_token, 'Quote token');
    assert(market_info_ret.owner == market_info.owner, 'Owner');
    assert(market_info_ret.is_public == market_info.is_public, 'Is public');

    // Check market state.
    assert(market_state_ret.base_reserves == 0, 'Base reserves');
    assert(market_state_ret.quote_reserves == 0, 'Quote reserves');
    assert(market_state_ret.is_paused == false, 'Is paused');
    assert(market_state_ret.vault_token == vault_token, 'Vault token');

    // Check vault token.
    let vault_token = ERC20ABIDispatcher { contract_address: vault_token_opt.unwrap() };
    let vault_token_alt = IVaultTokenDispatcher { contract_address: vault_token_opt.unwrap() };
    assert(vault_token.name() == "Haiko Mock ETH-USDC", 'Vault token: name');
    assert(vault_token.symbol() == "HAIKO-MOCK-ETH-USDC", 'Vault token: name');
    assert(vault_token.decimals() == 18, 'Vault token: decimal');
    assert(vault_token_alt.owner() == solver.contract_address, 'Vault token: owner');
}

#[test]
fn test_create_private_market_initialises_immutables() {
    let (base_token, quote_token, _vault_token_class, solver, _market_id, _vault_token_opt) =
        before(
        true
    );

    // Create market.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let market_info = MarketInfo {
        base_token: base_token.contract_address,
        quote_token: quote_token.contract_address,
        owner: alice(),
        is_public: false,
    };
    let (market_id, _) = solver.create_market(market_info);

    // Fetch market.
    let market_info_ret = solver.market_info(market_id);
    let market_state_ret = solver.market_state(market_id);

    // Run checks.
    assert(market_info_ret.base_token == market_info.base_token, 'Base token');
    assert(market_info_ret.quote_token == market_info.quote_token, 'Quote token');
    assert(market_info_ret.owner == market_info.owner, 'Owner');
    assert(market_info_ret.is_public == market_info.is_public, 'Is public');

    assert(market_state_ret.base_reserves == 0, 'Base reserves');
    assert(market_state_ret.quote_reserves == 0, 'Quote reserves');
    assert(market_state_ret.is_paused == false, 'Is paused');
    assert(market_state_ret.vault_token == contract_address_const::<0x0>(), 'Vault token');
}

////////////////////////////////
// TESTS - Events
////////////////////////////////

#[test]
fn test_create_market_emits_events() {
    let (base_token, quote_token, _vault_token_class, solver, _market_id, _vault_token_opt) =
        before(
        true
    );

    // Spy on events.
    let mut spy = spy_events(SpyOn::One(solver.contract_address));

    // Create market.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let market_info = MarketInfo {
        base_token: base_token.contract_address,
        quote_token: quote_token.contract_address,
        owner: alice(),
        is_public: true,
    };
    let (market_id, vault_token_opt) = solver.create_market(market_info);

    // Check events emitted.
    spy
        .assert_emitted(
            @array![
                (
                    solver.contract_address,
                    SolverComponent::Event::CreateMarket(
                        SolverComponent::CreateMarket {
                            market_id,
                            base_token: market_info.base_token,
                            quote_token: market_info.quote_token,
                            owner: market_info.owner,
                            is_public: market_info.is_public,
                            vault_token: vault_token_opt.unwrap(),
                        }
                    )
                )
            ]
        );
}

////////////////////////////////
// TESTS - Fail cases
////////////////////////////////

#[test]
#[should_panic(expected: ('BaseTokenNull',))]
fn test_create_market_with_null_base_token_fails() {
    let (_base_token, quote_token, _vault_token_class, solver, _market_id, _vault_token_opt) =
        before(
        true
    );

    // Create market.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let market_info = MarketInfo {
        base_token: contract_address_const::<0x0>(),
        quote_token: quote_token.contract_address,
        owner: alice(),
        is_public: true,
    };
    solver.create_market(market_info);
}

#[test]
#[should_panic(expected: ('QuoteTokenNull',))]
fn test_create_market_with_null_quote_token_fails() {
    let (base_token, _quote_token, _vault_token_class, solver, _market_id, _vault_token_opt) =
        before(
        true
    );

    // Create market.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let market_info = MarketInfo {
        base_token: base_token.contract_address,
        quote_token: contract_address_const::<0x0>(),
        owner: alice(),
        is_public: true,
    };
    solver.create_market(market_info);
}

#[test]
#[should_panic(expected: ('SameToken',))]
fn test_create_market_with_same_token_fails() {
    let (base_token, _quote_token, _vault_token_class, solver, _market_id, _vault_token_opt) =
        before(
        true
    );

    // Create market.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let market_info = MarketInfo {
        base_token: base_token.contract_address,
        quote_token: base_token.contract_address,
        owner: alice(),
        is_public: true,
    };
    solver.create_market(market_info);
}

#[test]
#[should_panic(expected: ('OwnerNull',))]
fn test_create_market_with_null_owner_fails() {
    let (base_token, quote_token, _vault_token_class, solver, _market_id, _vault_token_opt) =
        before(
        true
    );

    // Create market.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let market_info = MarketInfo {
        base_token: base_token.contract_address,
        quote_token: quote_token.contract_address,
        owner: contract_address_const::<0x0>(),
        is_public: true,
    };
    solver.create_market(market_info);
}

#[test]
#[should_panic(expected: ('MarketExists',))]
fn test_create_duplicate_market_fails() {
    let (base_token, quote_token, _vault_token_class, solver, _market_id, _vault_token_opt) =
        before(
        true
    );

    // Create market.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let market_info = MarketInfo {
        base_token: base_token.contract_address,
        quote_token: quote_token.contract_address,
        owner: owner(),
        is_public: true,
    };
    solver.create_market(market_info);
}
