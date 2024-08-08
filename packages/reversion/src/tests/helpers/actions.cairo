// Core lib imports.
use starknet::syscalls::deploy_syscall;
use starknet::ContractAddress;
use starknet::class_hash::ClassHash;

// Local imports.
use haiko_solver_reversion::contracts::mocks::mock_pragma_oracle::{
    IMockPragmaOracleDispatcher, IMockPragmaOracleDispatcherTrait
};
use haiko_solver_core::interfaces::ISolver::ISolverDispatcher;

// External imports.
use snforge_std::{declare, ContractClass, ContractClassTrait, start_prank, stop_prank};

pub fn deploy_reversion_solver(
    solver_class: ContractClass,
    owner: ContractAddress,
    oracle: ContractAddress,
    vault_token_class: ClassHash,
) -> ISolverDispatcher {
    let calldata = array![owner.into(), oracle.into(), vault_token_class.into()];
    let contract_address = solver_class.deploy(@calldata).unwrap();
    ISolverDispatcher { contract_address }
}

pub fn deploy_mock_pragma_oracle(
    oracle_class: ContractClass, owner: ContractAddress,
) -> IMockPragmaOracleDispatcher {
    let contract_address = oracle_class.deploy(@array![]).unwrap();
    IMockPragmaOracleDispatcher { contract_address }
}
