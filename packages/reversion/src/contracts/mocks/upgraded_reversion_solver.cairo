use starknet::ContractAddress;

#[starknet::interface]
pub trait IUpgradedReversionSolver<TContractState> {
    fn foo(self: @TContractState) -> u32;
}

#[starknet::contract]
pub mod UpgradedReversionSolver {
    use super::IUpgradedReversionSolver;

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
    impl UpgradedReversionSolver of IUpgradedReversionSolver<ContractState> {
        ////////////////////////////////
        // VIEW FUNCTIONS
        ////////////////////////////////

        fn foo(self: @ContractState) -> u32 {
            self.foo.read()
        }
    }
}
