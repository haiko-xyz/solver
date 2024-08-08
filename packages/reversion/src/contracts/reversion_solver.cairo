#[starknet::contract]
pub mod ReversionSolver {
    // Core lib imports.
    use starknet::ContractAddress;
    use starknet::contract_address::contract_address_const;
    use starknet::{get_caller_address, get_block_timestamp};
    use starknet::class_hash::ClassHash;

    // Local imports.
    use haiko_solver_core::contracts::solver::SolverComponent;
    use haiko_solver_core::interfaces::ISolver::ISolverHooks;
    use haiko_solver_reversion::libraries::{
        swap_lib, spread_math, store_packing::{MarketParamsStorePacking, TrendStateStorePacking}
    };
    use haiko_solver_reversion::interfaces::{
        IReversionSolver::IReversionSolver,
        pragma::{
            AggregationMode, DataType, SimpleDataType, PragmaPricesResponse, IOracleABIDispatcher,
            IOracleABIDispatcherTrait
        },
    };
    use haiko_solver_core::types::{PositionInfo, MarketState, MarketInfo, SwapParams};
    use haiko_solver_reversion::types::{MarketParams, TrendState, Trend};

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
        // trend setter admin with permission to change trend
        trend_setter: ContractAddress,
        // Indexed by market id
        market_params: LegacyMap::<felt252, MarketParams>,
        // Indexed by market id
        queued_market_params: LegacyMap::<felt252, MarketParams>,
        // Indexed by market id
        trend_state: LegacyMap::<felt252, TrendState>,
        // Indexed by market id
        // timestamp when market params were queued
        queued_at: LegacyMap::<felt252, u64>,
        // delay in seconds for confirming queued market params
        delay: u64,
    }

    ////////////////////////////////
    // EVENTS
    ///////////////////////////////

    #[event]
    #[derive(Drop, starknet::Event)]
    pub(crate) enum Event {
        SetTrend: SetTrend,
        QueueMarketParams: QueueMarketParams,
        SetMarketParams: SetMarketParams,
        SetDelay: SetDelay,
        ChangeOracle: ChangeOracle,
        ChangeTrendSetter: ChangeTrendSetter,
        #[flat]
        SolverEvent: SolverComponent::Event,
    }

    #[derive(Drop, starknet::Event)]
    pub(crate) struct SetTrend {
        #[key]
        pub market_id: felt252,
        pub trend: Trend,
    }

    #[derive(Drop, starknet::Event)]
    pub(crate) struct QueueMarketParams {
        #[key]
        pub market_id: felt252,
        pub spread: u32,
        pub range: u32,
        pub base_currency_id: felt252,
        pub quote_currency_id: felt252,
        pub min_sources: u32,
        pub max_age: u64,
    }

    #[derive(Drop, starknet::Event)]
    pub(crate) struct SetMarketParams {
        #[key]
        pub market_id: felt252,
        pub spread: u32,
        pub range: u32,
        pub base_currency_id: felt252,
        pub quote_currency_id: felt252,
        pub min_sources: u32,
        pub max_age: u64,
    }

    #[derive(Drop, starknet::Event)]
    pub(crate) struct SetDelay {
        pub delay: u64,
    }

    #[derive(Drop, starknet::Event)]
    pub(crate) struct ChangeOracle {
        pub oracle: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    pub(crate) struct ChangeTrendSetter {
        pub trend_setter: ContractAddress,
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
        self.solver._initializer("Reversion", "RVRS", owner, vault_token_class);
        let oracle_dispatcher = IOracleABIDispatcher { contract_address: oracle };
        self.oracle.write(oracle_dispatcher);
    }

    ////////////////////////////////
    // FUNCTIONS
    ////////////////////////////////

    #[abi(embed_v0)]
    impl SolverHooks of ISolverHooks<ContractState> {
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

            // Get virtual positions.
            let (bid, ask) = self.get_virtual_positions(market_id);
            let position = if swap_params.is_buy {
                ask
            } else {
                bid
            };

            // Calculate and return swap amounts.
            swap_lib::get_swap_amounts(swap_params, position)
        }

        // Get the initial token supply to mint when first depositing to a market.
        //
        // # Arguments
        // * `market_id` - market id
        // * `base_amount` - base amount deposited
        // * `quote_amount` - quote amount deposited
        //
        // # Returns
        // * `initial_supply` - initial supply
        fn initial_supply(self: @ContractState, market_id: felt252) -> u256 {
            // Query virtual positions. State should already be committed when this is called so 
            // it will reflect the amounts deposited as part of this call.
            let (bid, ask) = self.get_virtual_positions(market_id);

            // Calculate initial supply.            
            (bid.liquidity + ask.liquidity).into()
        }

        // Callback function to execute any state updates after a swap is completed.
        // This fn should only be callable by the solver contract.
        //
        // # Arguments
        // * `market_id` - market id
        // * `swap_params` - swap parameters
        fn after_swap(ref self: ContractState, market_id: felt252, swap_params: SwapParams) {
            // Run checks.
            assert(self.solver.unlocked.read(), 'NotSolver');

            // Fetch state.
            let mut trend_state: TrendState = self.trend_state.read(market_id);
            let oracle_output = self.get_unscaled_oracle_price(market_id);

            // Calculate conditions for updating cached price.
            //  1. if price trends up and price > cached price, update cached price
            //  2. if price trends down and price < cached price, update cached price
            //  3. otherwise, don't update
            if trend_state.trend == Trend::Up
                && oracle_output.price > trend_state.cached_price
                    || trend_state.trend == Trend::Down
                && oracle_output.price < trend_state.cached_price {
                trend_state.cached_price = oracle_output.price;
                trend_state.cached_decimals = oracle_output.decimals;
                self.trend_state.write(market_id, trend_state);
            };

            // Commit state.
            self.trend_state.write(market_id, trend_state);
        }
    }

    #[abi(embed_v0)]
    impl ReversionSolver of IReversionSolver<ContractState> {
        // Market parameters
        fn market_params(self: @ContractState, market_id: felt252) -> MarketParams {
            self.market_params.read(market_id)
        }

        // Queued market parameters
        fn queued_market_params(self: @ContractState, market_id: felt252) -> MarketParams {
            self.queued_market_params.read(market_id)
        }

        // Delay (in seconds) for setting market parameters
        fn delay(self: @ContractState) -> u64 {
            self.delay.read()
        }

        // Pragma oracle contract address
        fn oracle(self: @ContractState) -> ContractAddress {
            self.oracle.read().contract_address
        }

        // Trend setter contract address
        fn trend_setter(self: @ContractState) -> ContractAddress {
            self.trend_setter.read()
        }

        // Get trend of solver market.
        //
        // # Params
        // * `market_id` - market id
        //
        // # Returns
        // * `trend - market trend
        fn trend(self: @ContractState, market_id: felt252) -> Trend {
            self.trend_state.read(market_id).trend
        }

        // Get unscaled oracle price from oracle feed.
        // 
        // # Arguments
        // * `market_id` - market id
        //
        // # Returns
        // * `output` - Pragma oracle price response
        fn get_unscaled_oracle_price(
            self: @ContractState, market_id: felt252
        ) -> PragmaPricesResponse {
            // Fetch state.
            let oracle = self.oracle.read();
            let params = self.market_params.read(market_id);

            // Fetch oracle price.
            oracle
                .get_data_with_USD_hop(
                    params.base_currency_id,
                    params.quote_currency_id,
                    AggregationMode::Median(()),
                    SimpleDataType::SpotEntry(()),
                    Option::None(())
                )
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
            let market_info: MarketInfo = self.solver.market_info.read(market_id);
            let params = self.market_params.read(market_id);

            // Fetch oracle price.
            let output = self.get_unscaled_oracle_price(market_id);

            // Validate number of sources and age of oracle price.
            let now = get_block_timestamp();
            let is_valid = (output.num_sources_aggregated >= params.min_sources)
                && (output.last_updated_timestamp + params.max_age >= now);

            // Calculate and return scaled price.
            let oracle_price = self.scale_oracle_price(@market_info, output.price, output.decimals);
            (oracle_price, is_valid)
        }

        // Change trend of the solver market.
        // Only callable by market owner.
        //
        // # Params
        // * `market_id` - market id
        // * `trend - market trend
        fn set_trend(ref self: ContractState, market_id: felt252, trend: Trend) {
            let caller = get_caller_address();
            let market_info: MarketInfo = self.solver.market_info.read(market_id);
            let mut trend_state = self.trend_state.read(market_id);
            let trend_setter = self.trend_setter.read();

            // Run checks.
            assert(market_info.base_token != contract_address_const::<0x0>(), 'MarketNull');
            assert(caller == market_info.owner || caller == trend_setter, 'NotApproved');
            assert(trend_state.trend != trend, 'TrendUnchanged');

            // Update state.
            // Whenever we update trend, we also need to update the cached price in case it is stale.
            let oracle_output = self.get_unscaled_oracle_price(market_id);
            trend_state.trend = trend;
            trend_state.cached_price = oracle_output.price;
            trend_state.cached_decimals = oracle_output.decimals;
            self.trend_state.write(market_id, trend_state);

            // Emit event.
            self.emit(Event::SetTrend(SetTrend { market_id, trend, }));
        }

        // Queue change to the parameters of the solver market.
        // This must be accepted after the set delay in order for the change to be applied.
        // Only callable by market owner.
        //
        // # Params
        // * `market_id` - market id
        // * `params` - market params
        fn queue_market_params(ref self: ContractState, market_id: felt252, params: MarketParams) {
            // Run checks.
            self.solver.assert_market_owner(market_id);
            let old_params = self.market_params.read(market_id);
            assert(old_params != params, 'ParamsUnchanged');

            // Update state.
            let now = get_block_timestamp();
            self.queued_market_params.write(market_id, params);
            self.queued_at.write(market_id, now);

            // Emit event.
            self
                .emit(
                    Event::QueueMarketParams(
                        QueueMarketParams {
                            market_id,
                            spread: params.spread,
                            range: params.range,
                            base_currency_id: params.base_currency_id,
                            quote_currency_id: params.quote_currency_id,
                            min_sources: params.min_sources,
                            max_age: params.max_age,
                        }
                    )
                );
        }

        // Confirm and set queued market parameters.
        // Must have been queued for at least the set delay.
        // Only callable by market owner.
        //
        // # Params
        // * `market_id` - market id
        // * `params` - market params
        fn set_market_params(ref self: ContractState, market_id: felt252) {
            // Fetch queued params and delay.
            let params = self.market_params.read(market_id);
            let queued_params = self.queued_market_params.read(market_id);
            let queued_at = self.queued_at.read(market_id);
            let delay = self.delay.read();

            // Run checks.
            self.solver.assert_market_owner(market_id);
            assert(params != queued_params, 'ParamsUnchanged');
            if params != Default::default() {
                // Skip this check if we are initialising the market for first time.
                assert(queued_at + delay <= get_block_timestamp(), 'DelayNotPassed');
            }
            assert(queued_at != 0 && queued_params != Default::default(), 'NotQueued');
            assert(queued_params.range != 0, 'RangeZero');
            assert(queued_params.min_sources != 0, 'MinSourcesZero');
            assert(queued_params.max_age != 0, 'MaxAgeZero');
            assert(queued_params.base_currency_id != 0, 'BaseIdZero');
            assert(queued_params.quote_currency_id != 0, 'QuoteIdZero');

            // Update state.
            self.queued_market_params.write(market_id, Default::default());
            self.queued_at.write(market_id, 0);
            self.market_params.write(market_id, queued_params);

            // Emit event.
            self
                .emit(
                    Event::SetMarketParams(
                        SetMarketParams {
                            market_id,
                            spread: params.spread,
                            range: params.range,
                            base_currency_id: params.base_currency_id,
                            quote_currency_id: params.quote_currency_id,
                            min_sources: params.min_sources,
                            max_age: params.max_age,
                        }
                    )
                );
        }

        // Set delay (in seconds) for changing market parameters
        // Only callable by owner.
        //
        // # Params
        // * `delay` - delay in blocks
        fn set_delay(ref self: ContractState, delay: u64) {
            // Run checks.
            self.solver.assert_owner();
            let old_delay = self.delay.read();
            assert(delay != old_delay, 'DelayUnchanged');

            // Update state.
            self.delay.write(delay);

            // Emit event.
            self.emit(Event::SetDelay(SetDelay { delay }));
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

        // Change the trend setter.
        //
        // # Arguments
        // * `trend_setter` - contract address of trend setter admin
        fn change_trend_setter(ref self: ContractState, trend_setter: ContractAddress) {
            self.solver.assert_owner();
            let old_trend_setter = self.trend_setter.read();
            assert(trend_setter != old_trend_setter, 'TrendSetterUnchanged');
            self.trend_setter.write(trend_setter);
            self.emit(Event::ChangeTrendSetter(ChangeTrendSetter { trend_setter }));
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
            let market_info: MarketInfo = self.solver.market_info.read(market_id);
            let state: MarketState = self.solver.market_state.read(market_id);
            let params = self.market_params.read(market_id);
            let trend_state: TrendState = self.trend_state.read(market_id);

            // Fetch oracle price and cached oracle price.
            let (oracle_price, is_valid) = self.get_oracle_price(market_id);
            assert(is_valid, 'InvalidOraclePrice');
            let cached_price = if trend_state.cached_price == 0 {
                0
            } else {
                self
                    .scale_oracle_price(
                        @market_info, trend_state.cached_price, trend_state.cached_decimals
                    )
            };

            // Calculate and return positions.
            let mut bid: PositionInfo = Default::default();
            let mut ask: PositionInfo = Default::default();
            let (bid_lower, bid_upper, ask_lower, ask_upper) =
                spread_math::get_virtual_position_range(
                trend_state.trend, params.spread, params.range, cached_price, oracle_price
            );
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

    #[abi(per_item)]
    #[generate_trait]
    pub impl InternalImpl of InternalTrait {
        // Internal function to scale the oracle price retrieved from Pragma by token decimals.
        // We return the scaled price as base 1e28.
        //
        // # Arguments
        // * `market_info` - market info
        // * `oracle_price` - oracle price
        // * `decimals` - oracle price decimals
        fn scale_oracle_price(
            self: @ContractState, market_info: @MarketInfo, oracle_price: u128, decimals: u32
        ) -> u256 {
            // Get token decimals.
            let base_token = ERC20ABIDispatcher { contract_address: *market_info.base_token };
            let quote_token = ERC20ABIDispatcher { contract_address: *market_info.quote_token };
            let base_decimals: u256 = base_token.decimals().into();
            let quote_decimals: u256 = quote_token.decimals().into();
            assert(28 + quote_decimals >= decimals.into() + base_decimals, 'DecimalsUF');
            let decimals: u256 = 28 + quote_decimals - decimals.into() - base_decimals;

            // Scale and return oracle price.
            let scaling_factor = math::pow(10, decimals);
            oracle_price.into() * scaling_factor
        }
    }
}
