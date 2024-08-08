use haiko_solver_reversion::types::{MarketParams, TrendState};

#[starknet::interface]
pub trait IStorePackingContract<TContractState> {
    fn get_market_params(self: @TContractState, market_id: felt252) -> MarketParams;
    fn get_trend_state(self: @TContractState, market_id: felt252) -> TrendState;

    fn set_market_params(ref self: TContractState, market_id: felt252, market_params: MarketParams);
    fn set_trend_state(ref self: TContractState, market_id: felt252, trend_state: TrendState);
}

#[starknet::contract]
pub mod StorePackingContract {
    use haiko_solver_reversion::types::{MarketParams, TrendState};
    use haiko_solver_reversion::libraries::store_packing::{
        MarketParamsStorePacking, TrendStateStorePacking
    };
    use super::IStorePackingContract;

    ////////////////////////////////
    // STORAGE
    ////////////////////////////////

    #[storage]
    struct Storage {
        market_params: LegacyMap::<felt252, MarketParams>,
        trend_state: LegacyMap::<felt252, TrendState>,
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

        fn get_trend_state(self: @ContractState, market_id: felt252) -> TrendState {
            self.trend_state.read(market_id)
        }

        ////////////////////////////////
        // EXTERNAL FUNCTIONS
        ////////////////////////////////

        fn set_market_params(
            ref self: ContractState, market_id: felt252, market_params: MarketParams
        ) {
            self.market_params.write(market_id, market_params);
        }

        fn set_trend_state(ref self: ContractState, market_id: felt252, trend_state: TrendState) {
            self.trend_state.write(market_id, trend_state);
        }
    }
}
