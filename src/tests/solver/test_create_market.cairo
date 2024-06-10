// Core lib imports.
use starknet::contract_address_const;

// Local imports.
use haiko_solver_replicating::{
    contracts::solver::ReplicatingSolver,
    interfaces::{
        IVaultToken::{IVaultTokenDispatcher, IVaultTokenDispatcherTrait},
        IReplicatingSolver::{IReplicatingSolverDispatcher, IReplicatingSolverDispatcherTrait},
    },
    types::replicating::{MarketInfo, MarketParams},
    tests::{
        helpers::{
            actions::{deploy_replicating_solver, deploy_mock_pragma_oracle},
            params::default_market_params, utils::before,
        },
    },
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
    let (
        base_token, quote_token, _oracle, _vault_token_class, solver, _market_id, _vault_token_opt
    ) =
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
    let market_params = default_market_params();
    let (market_id, vault_token_opt) = solver.create_market(market_info, market_params);
    let vault_token = vault_token_opt.unwrap();

    // Fetch market.
    let market_info_ret = solver.market_info(market_id);
    let market_params_ret = solver.market_params(market_id);
    let market_state_ret = solver.market_state(market_id);

    // Check market info.
    assert(market_info_ret.base_token == market_info.base_token, 'Base token');
    assert(market_info_ret.quote_token == market_info.quote_token, 'Quote token');
    assert(market_info_ret.owner == market_info.owner, 'Owner');
    assert(market_info_ret.is_public == market_info.is_public, 'Is public');

    // Check market params.
    assert(market_params_ret.min_spread == market_params.min_spread, 'Min spread');
    assert(market_params_ret.range == market_params.range, 'Range');
    assert(market_params_ret.max_delta == market_params.max_delta, 'Max delta');
    assert(market_params_ret.max_skew == market_params.max_skew, 'Max skew');
    assert(
        market_params_ret.base_currency_id == market_params.base_currency_id, 'Base currency id'
    );
    assert(
        market_params_ret.quote_currency_id == market_params.quote_currency_id, 'Quote currency id'
    );
    assert(market_params_ret.min_sources == market_params.min_sources, 'Min sources');
    assert(market_params_ret.max_age == market_params.max_age, 'Max age');

    // Check market state.
    assert(market_state_ret.base_reserves == 0, 'Base reserves');
    assert(market_state_ret.quote_reserves == 0, 'Quote reserves');
    assert(market_state_ret.is_paused == false, 'Is paused');
    assert(market_state_ret.vault_token == vault_token, 'Vault token');

    // Check vault token.
    let vault_token = ERC20ABIDispatcher { contract_address: vault_token_opt.unwrap() };
    let vault_token_alt = IVaultTokenDispatcher { contract_address: vault_token_opt.unwrap() };
    assert(vault_token.name() == "Haiko Replicating ETH-USDC", 'Vault token: name');
    assert(vault_token.symbol() == "REPL-ETH-USDC", 'Vault token: name');
    assert(vault_token.decimals() == 18, 'Vault token: decimal');
    assert(vault_token_alt.owner() == solver.contract_address, 'Vault token: owner');
}

