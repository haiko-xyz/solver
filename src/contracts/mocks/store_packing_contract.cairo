use haiko_solver_replicating::types::replicating::{MarketParams, MarketState};

#[starknet::interface]
pub trait IStorePackingContract<TContractState> {
    fn get_market_params(self: @TContractState, market_id: felt252) -> MarketParams;
    fn get_market_state(self: @TContractState, market_id: felt252) -> MarketState;

    fn set_market_params(ref self: TContractState, market_id: felt252, market_params: MarketParams);
    fn set_market_state(ref self: TContractState, market_id: felt252, market_state: MarketState);
}

#[starknet::contract]
pub mod StorePackingContract {
    use haiko_solver_replicating::types::replicating::{MarketParams, MarketState};
    use haiko_solver_replicating::libraries::store_packing::{
        MarketParamsStorePacking, MarketStateStorePacking,
    };
    use super::IStorePackingContract;

    ////////////////////////////////
    // STORAGE
    ////////////////////////////////

    #[storage]
    struct Storage {
        market_params: LegacyMap::<felt252, MarketParams>,
        market_state: LegacyMap::<felt252, MarketState>,
    }

    #[constructor]
    fn constructor(ref self: ContractState,) {}

    #[abi(embed_v0)]
    impl StorePackingContract of IStorePackingContract<ContractState> {
        ////////////////////////////////
        // VIEW FUNCTIONS
        ////////////////////////////////

        fn get_market_params(self: @ContractState, market_id: felt252) -> MarketParams {
            self.market_params.read(market_id)
        }

        fn get_market_state(self: @ContractState, market_id: felt252) -> MarketState {
            self.market_state.read(market_id)
        }

        ////////////////////////////////
        // EXTERNAL FUNCTIONS
        ////////////////////////////////

        fn set_market_params(
            ref self: ContractState, market_id: felt252, market_params: MarketParams
        ) {
            self.market_params.write(market_id, market_params);
        }

        fn set_market_state(
            ref self: ContractState, market_id: felt252, market_state: MarketState
        ) {
            self.market_state.write(market_id, market_state);
        }
    }
}
