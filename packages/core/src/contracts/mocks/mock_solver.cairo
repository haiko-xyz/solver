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

    // Get fee rate for solver market.
    //
    // # Returns
    // * `fee_rate` - fee rate
    fn fee_rate(self: @TContractState, market_id: felt252) -> u16;

    // Set fee rate for solver market.
    //
    // # Params
    // * `market_id` - market id
    // * `fee_rate` - fee rate
    fn set_fee_rate(ref self: TContractState, market_id: felt252, fee_rate: u16);
}

#[starknet::contract]
pub mod MockSolver {
    // Core lib imports.
    use starknet::ContractAddress;
    use starknet::contract_address::contract_address_const;
    use starknet::get_block_timestamp;
    use starknet::class_hash::ClassHash;
    use core::cmp::min;

    // Local imports.
    use super::IMockSolver;
    use haiko_solver_core::contracts::solver::SolverComponent;
    use haiko_solver_core::libraries::math::fast_sqrt;
    use haiko_solver_core::interfaces::ISolver::ISolverHooks;
    use haiko_solver_core::types::{PositionInfo, MarketState, MarketInfo, SwapParams};

    // Haiko imports.
    use haiko_lib::math::{math, fee_math};
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

    ////////////////////////////////
    // STORAGE
    ///////////////////////////////

    #[storage]
    struct Storage {
        // Solver
        #[substorage(v0)]
        solver: SolverComponent::Storage,
        // Price (base 1e28, indexed by market id)
        price: LegacyMap::<felt252, u256>,
        // Fee rate
        fee_rate: LegacyMap::<felt252, u16>,
    }

    ////////////////////////////////
    // EVENTS
    ///////////////////////////////

    #[event]
    #[derive(Drop, starknet::Event)]
    pub(crate) enum Event {
        #[flat]
        SolverEvent: SolverComponent::Event,
    }

    ////////////////////////////////
    // CONSTRUCTOR
    ////////////////////////////////

    #[constructor]
    fn constructor(ref self: ContractState, owner: ContractAddress, vault_token_class: ClassHash,) {
        self.solver._initializer("Mock", "MOCK", owner, vault_token_class);
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
        // * `amount_in` - amount in including fees
        // * `amount_out` - amount out
        // * `fees` - fees
        fn quote(
            self: @ContractState, market_id: felt252, swap_params: SwapParams,
        ) -> (u256, u256, u256) {
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
            let fee_rate = self.fee_rate.read(market_id);
            let (amount_in, amount_out) = if swap_params.exact_input {
                let fees = fee_math::calc_fee(swap_params.amount, fee_rate);
                let amount_in_excl_fees = swap_params.amount - fees;
                let amount_out = if swap_params.is_buy {
                    math::mul_div(amount_in_excl_fees, ONE, price, false)
                } else {
                    math::mul_div(amount_in_excl_fees, price, ONE, false)
                };
                (swap_params.amount, amount_out)
            } else {
                let amount_in_excl_fees = if swap_params.is_buy {
                    math::mul_div(swap_params.amount, price, ONE, false)
                } else {
                    math::mul_div(swap_params.amount, ONE, price, false)
                };
                let amount_in = fee_math::net_to_gross(amount_in_excl_fees, fee_rate);
                (amount_in, swap_params.amount)
            };

            // Cap amount out by reserves.
            let amount_out_capped = if swap_params.is_buy {
                min(amount_out, state.base_reserves)
            } else {
                min(amount_out, state.quote_reserves)
            };
            let amount_in_capped = if amount_out_capped < amount_out {
                math::mul_div(amount_in, amount_out_capped, amount_out, true)
            } else {
                amount_in
            };
            let fees_capped = fee_math::calc_fee(amount_in_capped, fee_rate);

            (amount_in_capped, amount_out_capped, fees_capped)
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
        fn after_swap(ref self: ContractState, market_id: felt252, swap_params: SwapParams) {
            assert(self.solver.unlocked.read(), 'NotSolver');
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

        // Get fee rate
        //
        // # Arguments
        // * `market_id` - market id
        //
        // # Returns
        // * `fee_rate` - fee rate
        fn fee_rate(self: @ContractState, market_id: felt252) -> u16 {
            self.fee_rate.read(market_id)
        }

        // Set fee rate
        //
        // # Arguments
        // * `market_id` - market id
        // * `fee_rate` - fee rate
        fn set_fee_rate(ref self: ContractState, market_id: felt252, fee_rate: u16) {
            self.fee_rate.write(market_id, fee_rate);
        }
    }
}
