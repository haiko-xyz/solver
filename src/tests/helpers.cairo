// Core lib imports.
use starknet::syscalls::deploy_syscall;
use starknet::ContractAddress;
use starknet::class_hash::ClassHash;

// Local imports.
use haiko_solver_replicating::contracts::mocks::mock_pragma_oracle::{
    IMockPragmaOracleDispatcher, IMockPragmaOracleDispatcherTrait
};
use haiko_solver_replicating::interfaces::IReplicatingSolver::IReplicatingSolverDispatcher;

// External imports.
use snforge_std::{declare, ContractClassTrait, start_prank, stop_prank};

pub fn deploy_replicating_solver(
    owner: ContractAddress, oracle: ContractAddress, vault_token_class: ClassHash,
) -> IReplicatingSolverDispatcher {
    let contract = declare("ReplicatingSolver");
    let calldata = array![owner.into(), oracle.into(), vault_token_class.into()];
    let contract_address = contract.deploy(@calldata).unwrap();
    IReplicatingSolverDispatcher { contract_address }
}

pub fn deploy_mock_pragma_oracle(owner: ContractAddress,) -> IMockPragmaOracleDispatcher {
    let contract = declare("MockPragmaOracle");
    let contract_address = contract.deploy(@array![]).unwrap();
    IMockPragmaOracleDispatcher { contract_address }
}
