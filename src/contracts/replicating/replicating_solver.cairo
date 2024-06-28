#[starknet::contract]
pub mod ReplicatingSolver {
    // Core lib imports.
    use starknet::ContractAddress;
    use starknet::contract_address::contract_address_const;
    use starknet::get_block_timestamp;
    use starknet::class_hash::ClassHash;

    // Local imports.
    use haiko_solver::contracts::core::solver::SolverComponent;
    use haiko_solver::libraries::{
        swap_lib, spread_math, id, store_packing::MarketParamsStorePacking
    };
    use haiko_solver::interfaces::{
        ISolver::ISolverQuoter, IReplicatingSolver::IReplicatingSolver,
        pragma::{
            AggregationMode, DataType, SimpleDataType, PragmaPricesResponse, IOracleABIDispatcher,
            IOracleABIDispatcherTrait
        },
    };
    use haiko_solver::types::{
        core::{PositionInfo, MarketState, MarketInfo, SwapParams}, replicating::MarketParams
    };

    // Haiko imports.
    use haiko_lib::math::math;

    // External imports.
    use openzeppelin::token::erc20::interface::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};

    ////////////////////////////////
    // COMPONENTS
    ///////////////////////////////

    component!(path: SolverComponent, storage: solver, event: SolverEvent);

    #[abi(embed_v0)]
    impl SolverImpl = SolverComponent::SolverImpl<ContractState>;
    impl SolverModifierImpl = SolverComponent::SolverModifier<ContractState>;
    impl SolverInternalImpl = SolverComponent::InternalImpl<ContractState>;

    ////////////////////////////////
    // STORAGE
    ///////////////////////////////

    #[storage]
    struct Storage {
        // Solver
        #[substorage(v0)]
        solver: SolverComponent::Storage,
        // oracle for price and volatility feeds
        oracle: IOracleABIDispatcher,
        // Indexed by market id
        market_params: LegacyMap::<felt252, MarketParams>,
    }

    ////////////////////////////////
    // EVENTS
    ///////////////////////////////

    #[event]
    #[derive(Drop, starknet::Event)]
    pub(crate) enum Event {
        SetMarketParams: SetMarketParams,
        ChangeOracle: ChangeOracle,
        #[flat]
        SolverEvent: SolverComponent::Event,
    }

    #[derive(Drop, starknet::Event)]
    pub(crate) struct SetMarketParams {
        #[key]
        pub market_id: felt252,
        pub min_spread: u32,
        pub range: u32,
        pub max_delta: u32,
        pub max_skew: u16,
        pub base_currency_id: felt252,
        pub quote_currency_id: felt252,
        pub min_sources: u32,
        pub max_age: u64,
    }

    #[derive(Drop, starknet::Event)]
    pub(crate) struct ChangeOracle {
        pub oracle: ContractAddress,
    }

    ////////////////////////////////
    // CONSTRUCTOR
    ////////////////////////////////

    #[constructor]
    fn constructor(
        ref self: ContractState,
        owner: ContractAddress,
        oracle: ContractAddress,
        vault_token_class: ClassHash,
    ) {
        self.solver._initializer("Replicating", "REPL", owner, vault_token_class);
        let oracle_dispatcher = IOracleABIDispatcher { contract_address: oracle };
        self.oracle.write(oracle_dispatcher);
    }

    ////////////////////////////////
    // FUNCTIONS
    ////////////////////////////////

    #[abi(embed_v0)]
    impl SolverQuoter of ISolverQuoter<ContractState> {
        // Obtain quote for swap through a solver market.
        // 
        // # Arguments
        // * `market_id` - market id
        // * `swap_params` - swap parameters
        //
        // # Returns
        // * `amount_in` - amount in
        // * `amount_out` - amount out
        fn quote(
            self: @ContractState, market_id: felt252, swap_params: SwapParams,
        ) -> (u256, u256) {
            // Run validity checks.
            let state: MarketState = self.solver.market_state.read(market_id);
            let market_info: MarketInfo = self.solver.market_info.read(market_id);
            assert(market_info.base_token != contract_address_const::<0x0>(), 'MarketNull');
            assert(!state.is_paused, 'Paused');

            // Fetch oracle price.
            let (oracle_price, is_valid) = self.get_oracle_price(market_id);
            assert(is_valid, 'InvalidOraclePrice');

            // Calculate swap amounts.
            let params = self.market_params.read(market_id);
            let delta = spread_math::get_delta(
                params.max_delta, state.base_reserves, state.quote_reserves, oracle_price
            );
            let is_bid = !swap_params.is_buy;
            let reserves = if is_bid {
                state.quote_reserves
            } else {
                state.base_reserves
            };
            let (lower_limit, upper_limit) = spread_math::get_virtual_position_range(
                is_bid, params.min_spread, delta, params.range, oracle_price
            );
            let position = spread_math::get_virtual_position(
                is_bid, lower_limit, upper_limit, reserves
            );
            let (amount_in, amount_out) = swap_lib::get_swap_amounts(swap_params, position);

            // Check deposited amounts does not violate max skew, or if it does, that
            // the deposit reduces the extent of skew.
            let (base_reserves, quote_reserves) = if swap_params.is_buy {
                (state.base_reserves - amount_out, state.quote_reserves + amount_in)
            } else {
                (state.base_reserves + amount_in, state.quote_reserves - amount_out)
            };
            if params.max_skew != 0 {
                let (skew_before, _) = spread_math::get_skew(
                    state.base_reserves, state.quote_reserves, oracle_price
                );
                let (skew_after, _) = spread_math::get_skew(
                    base_reserves, quote_reserves, oracle_price
                );
                if skew_after > params.max_skew.into() {
                    assert(skew_after < skew_before, 'MaxSkew');
                }
            }

            // Return amounts.
            (amount_in, amount_out)
        }

        // Get virtual liquidity positions against which swaps are executed.
        // 
        // # Arguments
        // * `market_id` - market id
        //
        // # Returns
        // * `bid` - bid position
        // * `ask` - ask position
        fn get_virtual_positions(
            self: @ContractState, market_id: felt252
        ) -> (PositionInfo, PositionInfo) {
            // Fetch state.
            let state: MarketState = self.solver.market_state.read(market_id);
            let params: MarketParams = self.market_params.read(market_id);

            // Fetch oracle price.
            let (oracle_price, is_valid) = self.get_oracle_price(market_id);
            assert(is_valid, 'InvalidOraclePrice');

            // Calculate position ranges.
            let delta = spread_math::get_delta(
                params.max_delta, state.base_reserves, state.quote_reserves, oracle_price
            );
            let (bid_lower, bid_upper) = spread_math::get_virtual_position_range(
                true, params.min_spread, delta, params.range, oracle_price
            );
            let (ask_lower, ask_upper) = spread_math::get_virtual_position_range(
                false, params.min_spread, delta, params.range, oracle_price
            );

            // Calculate and return positions.
            let mut bid: PositionInfo = Default::default();
            let mut ask: PositionInfo = Default::default();
            if state.quote_reserves != 0 {
                bid =
                    spread_math::get_virtual_position(
                        true, bid_lower, bid_upper, state.quote_reserves
                    );
            }
            if state.base_reserves != 0 {
                ask =
                    spread_math::get_virtual_position(
                        false, ask_lower, ask_upper, state.base_reserves
                    );
            }

            (bid, ask)
        }
    }

    #[abi(embed_v0)]
    impl ReplicatingSolver of IReplicatingSolver<ContractState> {
        // Market parameters
        fn market_params(self: @ContractState, market_id: felt252) -> MarketParams {
            self.market_params.read(market_id)
        }

        // Pragma oracle contract address
        fn oracle(self: @ContractState) -> ContractAddress {
            self.oracle.read().contract_address
        }

        // Get price from oracle feed.
        // 
        // # Arguments
        // * `market_id` - market id
        //
        // # Returns
        // * `price` - oracle price, base 1e28
        // * `is_valid` - whether oracle price passes validity checks re number of sources and age
        fn get_oracle_price(self: @ContractState, market_id: felt252) -> (u256, bool) {
            // Fetch state.
            let oracle = self.oracle.read();
            let market_info: MarketInfo = self.solver.market_info.read(market_id);
            let params = self.market_params.read(market_id);

            // Fetch oracle price.
            let output: PragmaPricesResponse = oracle
                .get_data_with_USD_hop(
                    params.base_currency_id,
                    params.quote_currency_id,
                    AggregationMode::Median(()),
                    SimpleDataType::SpotEntry(()),
                    Option::None(())
                );

            // Validate number of sources and age of oracle price.
            let now = get_block_timestamp();
            let is_valid = (output.num_sources_aggregated >= params.min_sources)
                && (output.last_updated_timestamp + params.max_age >= now);

            // Calculate and return scaled price. We want to return the price base 1e28,
            // but we must also scale it by the number of decimals in the oracle price and
            // the token pair.
            let base_token = ERC20ABIDispatcher { contract_address: market_info.base_token };
            let quote_token = ERC20ABIDispatcher { contract_address: market_info.quote_token };
            let base_decimals: u256 = base_token.decimals().into();
            let quote_decimals: u256 = quote_token.decimals().into();
            assert(28 + quote_decimals >= output.decimals.into() + base_decimals, 'DecimalsUF');
            let decimals: u256 = 28 + quote_decimals - output.decimals.into() - base_decimals;
            let scaling_factor = math::pow(10, decimals);
            (output.price.into() * scaling_factor, is_valid)
        }

        // Change parameters of the solver market.
        // Only callable by market owner.
        //
        // # Params
        // * `market_id` - market id
        // * `params` - market params
        fn set_market_params(ref self: ContractState, market_id: felt252, params: MarketParams) {
            // Run checks.
            self.solver.assert_market_owner(market_id);
            let old_params = self.market_params.read(market_id);
            assert(old_params != params, 'ParamsUnchanged');
            assert(params.range != 0, 'RangeZero');
            assert(params.min_sources != 0, 'MinSourcesZero');
            assert(params.max_age != 0, 'MaxAgeZero');
            assert(params.base_currency_id != 0, 'BaseIdZero');
            assert(params.quote_currency_id != 0, 'QuoteIdZero');

            // Update state.
            self.market_params.write(market_id, params);

            // Emit event.
            self
                .emit(
                    Event::SetMarketParams(
                        SetMarketParams {
                            market_id,
                            min_spread: params.min_spread,
                            range: params.range,
                            max_delta: params.max_delta,
                            max_skew: params.max_skew,
                            base_currency_id: params.base_currency_id,
                            quote_currency_id: params.quote_currency_id,
                            min_sources: params.min_sources,
                            max_age: params.max_age,
                        }
                    )
                );
        }

        // Change the oracle contract address.
        //
        // # Arguments
        // * `oracle` - contract address of oracle feed
        fn change_oracle(ref self: ContractState, oracle: ContractAddress) {
            self.solver.assert_owner();
            let old_oracle = self.oracle.read();
            assert(oracle != old_oracle.contract_address, 'OracleUnchanged');
            let oracle_dispatcher = IOracleABIDispatcher { contract_address: oracle };
            self.oracle.write(oracle_dispatcher);
            self.emit(Event::ChangeOracle(ChangeOracle { oracle }));
        }
    }
}
