#[starknet::contract]
pub mod ReplicatingSolver {
    // Core lib imports.
    use core::integer::BoundedInt;
    use core::cmp::{min, max};
    use starknet::ContractAddress;
    use starknet::contract_address::contract_address_const;
    use starknet::{get_caller_address, get_contract_address, get_block_timestamp};
    use starknet::class_hash::ClassHash;
    use starknet::syscalls::{replace_class_syscall, deploy_syscall};

    // Local imports.
    use haiko_solver_replicating::libraries::{
        swap_lib, spread_math, id, erc20_versioned_call,
        store_packing::{MarketParamsStorePacking, MarketStateStorePacking}
    };
    use haiko_solver_replicating::interfaces::ISolver::ISolver;
    use haiko_solver_replicating::interfaces::IReplicatingSolver::IReplicatingSolver;
    use haiko_solver_replicating::interfaces::IVaultToken::{
        IVaultTokenDispatcher, IVaultTokenDispatcherTrait
    };
    use haiko_solver_replicating::interfaces::pragma::{
        AggregationMode, DataType, SimpleDataType, PragmaPricesResponse, IOracleABIDispatcher,
        IOracleABIDispatcherTrait
    };
    use haiko_solver_replicating::types::core::SwapParams;
    use haiko_solver_replicating::types::replicating::{
        MarketInfo, MarketParams, MarketState, PositionInfo
    };

    // Haiko imports.
    use haiko_lib::{math::{math, fee_math}, constants::{ONE, LOG2_1_00001, MAX_FEE_RATE}};

