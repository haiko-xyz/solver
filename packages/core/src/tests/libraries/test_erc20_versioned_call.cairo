// Core lib imports.
use starknet::syscalls::{deploy_syscall, call_contract_syscall};
use core::to_byte_array::{FormatAsByteArray, AppendFormattedToByteArray};

// Local imports.
use haiko_solver_core::contracts::mocks::{
    erc20_bytearray::{IERC20ByteArrayDispatcher, IERC20ByteArrayDispatcherTrait},
    erc20_felt252::{IERC20Felt252Dispatcher, IERC20Felt252DispatcherTrait},
};
use haiko_solver_core::libraries::erc20_versioned_call;

// External imports.
use snforge_std::{declare, ContractClassTrait};
use openzeppelin::token::erc20::interface::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};

#[test]
fn test_erc20_bytearray() {
    let erc20_class = declare("ERC20ByteArray");
    let name: ByteArray = "Mock";
    let symbol: ByteArray = "MOCK";
    let mut calldata = array![];
    name.serialize(ref calldata);
    symbol.serialize(ref calldata);
    let contract_address = erc20_class.deploy(@calldata).unwrap();
    let result = erc20_versioned_call::get_symbol(contract_address);
    assert(result == "MOCK", 'Symbol (byte array)');
}

#[test]
fn test_erc20_felt252() {
    // Deploy erc20
    let erc20_class = declare("ERC20Felt252");
    let name: felt252 = 'Mock';
    let symbol: felt252 = 'MOCK';
    let mut calldata: Array<felt252> = array![];
    name.serialize(ref calldata);
    symbol.serialize(ref calldata);
    let contract_address = erc20_class.deploy(@calldata).unwrap();
    let result = erc20_versioned_call::get_symbol(contract_address);
    assert(result == "MOCK", 'Symbol (felt252)');
}
