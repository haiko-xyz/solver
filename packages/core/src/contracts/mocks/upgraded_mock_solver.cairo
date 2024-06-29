use starknet::ContractAddress;

#[starknet::interface]
pub trait IUpgradedMockSolver<TContractState> {
    fn foo(self: @TContractState) -> u32;
}

#[starknet::contract]
pub mod UpgradedMockSolver {
    use super::IUpgradedMockSolver;

    ////////////////////////////////
    // STORAGE
    ////////////////////////////////

    #[storage]
    struct Storage {
        foo: u32,
    }

    ////////////////////////////////
    // CONSTRUCTOR
    ////////////////////////////////

    #[abi(embed_v0)]
    impl UpgradedMockSolver of IUpgradedMockSolver<ContractState> {
        ////////////////////////////////
        // VIEW FUNCTIONS
        ////////////////////////////////

        fn foo(self: @ContractState) -> u32 {
            self.foo.read()
        }
    }
}
