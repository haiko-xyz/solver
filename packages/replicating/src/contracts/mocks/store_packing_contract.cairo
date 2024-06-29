use haiko_solver_replicating::types::MarketParams;

#[starknet::interface]
pub trait IStorePackingContract<TContractState> {
    fn get_market_params(self: @TContractState, market_id: felt252) -> MarketParams;

    fn set_market_params(ref self: TContractState, market_id: felt252, market_params: MarketParams);
}

#[starknet::contract]
pub mod StorePackingContract {
    use haiko_solver_replicating::types::MarketParams;
    use haiko_solver_replicating::libraries::store_packing::MarketParamsStorePacking;
    use super::IStorePackingContract;

    ////////////////////////////////
    // STORAGE
    ////////////////////////////////

    #[storage]
    struct Storage {
        market_params: LegacyMap::<felt252, MarketParams>,
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

        ////////////////////////////////
        // EXTERNAL FUNCTIONS
        ////////////////////////////////

        fn set_market_params(
            ref self: ContractState, market_id: felt252, market_params: MarketParams
        ) {
            self.market_params.write(market_id, market_params);
        }
    }
}
