#[derive(Drop, Copy, Serde, PartialEq, Default, starknet::Store)]
pub struct MockMarketParams {
    pub foo: felt252,
    pub bar: felt252,
}

#[starknet::interface]
pub trait IMockSolver<TContractState> {
    // Get price for solver market.
    // 
    // # Returns
    // * `price` - oracle price
    fn price(self: @TContractState, market_id: felt252) -> u256;

    // Set price for solver market.
    //
    // # Params
    // * `market_id` - market id
    // * `params` - market params
    fn set_price(ref self: TContractState, market_id: felt252, price: u256);

    // Fetch market params for a solver market.
    //
    // # Params
    // * `market_id` - market id
    //
    // # Returns
    // * `params` - market params
    fn market_params(self: @TContractState, market_id: felt252) -> MockMarketParams;

    // Propose market params for a solver market with governance enabled.
    //
    // # Params
    // * `market_id` - market id
    // * `params` - proposed market params
    fn propose_market_params(
        ref self: TContractState, market_id: felt252, params: MockMarketParams
    ) -> felt252;

    // Set market params for a solver market.
    //
    // # Params
    // * `market_id` - market id
    // * `params` - proposed market params
    fn set_market_params(ref self: TContractState, market_id: felt252, params: MockMarketParams);
}

#[starknet::contract]
pub mod MockSolver {
    // Core lib imports.
    use starknet::ContractAddress;
    use starknet::contract_address::contract_address_const;
    use starknet::get_block_timestamp;
    use starknet::class_hash::ClassHash;

    // Local imports.
    use super::{IMockSolver, MockMarketParams};
    use haiko_solver_core::contracts::solver::SolverComponent;
    use haiko_solver_core::contracts::governor::GovernorComponent;
    use haiko_solver_core::interfaces::ISolver::ISolverHooks;
    use haiko_solver_core::interfaces::IGovernor::IGovernorHooks;
    use haiko_solver_core::libraries::math::fast_sqrt;
    use haiko_solver_core::types::solver::{
        PositionInfo, MarketState, MarketInfo, SwapParams, Hooks
    };

