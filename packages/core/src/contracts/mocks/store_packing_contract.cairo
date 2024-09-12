use haiko_solver_core::types::{MarketState, FeesPerShare};

#[starknet::interface]
pub trait IStorePackingContract<TContractState> {
    fn get_market_state(self: @TContractState, market_id: felt252) -> MarketState;

    fn set_market_state(ref self: TContractState, market_id: felt252, market_state: MarketState);

    fn get_fees_per_share(self: @TContractState, market_id: felt252) -> FeesPerShare;

    fn set_fees_per_share(
        ref self: TContractState, market_id: felt252, fees_per_share: FeesPerShare
    );
}

#[starknet::contract]
pub mod StorePackingContract {
    use haiko_solver_core::types::{MarketState, FeesPerShare};
    use haiko_solver_core::libraries::store_packing::{
        MarketStateStorePacking, FeesPerShareStorePacking
    };
    use super::IStorePackingContract;

    ////////////////////////////////
    // STORAGE
    ////////////////////////////////

    #[storage]
    struct Storage {
        market_state: LegacyMap::<felt252, MarketState>,
        fees_per_share: LegacyMap::<felt252, FeesPerShare>,
    }

    #[constructor]
    fn constructor(ref self: ContractState,) {}

    #[abi(embed_v0)]
    impl StorePackingContract of IStorePackingContract<ContractState> {
        ////////////////////////////////
        // VIEW FUNCTIONS
        ////////////////////////////////

        fn get_market_state(self: @ContractState, market_id: felt252) -> MarketState {
            self.market_state.read(market_id)
        }

        fn get_fees_per_share(self: @ContractState, market_id: felt252) -> FeesPerShare {
            self.fees_per_share.read(market_id)
        }

        ////////////////////////////////
        // EXTERNAL FUNCTIONS
        ////////////////////////////////

        fn set_market_state(
            ref self: ContractState, market_id: felt252, market_state: MarketState
        ) {
            self.market_state.write(market_id, market_state);
        }

        fn set_fees_per_share(
            ref self: ContractState, market_id: felt252, fees_per_share: FeesPerShare
        ) {
            self.fees_per_share.write(market_id, fees_per_share);
        }
    }
}
