// Core lib imports.
use starknet::ContractAddress;
use starknet::contract_address_const;
use starknet::class_hash::ClassHash;

// Local imports.
use haiko_solver_core::{
    contracts::mocks::{
        mock_solver::{IMockSolverDispatcher, IMockSolverDispatcherTrait},
        upgraded_mock_solver::{
            UpgradedMockSolver, IUpgradedMockSolverDispatcher, IUpgradedMockSolverDispatcherTrait
        },
    },
    interfaces::{
        ISolver::{ISolverDispatcher, ISolverDispatcherTrait},
        IVaultToken::{IVaultTokenDispatcher, IVaultTokenDispatcherTrait},
    },
    types::{MarketInfo, MarketState, PositionInfo, SwapParams},
    tests::helpers::actions::deploy_mock_solver,
};

// Haiko imports.
use haiko_lib::constants::ONE;
use haiko_lib::helpers::{
    params::{owner, alice, bob, treasury, default_token_params},
    actions::token::{deploy_token, fund, approve}, utils::{to_e18, approx_eq},
};

// External imports.
use openzeppelin::token::erc20::interface::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};
use snforge_std::{
    declare, start_warp, start_prank, stop_prank, CheatTarget, spy_events, SpyOn, EventSpy,
    EventAssertions, EventFetcher, ContractClass, ContractClassTrait
};

////////////////////////////////
// SETUP
////////////////////////////////

const BASE_DECIMALS: u8 = 18;
const QUOTE_DECIMALS: u8 = 18;

////////////////////////////////
// TYPES
////////////////////////////////

#[derive(Drop, Copy, Serde)]
struct Snapshot {
    pub lp_base_bal: u256,
    pub lp_quote_bal: u256,
    pub vault_lp_bal: u256,
    pub vault_total_bal: u256,
    pub solver_base_bal: u256,
    pub solver_quote_bal: u256,
    pub market_state: MarketState,
}

////////////////////////////////
// HELPERS
////////////////////////////////

pub fn declare_classes() -> (ContractClass, ContractClass, ContractClass) {
    let erc20_class = declare("ERC20");
    let vault_token_class = declare("VaultToken");
    let solver_class = declare("MockSolver");

    (erc20_class, vault_token_class, solver_class)
}

pub fn before(
    is_market_public: bool
) -> (
    ERC20ABIDispatcher,
    ERC20ABIDispatcher,
    ClassHash,
    ISolverDispatcher,
    felt252,
    Option<ContractAddress>,
) {
    _before(is_market_public, BASE_DECIMALS, QUOTE_DECIMALS, true, 0, Option::None(()))
}

pub fn before_custom_decimals(
    is_market_public: bool, base_decimals: u8, quote_decimals: u8,
) -> (
    ERC20ABIDispatcher,
    ERC20ABIDispatcher,
    ClassHash,
    ISolverDispatcher,
    felt252,
    Option<ContractAddress>,
) {
    _before(is_market_public, base_decimals, quote_decimals, true, 0, Option::None(()))
}

pub fn before_skip_approve(
    is_market_public: bool,
) -> (
    ERC20ABIDispatcher,
    ERC20ABIDispatcher,
    ClassHash,
    ISolverDispatcher,
    felt252,
    Option<ContractAddress>,
) {
    _before(is_market_public, BASE_DECIMALS, QUOTE_DECIMALS, false, 0, Option::None(()))
}

pub fn before_with_salt(
    is_market_public: bool, salt: felt252, classes: (ContractClass, ContractClass, ContractClass),
) -> (
    ERC20ABIDispatcher,
    ERC20ABIDispatcher,
    ClassHash,
    ISolverDispatcher,
    felt252,
    Option<ContractAddress>,
) {
    _before(is_market_public, BASE_DECIMALS, QUOTE_DECIMALS, true, salt, Option::Some(classes))
}

fn _before(
    is_market_public: bool,
    base_decimals: u8,
    quote_decimals: u8,
    approve_solver: bool,
    salt: felt252,
    classes: Option<(ContractClass, ContractClass, ContractClass)>,
) -> (
    ERC20ABIDispatcher,
    ERC20ABIDispatcher,
    ClassHash,
    ISolverDispatcher,
    felt252,
    Option<ContractAddress>,
) {
    // Declare or unwrap classes.
    let (erc20_class, vault_token_class, solver_class) = if classes.is_some() {
        classes.unwrap()
    } else {
        declare_classes()
    };

    // Get default owner.
    let owner = owner();

    // Deploy tokens.
    let (_treasury, mut base_token_params, mut quote_token_params) = default_token_params();
    base_token_params.decimals = base_decimals;
    quote_token_params.decimals = quote_decimals;
    let base_token = deploy_token(erc20_class, @base_token_params);
    let quote_token = deploy_token(erc20_class, @quote_token_params);

    // Deploy mock solver.
    let solver = deploy_mock_solver(solver_class, owner, vault_token_class.class_hash);

    // Create market.
    start_prank(CheatTarget::One(solver.contract_address), owner());
    let market_info = MarketInfo {
        base_token: base_token.contract_address,
        quote_token: quote_token.contract_address,
        owner,
        is_public: is_market_public,
    };
    let (market_id, vault_token_opt) = solver.create_market(market_info);

    // Set price.
    let mock_solver = IMockSolverDispatcher { contract_address: solver.contract_address };
    mock_solver.set_price(market_id, ONE);

    // Set fee rate.
    mock_solver.set_fee_rate(market_id, 50);

    // Fund owner with initial token balances and approve strategy and market manager as spenders.
    let base_amount = to_e18(10000000000000000000000);
    let quote_amount = to_e18(10000000000000000000000);
    fund(base_token, owner(), base_amount);
    fund(quote_token, owner(), quote_amount);
    if approve_solver {
        approve(base_token, owner(), solver.contract_address, base_amount);
        approve(quote_token, owner(), solver.contract_address, quote_amount);
    }

    // Fund LP with initial token balances and approve strategy and market manager as spenders.
    fund(base_token, alice(), base_amount);
    fund(quote_token, alice(), quote_amount);
    if approve_solver {
        approve(base_token, alice(), solver.contract_address, base_amount);
        approve(quote_token, alice(), solver.contract_address, quote_amount);
    }

    (base_token, quote_token, vault_token_class.class_hash, solver, market_id, vault_token_opt)
}

pub fn snapshot(
    solver: ISolverDispatcher,
    market_id: felt252,
    base_token: ERC20ABIDispatcher,
    quote_token: ERC20ABIDispatcher,
    vault_token_addr: ContractAddress,
    lp: ContractAddress,
) -> Snapshot {
    let lp_base_bal = base_token.balanceOf(lp);
    let lp_quote_bal = quote_token.balanceOf(lp);
    let mut vault_lp_bal = 0;
    let mut vault_total_bal = 0;
    if vault_token_addr != contract_address_const::<0x0>() {
        let vault_token = ERC20ABIDispatcher { contract_address: vault_token_addr };
        vault_lp_bal = vault_token.balanceOf(lp);
        vault_total_bal = vault_token.totalSupply();
    }
    let solver_base_bal = base_token.balanceOf(solver.contract_address);
    let solver_quote_bal = quote_token.balanceOf(solver.contract_address);
    let market_state = solver.market_state(market_id);

    Snapshot {
        lp_base_bal,
        lp_quote_bal,
        vault_lp_bal,
        vault_total_bal,
        solver_base_bal,
        solver_quote_bal,
        market_state,
    }
}
