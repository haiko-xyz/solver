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
}

#[starknet::contract]
pub mod MockSolver {
    // Core lib imports.
    use starknet::ContractAddress;
    use starknet::contract_address::contract_address_const;
    use starknet::get_block_timestamp;
    use starknet::class_hash::ClassHash;

    // Local imports.
    use super::IMockSolver;
    use haiko_solver_core::contracts::solver::SolverComponent;
    use haiko_solver_core::interfaces::ISolver::ISolverQuoter;
    use haiko_solver_core::types::{PositionInfo, MarketState, MarketInfo, SwapParams};

    // Haiko imports.
    use haiko_lib::math::math;
    use haiko_lib::constants::ONE;

    // External imports.
    use openzeppelin::token::erc20::interface::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};
    use alexandria_math::fast_root::fast_sqrt;

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

            // Calculate and return swap amounts.
            let price = self.price(market_id);
            let amount_calc = if swap_params.is_buy == swap_params.exact_input {
                math::mul_div(swap_params.amount, ONE, price, false)
            } else {
                math::mul_div(swap_params.amount, price, ONE, false)
            };
            if swap_params.exact_input {
                (swap_params.amount, amount_calc)
            } else {
                (amount_calc, swap_params.amount)
            }
        }

        // Get the initial token supply to mint when first depositing to a market.
        //
        // # Arguments
        // * `market_id` - market id
        //
        // # Returns
        // * `initial_supply` - initial supply
        fn initial_supply(self: @ContractState, market_id: felt252) -> u256 {
            // We use the Uniswap formula to calculate initial liquidity
            // L = sqrt(xy)
            let state: MarketState = self.solver.market_state.read(market_id);
            let sqrt_base_reserves = fast_sqrt(state.base_reserves.try_into().unwrap(), 10);
            let sqrt_quote_reserves = fast_sqrt(state.quote_reserves.try_into().unwrap(), 10);
            (sqrt_base_reserves * sqrt_quote_reserves).into()
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
    }
}
