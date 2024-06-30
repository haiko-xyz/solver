use starknet::ContractAddress;

#[starknet::interface]
pub trait IUpgradedReplicatingSolver<TContractState> {
    fn foo(self: @TContractState) -> u32;
}

#[starknet::contract]
pub mod UpgradedReplicatingSolver {
    use super::IUpgradedReplicatingSolver;

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
    impl UpgradedReplicatingSolver of IUpgradedReplicatingSolver<ContractState> {
        ////////////////////////////////
        // VIEW FUNCTIONS
        ////////////////////////////////

        fn foo(self: @ContractState) -> u32 {
            self.foo.read()
        }
    }
}
