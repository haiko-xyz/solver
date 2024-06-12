// Core lib imports.
use starknet::contract_address_const;

// Local imports.
use haiko_solver_replicating::{
    contracts::solver::ReplicatingSolver,
    contracts::mocks::{
        mock_pragma_oracle::{IMockPragmaOracleDispatcher, IMockPragmaOracleDispatcherTrait},
        upgraded_replicating_solver::{
            IUpgradedReplicatingSolverDispatcher, IUpgradedReplicatingSolverDispatcherTrait
        },
    },
    interfaces::{
        IVaultToken::{IVaultTokenDispatcher, IVaultTokenDispatcherTrait},
        IReplicatingSolver::{IReplicatingSolverDispatcher, IReplicatingSolverDispatcherTrait},
    },
    types::replicating::{MarketInfo, MarketParams},
    tests::{
        helpers::{
            actions::{deploy_replicating_solver, deploy_mock_pragma_oracle},
            params::default_market_params,
            utils::{before, before_custom_decimals, before_skip_approve, snapshot},
        },
    },
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
fn test_upgrade_replicating_solver() {
    let (
        _base_token, _quote_token, _oracle, _vault_token_class, solver, _market_id, _vault_token_opt
    ) =
        before(
        true
    );

    // Log events.
    let mut spy = spy_events(SpyOn::One(solver.contract_address));

    // Upgrade solver.
    let class_hash = declare("UpgradedReplicatingSolver").class_hash;
    start_prank(CheatTarget::One(solver.contract_address), owner());
    solver.upgrade(class_hash);
    // Should be able to call new entrypoint
    IUpgradedReplicatingSolverDispatcher { contract_address: solver.contract_address }.foo();

    // Check event emitted.
    spy
        .assert_emitted(
            @array![
                (
                    solver.contract_address,
                    ReplicatingSolver::Event::Upgraded(ReplicatingSolver::Upgraded { class_hash })
                )
            ]
        );
}


#[test]
#[should_panic(expected: ('OnlyOwner',))]
fn test_upgrade_replicating_solver_not_owner() {
    let (
        _base_token, _quote_token, _oracle, _vault_token_class, solver, _market_id, _vault_token_opt
    ) =
        before(
        true
    );

    start_prank(CheatTarget::One(solver.contract_address), alice());
    let class_hash = declare("UpgradedReplicatingSolver").class_hash;
    solver.upgrade(class_hash);
}
