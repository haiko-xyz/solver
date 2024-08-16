#[starknet::contract]
pub mod ReplicatingSolver {
    // Core lib imports.
    use starknet::ContractAddress;
    use starknet::contract_address::contract_address_const;
    use starknet::get_block_timestamp;
    use starknet::class_hash::ClassHash;

    // Local imports.
    use haiko_solver_core::contracts::solver::SolverComponent;
    use haiko_solver_core::contracts::governor::GovernorComponent;
    use haiko_solver_core::interfaces::ISolver::ISolverHooks;
    use haiko_solver_core::interfaces::IGovernor::IGovernorHooks;
    use haiko_solver_replicating::libraries::{
        swap_lib, spread_math, store_packing::MarketParamsStorePacking
    };
    use haiko_solver_replicating::interfaces::{
        IReplicatingSolver::IReplicatingSolver,
        pragma::{
            AggregationMode, DataType, SimpleDataType, PragmaPricesResponse, IOracleABIDispatcher,
            IOracleABIDispatcherTrait
        },
    };
    use haiko_solver_core::types::{PositionInfo, MarketState, MarketInfo, SwapParams, Hooks};
    use haiko_solver_replicating::types::MarketParams;

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
    
    component!(path: GovernorComponent, storage: governor, event: GovernorEvent);
    #[abi(embed_v0)]
    impl GovernorImpl = GovernorComponent::GovernorImpl<ContractState>;
    impl GovernorInternalImpl = GovernorComponent::InternalImpl<ContractState>;

    ////////////////////////////////
    // STORAGE
    ///////////////////////////////

    #[storage]
    struct Storage {
        // Solver
        #[substorage(v0)]
        solver: SolverComponent::Storage,
        // Governance
        #[substorage(v0)]
        governor: GovernorComponent::Storage,
        // oracle for price and volatility feeds
        oracle: IOracleABIDispatcher,
        // Indexed by market id
        market_params: LegacyMap::<felt252, MarketParams>,
        // Indexed by market id
        queued_market_params: LegacyMap::<felt252, MarketParams>,
        // indexed by proposal id
        proposed_market_params: LegacyMap::<felt252, MarketParams>,
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
        ProposeMarketParams: ProposeMarketParams,
        QueueMarketParams: QueueMarketParams,
        SetMarketParams: SetMarketParams,
        SetDelay: SetDelay,
        ChangeOracle: ChangeOracle,
        #[flat]
        SolverEvent: SolverComponent::Event,
        #[flat]
        GovernorEvent: GovernorComponent::Event,
    }

    #[derive(Drop, starknet::Event)]
    pub(crate) struct ProposeMarketParams {
        #[key]
        pub market_id: felt252,
        #[key]
        pub proposal_id: felt252,
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
    pub(crate) struct QueueMarketParams {
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
    pub(crate) struct SetDelay {
        pub delay: u64,
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
        let hooks = Hooks { after_swap: false, after_withdraw: true, };
        self.solver._initializer("Replicating", "REPL", owner, vault_token_class, hooks);
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

            // Get virtual position.
            let (bid, ask) = self.get_virtual_positions(market_id);
            let position = if swap_params.is_buy {
                ask
            } else {
                bid
            };

            // Calculate swap amount. 
            let (amount_in, amount_out) = swap_lib::get_swap_amounts(swap_params, position);

            // Fetch oracle price.
            let (oracle_price, is_valid) = self.get_oracle_price(market_id);
            assert(is_valid, 'InvalidOraclePrice');

            // Check deposited amounts does not violate max skew, or if it does, that
            // the deposit reduces the extent of skew.
            let (base_reserves, quote_reserves) = if swap_params.is_buy {
                (state.base_reserves - amount_out, state.quote_reserves + amount_in)
            } else {
                (state.base_reserves + amount_in, state.quote_reserves - amount_out)
            };
            let params = self.market_params.read(market_id);
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
        fn after_swap(
            ref self: ContractState,
            market_id: felt252,
            caller: ContractAddress,
            swap_params: SwapParams
        ) {
            assert(self.solver.unlocked.read(), 'NotSolver');
        }

        // Callback function to execute any state updates after a withdraw is completed.
        // This fn should only be callable by the solver contract.
        //
        // # Params
        // * `market_id` - market id
        // * `caller` - withdrawing depositor
        // * `shares` - shares withdrawn
        // * `base_amount` - base amount withdrawn
        // * `quote_amount` - quote amount withdrawn
        fn after_withdraw(
            ref self: ContractState,
            market_id: felt252,
            caller: ContractAddress,
            shares: u256,
            base_amount: u256,
            quote_amount: u256
        ) {
            assert(self.solver.unlocked.read(), 'NotSolver');

            // Call governance hooks.
            self.governor.after_withdraw_governor(market_id, caller, shares);
        }
    }

    #[abi(embed_v0)]
    impl GovernorHooks of IGovernorHooks<ContractState> {
        // Hook called to set a passed market param.
        // Should be implemented by solver to set the passed market params in state.
        // Should emit any relevant events.
        //
        // # Params
        // * `market_id` - market id
        // * `proposal_id` - proposal id
        fn set_passed_market_params(
            ref self: ContractState, market_id: felt252, proposal_id: felt252
        ) {
            // Should only be callable internally.
            assert(self.solver.unlocked.read(), 'NotSolver');

            // Fetch proposed params.
            let params = self.proposed_market_params.read(proposal_id);

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
    }

    #[abi(embed_v0)]
    impl ReplicatingSolver of IReplicatingSolver<ContractState> {
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

        // Confirm and set queued market parameters.
        // Must have been queued for at least the set delay.
        // Only callable by market owner.
        //
        // # Params
        // * `market_id` - market id
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
                            min_spread: queued_params.min_spread,
                            range: queued_params.range,
                            max_delta: queued_params.max_delta,
                            max_skew: queued_params.max_skew,
                            base_currency_id: queued_params.base_currency_id,
                            quote_currency_id: queued_params.quote_currency_id,
                            min_sources: queued_params.min_sources,
                            max_age: queued_params.max_age,
                        }
                    )
                );
        }

        // Propose market params for a solver market with governance enabled.
        //
        // # Params
        // * `market_id` - market id
        // * `params` - proposed market params
        fn propose_market_params(
            ref self: ContractState, market_id: felt252, params: MarketParams
        ) -> felt252 {
            // Run checks.
            let old_params = self.market_params.read(market_id);
            assert(old_params != params, 'ParamsUnchanged');
            assert(params.range != 0, 'RangeZero');
            assert(params.min_sources != 0, 'MinSourcesZero');
            assert(params.max_age != 0, 'MaxAgeZero');
            assert(params.base_currency_id != 0, 'BaseIdZero');
            assert(params.quote_currency_id != 0, 'QuoteIdZero');

            // Call governor lower level function.
            let proposal_id = self
                .governor
                ._propose_market_params(market_id, );

            // Store proposed params.
            self.proposed_market_params.write(proposal_id, params);

            // Emit event.
            self.emit(
                Event::ProposeMarketParams(
                    ProposeMarketParams {
                        market_id,
                        proposal_id,
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

            // Return proposal id.
            proposal_id
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
}
