// Core lib imports.
use starknet::syscalls::deploy_syscall;
use starknet::ContractAddress;
use starknet::class_hash::ClassHash;

// Local imports.
use haiko_solver_core::interfaces::ISolver::ISolverDispatcher;

// External imports.
use snforge_std::{declare, ContractClass, ContractClassTrait, start_prank, stop_prank};

pub fn deploy_mock_solver(
    solver_class: ContractClass, owner: ContractAddress, vault_token_class: ClassHash,
) -> ISolverDispatcher {
    let calldata = array![owner.into(), vault_token_class.into()];
    let contract_address = solver_class.deploy(@calldata).unwrap();
    ISolverDispatcher { contract_address }
}
