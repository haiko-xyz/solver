use haiko_solver_reversion::types::{MarketParams, ModelParams};

#[starknet::interface]
pub trait IStorePackingContract<TContractState> {
    fn get_market_params(self: @TContractState, market_id: felt252) -> MarketParams;
    fn get_model_params(self: @TContractState, market_id: felt252) -> ModelParams;

    fn set_market_params(ref self: TContractState, market_id: felt252, market_params: MarketParams);
    fn set_model_params(ref self: TContractState, market_id: felt252, model_params: ModelParams);
}

#[starknet::contract]
pub mod StorePackingContract {
    use haiko_solver_reversion::types::{MarketParams, ModelParams};
    use haiko_solver_reversion::libraries::store_packing::{
        MarketParamsStorePacking, ModelParamsStorePacking
    };
    use super::IStorePackingContract;

    ////////////////////////////////
    // STORAGE
    ////////////////////////////////

    #[storage]
    struct Storage {
        market_params: LegacyMap::<felt252, MarketParams>,
        model_params: LegacyMap::<felt252, ModelParams>,
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

        fn get_model_params(self: @ContractState, market_id: felt252) -> ModelParams {
            self.model_params.read(market_id)
        }

        ////////////////////////////////
        // EXTERNAL FUNCTIONS
        ////////////////////////////////

        fn set_market_params(
            ref self: ContractState, market_id: felt252, market_params: MarketParams
        ) {
            self.market_params.write(market_id, market_params);
        }

        fn set_model_params(
            ref self: ContractState, market_id: felt252, model_params: ModelParams
        ) {
            self.model_params.write(market_id, model_params);
        }
    }
}
