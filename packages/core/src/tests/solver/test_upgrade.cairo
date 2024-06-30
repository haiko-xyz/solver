// Core lib imports.
use starknet::contract_address_const;

// Local imports.
use haiko_solver_core::{
    contracts::solver::SolverComponent,
    contracts::mocks::upgraded_mock_solver::{
        IUpgradedMockSolverDispatcher, IUpgradedMockSolverDispatcherTrait
    },
    interfaces::{
        ISolver::{ISolverDispatcher, ISolverDispatcherTrait},
        IVaultToken::{IVaultTokenDispatcher, IVaultTokenDispatcherTrait},
    },
    types::MarketInfo, tests::helpers::{actions::deploy_mock_solver, utils::{before, snapshot},}
};

// Haiko imports.
use haiko_lib::helpers::params::{owner, alice};
use haiko_lib::helpers::utils::{to_e18, approx_eq, approx_eq_pct};
use haiko_lib::helpers::actions::token::{fund, approve};

// External imports.
use snforge_std::{
    start_prank, stop_prank, start_warp, declare, spy_events, SpyOn, EventSpy, EventAssertions,
    CheatTarget
};
use openzeppelin::token::erc20::interface::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};

////////////////////////////////
// TESTS
////////////////////////////////

#[test]
fn test_upgrade_solver() {
    let (_base_token, _quote_token, _vault_token_class, solver, _market_id, _vault_token_opt) =
        before(
        true
    );

    // Log events.
    let mut spy = spy_events(SpyOn::One(solver.contract_address));

    // Upgrade solver.
    let class_hash = declare("UpgradedMockSolver").class_hash;
    start_prank(CheatTarget::One(solver.contract_address), owner());
    solver.upgrade(class_hash);
    // Should be able to call new entrypoint
    IUpgradedMockSolverDispatcher { contract_address: solver.contract_address }.foo();

    // Check event emitted.
    spy
        .assert_emitted(
            @array![
                (
                    solver.contract_address,
                    SolverComponent::Event::Upgraded(SolverComponent::Upgraded { class_hash })
                )
            ]
        );
}


#[test]
#[should_panic(expected: ('OnlyOwner',))]
fn test_upgrade_solver_not_owner() {
    let (_base_token, _quote_token, _vault_token_class, solver, _market_id, _vault_token_opt) =
        before(
        true
    );

    start_prank(CheatTarget::One(solver.contract_address), alice());
    let class_hash = declare("UpgradedMockSolver").class_hash;
    solver.upgrade(class_hash);
}