    // External imports.
    use openzeppelin::token::erc20::interface::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};

    ////////////////////////////////
    // STORAGE
    ///////////////////////////////

    #[storage]
    struct Storage {
        // OWNABLE
        // contract owner
        owner: ContractAddress,
        // queued contract owner (for ownership transfers)
        queued_owner: ContractAddress,
        // IMMUTABLES
        // solver name
        name: felt252,
        // solver symbol
        symbol: felt252,
        // MUTABLE
        // oracle for price and volatility feeds
        oracle: IOracleABIDispatcher,
        // vault token class hash
        vault_token_class: ClassHash,
        // SOLVER
        // Indexed by market id
        market_info: LegacyMap::<felt252, MarketInfo>,
        // Indexed by market id
        market_params: LegacyMap::<felt252, MarketParams>,
        // Indexed by market id
        market_state: LegacyMap::<felt252, MarketState>,
        // Indexed by market_id
        withdraw_fee_rate: LegacyMap::<felt252, u16>,
        // Indexed by asset
        withdraw_fees: LegacyMap::<ContractAddress, u256>,
    }

    ////////////////////////////////
    // EVENTS
    ///////////////////////////////

    #[event]
    #[derive(Drop, starknet::Event)]
    pub(crate) enum Event {
        CreateMarket: CreateMarket,
        Deposit: Deposit,
        Withdraw: Withdraw,
        Swap: Swap,
        SetMarketParams: SetMarketParams,
        CollectWithdrawFee: CollectWithdrawFee,
        SetWithdrawFee: SetWithdrawFee,
        WithdrawFeeEarned: WithdrawFeeEarned,
        ChangeOwner: ChangeOwner,
        ChangeOracle: ChangeOracle,
        ChangeVaultTokenClass: ChangeVaultTokenClass,
        Pause: Pause,
        Unpause: Unpause,
        Referral: Referral,
        Upgraded: Upgraded,
    }

    #[derive(Drop, starknet::Event)]
    pub(crate) struct CreateMarket {
        #[key]
        pub market_id: felt252,
        pub base_token: ContractAddress,
        pub quote_token: ContractAddress,
        pub owner: ContractAddress,
        pub is_public: bool,
    }

    #[derive(Drop, starknet::Event)]
    pub(crate) struct Swap {
        #[key]
        pub market_id: felt252,
        #[key]
        pub caller: ContractAddress,
        pub amount_in: u256,
        pub amount_out: u256,
    }

    #[derive(Drop, starknet::Event)]
    pub(crate) struct Deposit {
        #[key]
        pub caller: ContractAddress,
        #[key]
        pub market_id: felt252,
        pub base_amount: u256,
        pub quote_amount: u256,
        pub shares: u256,
    }

    #[derive(Drop, starknet::Event)]
    pub(crate) struct Withdraw {
        #[key]
        pub caller: ContractAddress,
        #[key]
        pub market_id: felt252,
        pub base_amount: u256,
        pub quote_amount: u256,
        pub shares: u256,
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
    pub(crate) struct SetWithdrawFee {
        #[key]
        pub market_id: felt252,
        pub fee_rate: u16,
    }

    #[derive(Drop, starknet::Event)]
    pub(crate) struct WithdrawFeeEarned {
        #[key]
        pub market_id: felt252,
        #[key]
        pub token: ContractAddress,
        pub amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    pub(crate) struct CollectWithdrawFee {
        #[key]
        pub receiver: ContractAddress,
        #[key]
        pub token: ContractAddress,
        pub amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    pub(crate) struct ChangeOracle {
        pub oracle: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    pub(crate) struct ChangeVaultTokenClass {
        pub class_hash: ClassHash,
    }

    #[derive(Drop, starknet::Event)]
    pub(crate) struct ChangeOwner {
        pub old: ContractAddress,
        pub new: ContractAddress
    }

    #[derive(Drop, starknet::Event)]
    pub(crate) struct Pause {
        #[key]
        pub market_id: felt252,
    }

    #[derive(Drop, starknet::Event)]
    pub(crate) struct Unpause {
        #[key]
        pub market_id: felt252,
    }

    #[derive(Drop, starknet::Event)]
    pub(crate) struct Referral {
        #[key]
        pub caller: ContractAddress,
        pub referrer: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    pub(crate) struct Upgraded {
        pub class_hash: ClassHash,
    }

    ////////////////////////////////
    // CONSTRUCTOR
    ////////////////////////////////

    #[constructor]
    fn constructor(
        ref self: ContractState,
        owner: ContractAddress,
        name: felt252,
        symbol: felt252,
        oracle: ContractAddress,
        vault_token_class: ClassHash,
    ) {
        self.owner.write(owner);
        self.name.write(name);
        self.symbol.write(symbol);
        let oracle_dispatcher = IOracleABIDispatcher { contract_address: oracle };
        self.oracle.write(oracle_dispatcher);
        self.vault_token_class.write(vault_token_class);
    }

    ////////////////////////////////
    // FUNCTIONS
    ////////////////////////////////

    #[abi(per_item)]
    #[generate_trait]
    impl ModifierImpl of ModifierTrait {
        fn assert_owner(self: @ContractState) {
            assert(self.owner.read() == get_caller_address(), 'OnlyOwner');
        }

        fn assert_market_owner(self: @ContractState, market_id: felt252) {
            let owner = self.market_info.read(market_id).owner;
            assert(owner == get_caller_address(), 'OnlyMarketOwner');
        }
    }

    #[abi(embed_v0)]
    impl Solver of ISolver<ContractState> {
        // Obtain quote for swap through a market.
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
            let state = self.market_state.read(market_id);
            let market_info = self.market_info.read(market_id);
            assert(market_info.base_token != contract_address_const::<0x0>(), 'NotInit');
            assert(!state.is_paused, 'Paused');

            // Fetch oracle price.
            let (oracle_price, is_valid) = self.get_oracle_price(market_id);
            assert(is_valid, 'InvalidOraclePrice');

            // Calculate swap amounts.
            let params = self.market_params.read(market_id);
            let delta = spread_math::get_delta(
                params.max_delta, state.base_reserves, state.quote_reserves, oracle_price
            );
            let reserves = if swap_params.is_buy {
                state.quote_reserves
            } else {
                state.base_reserves
            };
            let position = spread_math::get_virtual_position(
                !swap_params.is_buy, params.min_spread, delta, params.range, oracle_price, reserves
            );
            let (amount_in, amount_out) = swap_lib::get_swap_amounts(swap_params, position);

            // Throw if amounts bring portfolio skew above maximum.
            let (base_reserves, quote_reserves) = if swap_params.is_buy {
                (state.base_reserves + amount_out, state.quote_reserves - amount_in)
            } else {
                (state.base_reserves - amount_in, state.quote_reserves + amount_out)
            };
            let (skew, _) = spread_math::get_skew(base_reserves, quote_reserves, oracle_price);
            assert(skew <= params.max_skew.into(), 'MaxSkew');

            // Return amounts.
            (amount_in, amount_out)
        }

        // Execute swap through a market.
        // 
        // # Arguments
        // * `market_id` - market id
        // * `swap_params` - swap parameters
        //
        // # Returns
        // * `amount_in` - amount in
        // * `amount_out` - amount out
        fn swap(
            ref self: ContractState, market_id: felt252, swap_params: SwapParams,
        ) -> (u256, u256) {
            // Get amounts.
            let (amount_in, amount_out) = self.quote(market_id, swap_params);
            assert(amount_in != 0 && amount_out != 0, 'AmountsZero');

            // Check against threshold amount.
            if swap_params.threshold_amount.is_some() {
                let threshold_amount_val = swap_params.threshold_amount.unwrap();
                if swap_params.exact_input && (amount_out < threshold_amount_val) {
                    panic(array!['ThresholdAmount', amount_out.low.into(), amount_out.high.into()]);
                }
                if !swap_params.exact_input && (amount_in > threshold_amount_val) {
                    panic(array!['ThresholdAmount', amount_in.low.into(), amount_in.high.into()]);
                }
            }

            // Transfer tokens.
            let market_info = self.market_info.read(market_id);
            let base_token = ERC20ABIDispatcher { contract_address: market_info.base_token };
            let quote_token = ERC20ABIDispatcher { contract_address: market_info.quote_token };
            let caller = get_caller_address();
            let contract = get_contract_address();
            if swap_params.is_buy {
                quote_token.transferFrom(caller, contract, amount_in);
                base_token.transfer(caller, amount_out);
            } else {
                base_token.transferFrom(caller, contract, amount_in);
                quote_token.transfer(caller, amount_out);
            }

            // Update reserves.
            let mut state = self.market_state.read(market_id);
            state.base_reserves += amount_in;
            state.quote_reserves -= amount_out;
            self.market_state.write(market_id, state);

            // Emit events.
            self.emit(Event::Swap(Swap { market_id, caller, amount_in, amount_out }));

            (amount_in, amount_out)
        }
    }

    #[abi(embed_v0)]
    impl ReplicatingSolver of IReplicatingSolver<ContractState> {
        // Market id
        fn market_id(self: @ContractState, market_info: MarketInfo) -> felt252 {
            id::market_id(market_info)
        }

        // Immutable market information
        fn market_info(self: @ContractState, market_id: felt252) -> MarketInfo {
            self.market_info.read(market_id)
        }

        // Configurable market parameters
        fn market_params(self: @ContractState, market_id: felt252) -> MarketParams {
            self.market_params.read(market_id)
        }

        // Market state
        fn market_state(self: @ContractState, market_id: felt252) -> MarketState {
            self.market_state.read(market_id)
        }

        // Pragma oracle contract address
        fn oracle(self: @ContractState) -> ContractAddress {
            self.oracle.read().contract_address
        }

        // Vault token class hash
        fn vault_token_class(self: @ContractState) -> ClassHash {
            self.vault_token_class.read()
        }

        // Contract owner
        fn owner(self: @ContractState) -> ContractAddress {
            self.owner.read()
        }

        // Queued contract owner, used for ownership transfers
        fn queued_owner(self: @ContractState) -> ContractAddress {
            self.queued_owner.read()
        }

        // Withdraw fee rate for a given market
        fn withdraw_fee_rate(self: @ContractState, market_id: felt252) -> u16 {
            self.withdraw_fee_rate.read(market_id)
        }

        // Accumulated withdraw fee balance for a given asset
        fn withdraw_fees(self: @ContractState, token: ContractAddress) -> u256 {
            self.withdraw_fees.read(token)
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
            let market_info = self.market_info.read(market_id);
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
                && (params.max_age == 0 || output.last_updated_timestamp + params.max_age >= now);

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

        // Get token balances held in solver market.
        // 
        // # Arguments
        // * `market_id` - market id
        //
        // # Returns
        // * `base_amount` - total base tokens owned
        // * `quote_amount` - total quote tokens owned
        fn get_balances(self: @ContractState, market_id: felt252) -> (u256, u256) {
            let state = self.market_state.read(market_id);
            (state.base_reserves, state.quote_reserves)
        }

        // Get token amounts held in reserve for a list of markets.
        // 
        // # Arguments
        // * `market_ids` - list of market ids
        //
        // # Returns
        // * `balances` - list of base and quote token amounts
        fn get_balances_array(
            self: @ContractState, market_ids: Span<felt252>
        ) -> Span<(u256, u256)> {
            let mut balances: Array<(u256, u256)> = array![];
            let mut i = 0;
            loop {
                if i == market_ids.len() {
                    break;
                }
                let market_id = *market_ids.at(i);
                let (base_amount, quote_amount) = self.get_balances(market_id);
                balances.append((base_amount, quote_amount));
                i += 1;
            };
            // Return balances.
            balances.span()
        }

        // Get token amounts and shares held in solver market for a list of users.
        // 
        // # Arguments
        // * `users` - list of user address
        // * `market_ids` - list of market ids
        //
        // # Returns
        // * `base_amount` - base tokens owned by user
        // * `quote_amount` - quote tokens owned by user
        // * `user_shares` - user shares
        // * `total_shares` - total shares in market
        fn get_user_balances_array(
            self: @ContractState, users: Span<ContractAddress>, market_ids: Span<felt252>
        ) -> Span<(u256, u256, u256, u256)> {
            // Check users and market ids of equal length.
            assert(users.len() == market_ids.len(), 'LengthMismatch');

            let mut balances: Array<(u256, u256, u256, u256)> = array![];
            let mut i = 0;
            loop {
                if i == users.len() {
                    break;
                }
                let market_id = *market_ids.at(i);
                let state = self.market_state.read(market_id);
                // Handle non-existent vault token.
                if state.vault_token == contract_address_const::<0x0>() {
                    balances.append((0, 0, 0, 0));
                    i += 1;
                    continue;
                }
                // Handle divison by 0 case.
                let vault_token = ERC20ABIDispatcher { contract_address: state.vault_token };
                let total_shares = vault_token.totalSupply();
                if total_shares == 0 {
                    balances.append((0, 0, 0, 0));
                    i += 1;
                    continue;
                }
                // Calculate balances and shares
                let user_shares = vault_token.balanceOf(*users.at(i));
                let (base_balance, quote_balance) = self.get_balances(market_id);
                let base_amount = math::mul_div(base_balance, user_shares, total_shares, false);
                let quote_amount = math::mul_div(quote_balance, user_shares, total_shares, false);
                balances.append((base_amount, quote_amount, user_shares, total_shares));
                i += 1;
            };
            balances.span()
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
            let state = self.market_state.read(market_id);
            let params = self.market_params.read(market_id);
            let (oracle_price, is_valid) = self.get_oracle_price(market_id);
            assert(is_valid, 'InvalidOraclePrice');
            let delta = spread_math::get_delta(
                params.max_delta, state.base_reserves, state.quote_reserves, oracle_price
            );
            let bid = spread_math::get_virtual_position(
                true, params.min_spread, delta, params.range, oracle_price, state.quote_reserves
            );
            let ask = spread_math::get_virtual_position(
                false, params.min_spread, delta, params.range, oracle_price, state.base_reserves
            );
            (bid, ask)
        }

        // Create market for solver.
        // At the moment, only callable by contract owner to prevent unwanted claiming of markets. 
        // Each market must be unique in `market_info`.
        //
        // # Arguments
        // * `market_info` - market info
        // * `params` - solver params
        fn create_market(ref self: ContractState, market_info: MarketInfo, params: MarketParams) {
            // Only callable by contract owner.
            self.assert_owner();

            // Check market is not already initialised.
            let market_id = id::market_id(market_info);
            assert(
                self.market_info.read(market_id).base_token == contract_address_const::<0x0>(),
                'AlreadyExists'
            );

            // Check params.
            assert(market_info.base_token != contract_address_const::<0x0>(), 'BaseTokenNull');
            assert(market_info.quote_token != contract_address_const::<0x0>(), 'QuoteTokenNull');
            assert(params.range != 0, 'RangeZero');
            assert(params.base_currency_id != 0, 'BaseIdNull');
            assert(params.quote_currency_id != 0, 'QuoteIdNull');

            // Set market info and params.
            self.market_info.write(market_id, market_info);
            self.market_params.write(market_id, params);

            // If vault is public, deploy vault token and update state.
            if market_info.is_public {
                let vault_token = self._deploy_vault_token(market_info);
                let mut state = self.market_state.read(market_id);
                state.vault_token = vault_token;
                self.market_state.write(market_id, state);
            }

            // Emit events.
            self
                .emit(
                    Event::CreateMarket(
                        CreateMarket {
                            market_id,
                            base_token: market_info.base_token,
                            quote_token: market_info.quote_token,
                            owner: market_info.owner,
                            is_public: market_info.is_public,
                        }
                    )
                );
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

        // Deposit initial liquidity to market.
        // Should be used whenever total deposits in a market are zero. This can happen both
        // when a market is first initialised, or subsequently whenever all deposits are withdrawn.
        //
        // # Arguments
        // * `market_id` - market id
        // * `base_amount` - base asset to deposit
        // * `quote_amount` - quote asset to deposit
        //
        // # Returns
        // * `shares` - pool shares minted in the form of liquidity
        fn deposit_initial(
            ref self: ContractState, market_id: felt252, base_amount: u256, quote_amount: u256
        ) -> u256 {
            // Fetch market info and state.
            let market_info = self.market_info.read(market_id);
            let mut state = self.market_state.read(market_id);

            // Run checks
            assert(!state.is_paused, 'Paused');
            assert(market_info.base_token != contract_address_const::<0x0>(), 'NotInit');
            assert(base_amount != 0 || quote_amount != 0, 'AmountsZero');
            assert(state.base_reserves != 0 || state.quote_reserves != 0, 'UseDeposit');
            if !market_info.is_public {
                self.assert_market_owner(market_id);
            }

            // Transfer tokens to contract.
            let contract = get_contract_address();
            let caller = get_caller_address();
            let base_token = ERC20ABIDispatcher { contract_address: market_info.base_token };
            let quote_token = ERC20ABIDispatcher { contract_address: market_info.quote_token };
            base_token.transferFrom(caller, contract, base_amount);
            quote_token.transferFrom(caller, contract, quote_amount);

            // Update reserves.
            state.base_reserves += base_amount;
            state.quote_reserves += quote_amount;
            self.market_state.write(market_id, state);

            // Calculate liquidity.
            let params = self.market_params.read(market_id);
            let (oracle_price, is_valid) = self.get_oracle_price(market_id);
            assert(is_valid, 'InvalidOraclePrice');
            let delta = spread_math::get_delta(
                params.max_delta, state.base_reserves, state.quote_reserves, oracle_price
            );
            let bid = spread_math::get_virtual_position(
                true, params.min_spread, delta, params.range, oracle_price, state.quote_reserves
            );
            let ask = spread_math::get_virtual_position(
                false, params.min_spread, delta, params.range, oracle_price, state.base_reserves
            );
            assert(bid.liquidity != 0 || ask.liquidity != 0, 'LiqZero');

            // Mint shares.
            let shares: u256 = (bid.liquidity + ask.liquidity).into();
            let token = IVaultTokenDispatcher { contract_address: state.vault_token };
            token.mint(caller, shares);

            // Emit event
            self
                .emit(
                    Event::Deposit(Deposit { market_id, caller, base_amount, quote_amount, shares })
                );

            shares
        }

        // Same as `deposit_initial`, but with a referrer.
        //
        // # Arguments
        // * `market_id` - market id
        // * `base_amount` - base asset to deposit
        // * `quote_amount` - quote asset to deposit
        // * `referrer` - referrer address
        //
        // # Returns
        // * `shares` - pool shares minted in the form of liquidity
        fn deposit_initial_with_referrer(
            ref self: ContractState,
            market_id: felt252,
            base_amount: u256,
            quote_amount: u256,
            referrer: ContractAddress
        ) -> u256 {
            // Check referrer is non-null.
            assert(referrer != contract_address_const::<0x0>(), 'ReferrerZero');

            // Emit referrer event. 
            let caller = get_caller_address();
            if caller != referrer {
                self.emit(Event::Referral(Referral { caller, referrer, }));
            }

            // Deposit initial.
            self.deposit_initial(market_id, base_amount, quote_amount)
        }

        // Deposit liquidity to market.
        // For public markets, this will take the lower of requested and available balances, 
        // and refund any excess tokens remaining after coercing to the prevailing vault token 
        // ratio. For private markets, will deposit the exact requested amounts.
        //
        // # Arguments
        // * `market_id` - market id
        // * `base_requested` - base asset requested to be deposited
        // * `quote_requested` - quote asset requested to be deposited
        //
        // # Returns
        // * `base_deposit` - base asset deposited
        // * `quote_deposit` - quote asset deposited
        // * `shares` - pool shares minted
        fn deposit(
            ref self: ContractState, market_id: felt252, base_amount: u256, quote_amount: u256
        ) -> (u256, u256, u256) {
            // Fetch market info and state.
            let market_info = self.market_info.read(market_id);
            let mut state = self.market_state.read(market_id);

            // Run checks.
            assert(!state.is_paused, 'Paused');
            assert(market_info.base_token != contract_address_const::<0x0>(), 'NotInit');
            assert(base_amount != 0 || quote_amount != 0, 'UseDepositInitial');
            if !market_info.is_public {
                self.assert_market_owner(market_id);
            }

            // Evaluate the lower of requested and available balances.
            let caller = get_caller_address();
            let base_token = ERC20ABIDispatcher { contract_address: market_info.base_token };
            let quote_token = ERC20ABIDispatcher { contract_address: market_info.quote_token };
            let available_base_amount = base_token.balanceOf(caller);
            let available_quote_amount = quote_token.balanceOf(caller);
            let base_capped = min(base_amount, available_base_amount);
            let quote_capped = min(quote_amount, available_quote_amount);

            // Calculate shares to mint.
            let mut base_deposit = base_capped;
            let mut quote_deposit = quote_capped;
            if market_info.is_public {
                base_deposit =
                    if state.quote_reserves == 0 {
                        base_capped
                    } else {
                        let base_equivalent = math::mul_div(
                            quote_capped, state.base_reserves, state.quote_reserves, false
                        );
                        min(base_capped, base_equivalent)
                    };
                quote_deposit =
                    if state.base_reserves == 0 {
                        quote_capped
                    } else {
                        let quote_equivalent = math::mul_div(
                            base_capped, state.quote_reserves, state.base_reserves, false
                        );
                        min(quote_capped, quote_equivalent)
                    };
            }
            assert(base_deposit != 0 || quote_deposit != 0, 'AmountZero');

            // Transfer tokens into contract.
            let contract = get_contract_address();
            if base_deposit != 0 {
                base_token.transferFrom(caller, contract, base_deposit);
            }
            if quote_deposit != 0 {
                quote_token.transferFrom(caller, contract, quote_deposit);
            }

            // Mint shares.
            let mut shares = 0;
            if market_info.is_public {
                let total_supply = ERC20ABIDispatcher { contract_address: state.vault_token }
                    .totalSupply();
                shares =
                    if state.quote_reserves > state.base_reserves {
                        math::mul_div(total_supply, quote_deposit, state.quote_reserves, false)
                    } else {
                        math::mul_div(total_supply, base_deposit, state.base_reserves, false)
                    };
                IVaultTokenDispatcher { contract_address: state.vault_token }.mint(caller, shares);
            }

            // Update reserves.
            state.base_reserves += base_deposit;
            state.quote_reserves += quote_deposit;
            self.market_state.write(market_id, state);

            // Emit event.
            self
                .emit(
                    Event::Deposit(
                        Deposit {
                            market_id,
                            caller,
                            base_amount: base_deposit,
                            quote_amount: quote_deposit,
                            shares,
                        }
                    )
                );

            (base_deposit, quote_deposit, shares)
        }

        // Same as `deposit`, but with a referrer.
        //
        // # Arguments
        // * `market_id` - market id
        // * `base_amount` - base asset desired
        // * `quote_amount` - quote asset desired
        // * `referrer` - referrer address
        //
        // # Returns
        // * `base_deposit` - base asset deposited
        // * `quote_deposit` - quote asset deposited
        // * `shares` - pool shares minted
        fn deposit_with_referrer(
            ref self: ContractState,
            market_id: felt252,
            base_amount: u256,
            quote_amount: u256,
            referrer: ContractAddress
        ) -> (u256, u256, u256) {
            // Check referrer is non-null.
            assert(referrer != contract_address_const::<0x0>(), 'ReferrerZero');

            // Emit referrer event. 
            let caller = get_caller_address();
            if caller != referrer {
                self.emit(Event::Referral(Referral { caller, referrer, }));
            }

            // Deposit.
            self.deposit(market_id, base_amount, quote_amount)
        }

        // Burn pool shares and withdraw funds from market.
        // Called for public vaults. For private vaults, use `withdraw_amount`.
        //
        // # Arguments
        // * `market_id` - market id
        // * `shares` - pool shares to burn
        //
        // # Returns
        // * `base_amount` - base asset withdrawn
        // * `quote_amount` - quote asset withdrawn
        fn withdraw_at_ratio(
            ref self: ContractState, market_id: felt252, shares: u256
        ) -> (u256, u256) {
            // Fetch state.
            let market_info = self.market_info.read(market_id);
            let mut state = self.market_state.read(market_id);

            // Run checks.
            assert(market_info.is_public, 'UseWithdrawAmounts');
            assert(shares != 0, 'SharesZero');
            assert(market_info.base_token != contract_address_const::<0x0>(), 'NotInit');
            let vault_token = ERC20ABIDispatcher { contract_address: state.vault_token };
            let caller = get_caller_address();
            assert(shares <= vault_token.balanceOf(caller), 'InsuffShares');
            let total_supply = vault_token.totalSupply();
            assert(total_supply != 0, 'SupplyZero');

            // Burn shares.
            IVaultTokenDispatcher { contract_address: state.vault_token }.burn(caller, shares);

            // Calculate share of reserves to withdraw. Commit state changes.
            let base_withdraw = math::mul_div(state.base_reserves, shares, total_supply, false);
            let quote_withdraw = math::mul_div(state.quote_reserves, shares, total_supply, false);
            state.base_reserves -= base_withdraw;
            state.quote_reserves -= quote_withdraw;
            self.market_state.write(market_id, state);

            // Deduct applicable fees, emit events and return withdrawn amounts.
            self._withdraw(market_id, base_withdraw, quote_withdraw, shares)
        }

        // Withdraw exact token amounts from market.
        // Called for private vaults. For public vaults, use `withdraw_at_ratio`.
        //
        // # Arguments
        // * `market_id` - market id
        // * `base_amount` - base amount requested
        // * `quote_amount` - quote amount requested
        //
        // # Returns
        // * `base_amount` - base asset withdrawn
        // * `quote_amount` - quote asset withdrawn
        fn withdraw_amounts(
            ref self: ContractState, market_id: felt252, base_amount: u256, quote_amount: u256
        ) -> (u256, u256) {
            // Fetch state.
            let market_info = self.market_info.read(market_id);
            let mut state = self.market_state.read(market_id);

            // Run checks.
            assert(!market_info.is_public, 'UseWithdrawAtRatio');
            assert(market_info.base_token != contract_address_const::<0x0>(), 'NotInit');

            // Cap withdraw amount at available. Commit state changes.
            let base_withdraw = min(base_amount, state.base_reserves);
            let quote_withdraw = min(quote_amount, state.quote_reserves);
            state.base_reserves -= base_withdraw;
            state.quote_reserves -= quote_withdraw;
            self.market_state.write(market_id, state);

            // Deduct applicable fees, emit events and return withdrawn amounts.
            self._withdraw(market_id, base_withdraw, quote_withdraw, 0)
        }

        // Collect withdrawal fees.
        // Only callable by contract owner.
        //
        // # Arguments
        // * `receiver` - address to receive fees
        // * `token` - token to collect fees for
        // * `amount` - amount of fees requested
        fn collect_withdraw_fees(
            ref self: ContractState, receiver: ContractAddress, token: ContractAddress, amount: u256
        ) -> u256 {
            // Run checks.
            self.assert_owner();
            let mut fees = self.withdraw_fees.read(token);
            assert(fees >= amount, 'InsuffFees');

            // Update fee balance.
            fees -= amount;
            self.withdraw_fees.write(token, fees);

            // Transfer fees to caller.
            let dispatcher = ERC20ABIDispatcher { contract_address: token };
            dispatcher.transfer(get_caller_address(), amount);

            // Emit event.
            self.emit(Event::CollectWithdrawFee(CollectWithdrawFee { receiver, token, amount }));

            // Return amount collected.
            amount
        }

        // Change parameters of the solver market.
        // Only callable by market owner.
        //
        // # Params
        // * `market_id` - market id
        // * `params` - market params
        fn set_params(ref self: ContractState, market_id: felt252, params: MarketParams) {
            // Run checks.
            self.assert_market_owner(market_id);
            let old_params = self.market_params.read(market_id);
            assert(old_params != params, 'ParamsUnchanged');
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

        // Set withdraw fee for a given market.
        // Only callable by contract owner.
        //
        // # Arguments
        // * `market_id` - market id
        // * `fee_rate` - fee rate
        fn set_withdraw_fee(ref self: ContractState, market_id: felt252, fee_rate: u16) {
            self.assert_owner();
            let old_fee_rate = self.withdraw_fee_rate.read(market_id);
            assert(old_fee_rate != fee_rate, 'FeeUnchanged');
            assert(fee_rate <= MAX_FEE_RATE, 'FeeOF');
            self.withdraw_fee_rate.write(market_id, fee_rate);
            self.emit(Event::SetWithdrawFee(SetWithdrawFee { market_id, fee_rate }));
        }

        // Change the oracle contract address.
        //
        // # Arguments
        // * `oracle` - contract address of oracle feed
        fn change_oracle(ref self: ContractState, oracle: ContractAddress) {
            self.assert_owner();
            let old_oracle = self.oracle.read();
            assert(oracle != old_oracle.contract_address, 'OracleUnchanged');
            let oracle_dispatcher = IOracleABIDispatcher { contract_address: oracle };
            self.oracle.write(oracle_dispatcher);
            self.emit(Event::ChangeOracle(ChangeOracle { oracle }));
        }

        // Set vault token class hash.
        // Only callable by contract owner.
        // 
        // # Arguments
        // * `new_class_hash` - new class hash of vault token
        fn change_vault_token_class(ref self: ContractState, new_class_hash: ClassHash) {
            self.assert_owner();
            let old_class_hash = self.vault_token_class.read();
            assert(old_class_hash != new_class_hash, 'ClassHashUnchanged');
            self.vault_token_class.write(new_class_hash);
            self
                .emit(
                    Event::ChangeVaultTokenClass(
                        ChangeVaultTokenClass { class_hash: new_class_hash }
                    )
                );
        }

        // Request transfer ownership of the contract.
        // Part 1 of 2 step process to transfer ownership.
        //
        // # Arguments
        // * `new_owner` - New owner of the contract
        fn transfer_owner(ref self: ContractState, new_owner: ContractAddress) {
            self.assert_owner();
            let old_owner = self.owner.read();
            assert(new_owner != old_owner, 'SameOwner');
            self.queued_owner.write(new_owner);
        }

        // Called by new owner to accept ownership of the contract.
        // Part 2 of 2 step process to transfer ownership.
        fn accept_owner(ref self: ContractState) {
            let queued_owner = self.queued_owner.read();
            assert(get_caller_address() == queued_owner, 'OnlyNewOwner');
            let old_owner = self.owner.read();
            self.owner.write(queued_owner);
            self.queued_owner.write(contract_address_const::<0x0>());
            self.emit(Event::ChangeOwner(ChangeOwner { old: old_owner, new: queued_owner }));
        }

        // Pause solver market. 
        // Only callable by market owner. 
        // 
        // # Arguments
        // * `market_id` - market id
        fn pause(ref self: ContractState, market_id: felt252) {
            self.assert_market_owner(market_id);
            let mut state = self.market_state.read(market_id);
            assert(!state.is_paused, 'AlreadyPaused');
            state.is_paused = true;
            self.market_state.write(market_id, state);
            self.emit(Event::Pause(Pause { market_id }));
        }

        // Unpause solver market.
        // Only callable by market owner.
        //
        // # Arguments
        // * `market_id` - market id
        fn unpause(ref self: ContractState, market_id: felt252) {
            self.assert_market_owner(market_id);
            let mut state = self.market_state.read(market_id);
            assert(state.is_paused, 'AlreadyUnpaused');
            state.is_paused = false;
            self.market_state.write(market_id, state);
            self.emit(Event::Unpause(Unpause { market_id }));
        }

        // Upgrade contract class.
        // Callable by owner only.
        //
        // # Arguments
        // * `new_class_hash` - new class hash of contract
        fn upgrade(ref self: ContractState, new_class_hash: ClassHash) {
            self.assert_owner();
            replace_class_syscall(new_class_hash).unwrap();
            self.emit(Event::Upgraded(Upgraded { class_hash: new_class_hash }));
        }
    }

    ////////////////////////////////
    // INTERNAL FUNCTIONS
    ////////////////////////////////

    #[abi(per_item)]
    #[generate_trait]
    impl InternalImpl of InternalTrait {
        // Internal function to deploy vault token for a market on initialisation.
        //
        // # Arguments
        // * `market_info` - market info
        fn _deploy_vault_token(
            ref self: ContractState, market_info: MarketInfo
        ) -> ContractAddress {
            // Fetch symbols of base and quote tokens.
            // We use a special versioned call for compatibility with both 
            // felt252 and ByteArray symbols.
            let base_symbol = erc20_versioned_call::get_symbol(market_info.base_token);
            let quote_symbol = erc20_versioned_call::get_symbol(market_info.quote_token);
            let name: ByteArray = format!(
                "Haiko {} {}-{}", self.name.read(), base_symbol, quote_symbol
            );
            let symbol: ByteArray = format!(
                "{}-{}-{}", self.symbol.read(), base_symbol, quote_symbol
            );
            let decimals: u8 = 18;
            let solver = get_contract_address();

            // Populate calldata
            let mut calldata: Array<felt252> = array![];
            name.serialize(ref calldata);
            symbol.serialize(ref calldata);
            decimals.serialize(ref calldata);
            solver.serialize(ref calldata);

            // Deploy vault token.
            let (token, _) = deploy_syscall(
                self.vault_token_class.read(), 0, calldata.span(), false
            )
                .unwrap();

            // Return vault token address.
            token
        }

        // Internal function to withdraw funds from market.
        // Amounts passed in should be before deducting applicable withdraw fees.
        // 
        // # Arguments
        // * `market_id` - market id
        // * `base_amount` - amount of base assets to withdraw, gross of withdraw fees
        // * `quote_amount` - amount of quote assets to withdraw, gross of withdraw fees
        // * `shares` - pool shares to burn for public vaults, or 0 for private vaults
        //
        // # Returns
        // * `base_withdraw` - base assets withdrawn
        // * `quote_withdraw` - quote assets withdrawn
        fn _withdraw(
            ref self: ContractState,
            market_id: felt252,
            base_amount: u256,
            quote_amount: u256,
            shares: u256
        ) -> (u256, u256) {
            // Initialise values.
            let mut base_withdraw = base_amount;
            let mut quote_withdraw = quote_amount;
            let mut base_withdraw_fees = 0;
            let mut quote_withdraw_fees = 0;

            // Deduct withdrawal fee.
            let withdraw_fee_rate = self.withdraw_fee_rate.read(market_id);
            if withdraw_fee_rate != 0 {
                base_withdraw_fees = fee_math::calc_fee(base_withdraw, withdraw_fee_rate);
                quote_withdraw_fees = fee_math::calc_fee(quote_withdraw, withdraw_fee_rate);
                base_withdraw -= base_withdraw_fees;
                quote_withdraw -= quote_withdraw_fees;
            }

            // Transfer tokens to caller.
            assert(base_withdraw != 0 || quote_withdraw != 0, 'AmountZero');
            let caller = get_caller_address();
            let market_info = self.market_info.read(market_id);
            if base_withdraw != 0 {
                let base_token = ERC20ABIDispatcher { contract_address: market_info.base_token };
                base_token.transfer(caller, base_withdraw);
            }
            if quote_withdraw != 0 {
                let quote_token = ERC20ABIDispatcher { contract_address: market_info.quote_token };
                quote_token.transfer(caller, quote_withdraw);
            }

            // Commit state updates.
            if base_withdraw_fees != 0 {
                let base_fees = self.withdraw_fees.read(market_info.base_token);
                self.withdraw_fees.write(market_info.base_token, base_fees + base_withdraw_fees);
            }
            if quote_withdraw_fees != 0 {
                let quote_fees = self.withdraw_fees.read(market_info.quote_token);
                self.withdraw_fees.write(market_info.quote_token, quote_fees + quote_withdraw_fees);
            }

            // Emit events.
            self
                .emit(
                    Event::Withdraw(
                        Withdraw { market_id, caller, base_amount, quote_amount, shares, }
                    )
                );
            if base_withdraw_fees != 0 {
                self
                    .emit(
                        Event::WithdrawFeeEarned(
                            WithdrawFeeEarned {
                                market_id, token: market_info.base_token, amount: base_withdraw_fees
                            }
                        )
                    );
            }
            if quote_withdraw_fees != 0 {
                self
                    .emit(
                        Event::WithdrawFeeEarned(
                            WithdrawFeeEarned {
                                market_id,
                                token: market_info.quote_token,
                                amount: quote_withdraw_fees
                            }
                        )
                    );
            }

            // Return withdrawn amounts.
            (base_withdraw, quote_withdraw)
        }
    }
}