#[test]
fn test_create_private_market_initialises_immutables() {
    let (
        base_token, quote_token, _oracle, _vault_token_class, solver, _market_id, _vault_token_opt
    ) =
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
    let market_params = default_market_params();
    let (market_id, _) = solver.create_market(market_info, market_params);

    // Fetch market.
    let market_info_ret = solver.market_info(market_id);
    let market_params_ret = solver.market_params(market_id);
    let market_state_ret = solver.market_state(market_id);

    // Run checks.
    assert(market_info_ret.base_token == market_info.base_token, 'Base token');
    assert(market_info_ret.quote_token == market_info.quote_token, 'Quote token');
    assert(market_info_ret.owner == market_info.owner, 'Owner');
    assert(market_info_ret.is_public == market_info.is_public, 'Is public');

    assert(market_params_ret.min_spread == market_params.min_spread, 'Min spread');
    assert(market_params_ret.range == market_params.range, 'Range');
    assert(market_params_ret.max_delta == market_params.max_delta, 'Max delta');
    assert(market_params_ret.max_skew == market_params.max_skew, 'Max skew');
    assert(
        market_params_ret.base_currency_id == market_params.base_currency_id, 'Base currency id'
    );
    assert(
        market_params_ret.quote_currency_id == market_params.quote_currency_id, 'Quote currency id'
    );
    assert(market_params_ret.min_sources == market_params.min_sources, 'Min sources');
    assert(market_params_ret.max_age == market_params.max_age, 'Max age');

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
    let (
        base_token, quote_token, _oracle, _vault_token_class, solver, _market_id, _vault_token_opt
    ) =
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
    let market_params = default_market_params();
    let (market_id, vault_token_opt) = solver.create_market(market_info, market_params);

    // Check events emitted.
    spy
        .assert_emitted(
            @array![
                (
                    solver.contract_address,
                    ReplicatingSolver::Event::CreateMarket(
                        ReplicatingSolver::CreateMarket {
                            market_id,
                            base_token: market_info.base_token,
                            quote_token: market_info.quote_token,
                            owner: market_info.owner,
                            is_public: market_info.is_public,
                            vault_token: vault_token_opt.unwrap(),
                        }
                    )
                ),
                (
                    solver.contract_address,
                    ReplicatingSolver::Event::SetMarketParams(
                        ReplicatingSolver::SetMarketParams {
                            market_id,
                            min_spread: market_params.min_spread,
                            range: market_params.range,
                            max_delta: market_params.max_delta,
                            max_skew: market_params.max_skew,
                            base_currency_id: market_params.base_currency_id,
                            quote_currency_id: market_params.quote_currency_id,
                            min_sources: market_params.min_sources,
                            max_age: market_params.max_age,
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
    let (
        _base_token, quote_token, _oracle, _vault_token_class, solver, _market_id, _vault_token_opt
    ) =
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
    let market_params = default_market_params();
    solver.create_market(market_info, market_params);
}

#[test]
#[should_panic(expected: ('QuoteTokenNull',))]
fn test_create_market_with_null_quote_token_fails() {
    let (
        base_token, _quote_token, _oracle, _vault_token_class, solver, _market_id, _vault_token_opt
    ) =
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
    let market_params = default_market_params();
    solver.create_market(market_info, market_params);
}

#[test]
#[should_panic(expected: ('OwnerNull',))]
fn test_create_market_with_null_owner_fails() {
    let (
        base_token, quote_token, _oracle, _vault_token_class, solver, _market_id, _vault_token_opt
    ) =
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
    let market_params = default_market_params();
    solver.create_market(market_info, market_params);
}

#[test]
#[should_panic(expected: ('BaseIdNull',))]
fn test_create_market_with_null_base_currency_id_fails() {
    let (
        base_token, quote_token, _oracle, _vault_token_class, solver, _market_id, _vault_token_opt
    ) =
        before(
        true
    );

    // Create market.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let market_info = MarketInfo {
        base_token: base_token.contract_address,
        quote_token: quote_token.contract_address,
        owner: alice(),
        is_public: true,
    };
    let mut market_params = default_market_params();
    market_params.base_currency_id = 0;
    solver.create_market(market_info, market_params);
}

#[test]
#[should_panic(expected: ('QuoteIdNull',))]
fn test_create_market_with_null_quote_currency_id_fails() {
    let (
        base_token, quote_token, _oracle, _vault_token_class, solver, _market_id, _vault_token_opt
    ) =
        before(
        true
    );

    // Create market.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let market_info = MarketInfo {
        base_token: base_token.contract_address,
        quote_token: quote_token.contract_address,
        owner: alice(),
        is_public: true,
    };
    let mut market_params = default_market_params();
    market_params.quote_currency_id = 0;
    solver.create_market(market_info, market_params);
}

#[test]
#[should_panic(expected: ('MinSourcesZero',))]
fn test_create_market_with_zero_min_sources_fails() {
    let (
        base_token, quote_token, _oracle, _vault_token_class, solver, _market_id, _vault_token_opt
    ) =
        before(
        true
    );

    // Create market.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let market_info = MarketInfo {
        base_token: base_token.contract_address,
        quote_token: quote_token.contract_address,
        owner: alice(),
        is_public: true,
    };
    let mut market_params = default_market_params();
    market_params.min_sources = 0;
    solver.create_market(market_info, market_params);
}

#[test]
#[should_panic(expected: ('MaxAgeZero',))]
fn test_create_market_with_zero_max_age_fails() {
    let (
        base_token, quote_token, _oracle, _vault_token_class, solver, _market_id, _vault_token_opt
    ) =
        before(
        true
    );

    // Create market.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let market_info = MarketInfo {
        base_token: base_token.contract_address,
        quote_token: quote_token.contract_address,
        owner: alice(),
        is_public: true,
    };
    let mut market_params = default_market_params();
    market_params.max_age = 0;
    solver.create_market(market_info, market_params);
}

#[test]
#[should_panic(expected: ('RangeZero',))]
fn test_create_market_with_zero_range_fails() {
    let (
        base_token, quote_token, _oracle, _vault_token_class, solver, _market_id, _vault_token_opt
    ) =
        before(
        true
    );

    // Create market.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let market_info = MarketInfo {
        base_token: base_token.contract_address,
        quote_token: quote_token.contract_address,
        owner: alice(),
        is_public: true,
    };
    let mut market_params = default_market_params();
    market_params.range = 0;
    solver.create_market(market_info, market_params);
}

#[test]
#[should_panic(expected: ('MarketExists',))]
fn test_create_duplicate_market_fails() {
    let (
        base_token, quote_token, _oracle, _vault_token_class, solver, _market_id, _vault_token_opt
    ) =
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
    let market_params = default_market_params();
    solver.create_market(market_info, market_params);
}