    // Haiko imports.
    use haiko_lib::math::math;
    use haiko_lib::constants::ONE;

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
        // Price (base 1e28, indexed by market id)
        price: LegacyMap::<felt252, u256>,
        // Market params, indexed by market id
        market_params: LegacyMap::<felt252, MockMarketParams>,
        // Proposed market params, indexed by proposal id
        proposed_market_params: LegacyMap::<felt252, MockMarketParams>,
    }

    ////////////////////////////////
    // EVENTS
    ///////////////////////////////

    #[event]
    #[derive(Drop, starknet::Event)]
    pub(crate) enum Event {
        ProposeMarketParams: ProposeMarketParams,
        SetMarketParams: SetMarketParams,
        #[flat]
        SolverEvent: SolverComponent::Event,
        #[flat]
        GovernorEvent: GovernorComponent::Event,
    }

    #[derive(Drop, starknet::Event)]
    pub(crate) struct ProposeMarketParams {
        #[key]
        pub market_id: felt252,
        pub proposal_id: felt252,
        pub foo: felt252,
        pub bar: felt252,
    }

    #[derive(Drop, starknet::Event)]
    pub(crate) struct SetMarketParams {
        #[key]
        pub market_id: felt252,
        pub foo: felt252,
        pub bar: felt252,
    }

    ////////////////////////////////
    // CONSTRUCTOR
    ////////////////////////////////

    #[constructor]
    fn constructor(ref self: ContractState, owner: ContractAddress, vault_token_class: ClassHash,) {
        let hooks = Hooks { after_swap: false, after_withdraw: true };
        self.solver._initializer("Mock", "MOCK", owner, vault_token_class, hooks);
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

            // Scale price by decimals.
            let unscaled_price = self.price(market_id);
            let base_token = ERC20ABIDispatcher { contract_address: market_info.base_token };
            let quote_token = ERC20ABIDispatcher { contract_address: market_info.quote_token };
            let base_decimals: u256 = base_token.decimals().into();
            let quote_decimals: u256 = quote_token.decimals().into();
            let base_scale = math::pow(10, base_decimals);
            let quote_scale = math::pow(10, quote_decimals);
            let price = math::mul_div(unscaled_price, quote_scale, base_scale, false);

            // Calculate and return swap amounts.
            let amount_calc = if swap_params.is_buy == swap_params.exact_input {
                math::mul_div(swap_params.amount, ONE, price, false)
            } else {
                math::mul_div(swap_params.amount, price, ONE, false)
            };
            let (amount_in, amount_out) = if swap_params.exact_input {
                (swap_params.amount, amount_calc)
            } else {
                (amount_calc, swap_params.amount)
            };

            // Cap at available amount.
            let (max_amount_in, max_amount_out) = if swap_params.is_buy {
                let amount_in = math::mul_div(state.base_reserves, price, ONE, false);
                (amount_in, state.base_reserves)
            } else {
                let amount_out = math::mul_div(state.quote_reserves, ONE, price, false);
                (state.quote_reserves, amount_out)
            };

            // Return capped amounts.
            if amount_in > max_amount_in || amount_out > max_amount_out {
                (max_amount_in, max_amount_out)
            } else {
                (amount_in, amount_out)
            }
        }

        // Initial token supply to mint when first depositing to a market.
        //
        // # Arguments
        // * `market_id` - market id
        //
        // # Returns
        // * `initial_supply` - initial supply
        fn initial_supply(self: @ContractState, market_id: felt252) -> u256 {
            let state: MarketState = self.solver.market_state.read(market_id);
            // We use the Uniswap formula to calculate initial liquidity: L = sqrt(xy)
            if state.base_reserves != 0 && state.quote_reserves != 0 {
                let sqrt_base_reserves = fast_sqrt(state.base_reserves.try_into().unwrap(), 10);
                let sqrt_quote_reserves = fast_sqrt(state.quote_reserves.try_into().unwrap(), 10);
                (sqrt_base_reserves * sqrt_quote_reserves).into()
            } // If one of the reserves is 0, we return the other reserve.
            else if state.base_reserves != 0 {
                state.base_reserves
            } else if state.quote_reserves != 0 {
                state.quote_reserves
            } // If both reserves are 0, we return 0. 
            else {
                0
            }
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
                        SetMarketParams { market_id, foo: params.foo, bar: params.bar, }
                    )
                );
        }
    }

    #[abi(embed_v0)]
    impl MockSolver of IMockSolver<ContractState> {
        // Get market price
        //
        // # Arguments
        // * `market_id` - market id
        //
        // # Returns
        // * `price` - oracle price
        fn price(self: @ContractState, market_id: felt252) -> u256 {
            self.price.read(market_id)
        }

        // Set market price
        //
        // # Arguments
        // * `market_id` - market id
        // * `price` - oracle price
        fn set_price(ref self: ContractState, market_id: felt252, price: u256) {
            self.price.write(market_id, price);
        }

        // Fetch market params for a solver market.
        //
        // # Params
        // * `market_id` - market id
        //
        // # Returns
        // * `params` - market params
        fn market_params(self: @ContractState, market_id: felt252) -> MockMarketParams {
            self.market_params.read(market_id)
        }

        // Propose market params for a solver market with governance enabled.
        //
        // # Params
        // * `market_id` - market id
        // * `params` - proposed market params
        fn propose_market_params(
            ref self: ContractState, market_id: felt252, params: MockMarketParams
        ) -> felt252 {
            // Check params.
            let old_params = self.market_params.read(market_id);
            assert(params != old_params, 'ParamsUnchanged');

            // Call governor lower level function.
            let proposal_id = self.governor._propose_market_params(market_id,);

            // Store proposed params.
            self.proposed_market_params.write(proposal_id, params);

            // Emit event.
            self
                .emit(
                    Event::ProposeMarketParams(
                        ProposeMarketParams {
                            market_id, proposal_id, foo: params.foo, bar: params.bar,
                        }
                    )
                );

            // Return proposal id.
            proposal_id
        }

        // Set market params for a solver market.
        //
        // # Params
        // * `market_id` - market id
        // * `params` - proposed market params
        fn set_market_params(
            ref self: ContractState, market_id: felt252, params: MockMarketParams
        ) {
            self.market_params.write(market_id, params);
        }
    }
}
