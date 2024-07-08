#[starknet::component]
pub mod SolverComponent {
    // Core lib imports.
    use core::integer::BoundedInt;
    use core::poseidon::poseidon_hash_span;
    use core::cmp::{min, max};
    use starknet::ContractAddress;
    use starknet::contract_address::contract_address_const;
    use starknet::{get_caller_address, get_contract_address, get_block_timestamp};
    use starknet::class_hash::ClassHash;
    use starknet::syscalls::{replace_class_syscall, deploy_syscall};

    // Local imports.
    use haiko_solver_core::libraries::{
        id, erc20_versioned_call, store_packing::MarketStateStorePacking
    };
    use haiko_solver_core::interfaces::{
        ISolver::{ISolver, ISolverHooksDispatcher, ISolverHooksDispatcherTrait},
        IVaultToken::{IVaultTokenDispatcher, IVaultTokenDispatcherTrait},
    };
    use haiko_solver_core::types::{MarketInfo, MarketState, PositionInfo, SwapParams};

    // Haiko imports.
    use haiko_lib::{math::{math, fee_math}, constants::{ONE, LOG2_1_00001, MAX_FEE_RATE}};

    // External imports.
    use openzeppelin::token::erc20::interface::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};

    ////////////////////////////////
    // STORAGE
    ///////////////////////////////

    #[storage]
    struct Storage {
        // IMMUTABLE
        // solver name
        name: ByteArray,
        // solver symbol
        symbol: ByteArray,
        // OWNABLE
        // contract owner
        owner: ContractAddress,
        // queued contract owner (for ownership transfers)
        queued_owner: ContractAddress,
        // SOLVER
        // Indexed by market id
        market_info: LegacyMap::<felt252, MarketInfo>,
        // Indexed by market id
        market_state: LegacyMap::<felt252, MarketState>,
        // Indexed by market_id
        withdraw_fee_rate: LegacyMap::<felt252, u16>,
        // Indexed by asset
        withdraw_fees: LegacyMap::<ContractAddress, u256>,
        // vault token class hash
        vault_token_class: ClassHash,
    }

    ////////////////////////////////
    // EVENTS
    ///////////////////////////////

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        CreateMarket: CreateMarket,
        Deposit: Deposit,
        Withdraw: Withdraw,
        Swap: Swap,
        CollectWithdrawFee: CollectWithdrawFee,
        SetWithdrawFee: SetWithdrawFee,
        WithdrawFeeEarned: WithdrawFeeEarned,
        ChangeOwner: ChangeOwner,
        ChangeVaultTokenClass: ChangeVaultTokenClass,
        Pause: Pause,
        Unpause: Unpause,
        Referral: Referral,
        Upgraded: Upgraded,
    }

    #[derive(Drop, starknet::Event)]
    pub struct CreateMarket {
        #[key]
        pub market_id: felt252,
        pub base_token: ContractAddress,
        pub quote_token: ContractAddress,
        pub owner: ContractAddress,
        pub is_public: bool,
        pub vault_token: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    pub struct Swap {
        #[key]
        pub market_id: felt252,
        #[key]
        pub caller: ContractAddress,
        pub is_buy: bool,
        pub exact_input: bool,
        pub amount_in: u256,
        pub amount_out: u256,
    }

    #[derive(Drop, starknet::Event)]
    pub struct Deposit {
        #[key]
        pub caller: ContractAddress,
        #[key]
        pub market_id: felt252,
        pub base_amount: u256,
        pub quote_amount: u256,
        pub shares: u256,
    }

    #[derive(Drop, starknet::Event)]
    pub struct Withdraw {
        #[key]
        pub caller: ContractAddress,
        #[key]
        pub market_id: felt252,
        pub base_amount: u256,
        pub quote_amount: u256,
        pub shares: u256,
    }

    #[derive(Drop, starknet::Event)]
    pub struct SetWithdrawFee {
        #[key]
        pub market_id: felt252,
        pub fee_rate: u16,
    }

    #[derive(Drop, starknet::Event)]
    pub struct WithdrawFeeEarned {
        #[key]
        pub market_id: felt252,
        #[key]
        pub token: ContractAddress,
        pub amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    pub struct CollectWithdrawFee {
        #[key]
        pub receiver: ContractAddress,
        #[key]
        pub token: ContractAddress,
        pub amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    pub struct ChangeVaultTokenClass {
        pub class_hash: ClassHash,
    }

    #[derive(Drop, starknet::Event)]
    pub struct ChangeOwner {
        pub old: ContractAddress,
        pub new: ContractAddress
    }

    #[derive(Drop, starknet::Event)]
    pub struct Pause {
        #[key]
        pub market_id: felt252,
    }

    #[derive(Drop, starknet::Event)]
    pub struct Unpause {
        #[key]
        pub market_id: felt252,
    }

    #[derive(Drop, starknet::Event)]
    pub struct Referral {
        #[key]
        pub caller: ContractAddress,
        pub referrer: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    pub struct Upgraded {
        pub class_hash: ClassHash,
    }

    ////////////////////////////////
    // FUNCTIONS
    ////////////////////////////////

    #[abi(per_item)]
    #[generate_trait]
    pub impl SolverModifier<
        TContractState, +HasComponent<TContractState>
    > of ModifierTrait<TContractState> {
        fn assert_owner(self: @ComponentState<TContractState>) {
            assert(self.owner.read() == get_caller_address(), 'OnlyOwner');
        }

        fn assert_market_owner(self: @ComponentState<TContractState>, market_id: felt252) {
            let market_info: MarketInfo = self.market_info.read(market_id);
            assert(market_info.owner == get_caller_address(), 'OnlyMarketOwner');
        }
    }

    #[embeddable_as(SolverImpl)]
    pub impl Solver<
        TContractState, +HasComponent<TContractState>
    > of ISolver<ComponentState<TContractState>> {
        // Get the name of the solver.
        // 
        // # Returns
        // * `name` - solver name
        fn name(self: @ComponentState<TContractState>) -> ByteArray {
            self.name.read()
        }

        // Get the symbol of the solver.
        // 
        // # Returns
        // * `symbol` - solver symbol
        fn symbol(self: @ComponentState<TContractState>) -> ByteArray {
            self.symbol.read()
        }

        // Market id
        fn market_id(self: @ComponentState<TContractState>, market_info: MarketInfo) -> felt252 {
            id::market_id(market_info)
        }

        // Immutable market information
        fn market_info(self: @ComponentState<TContractState>, market_id: felt252) -> MarketInfo {
            self.market_info.read(market_id)
        }

        // Market state
        fn market_state(self: @ComponentState<TContractState>, market_id: felt252) -> MarketState {
            self.market_state.read(market_id)
        }

        // Vault token class hash
        fn vault_token_class(self: @ComponentState<TContractState>) -> ClassHash {
            self.vault_token_class.read()
        }

        // Contract owner
        fn owner(self: @ComponentState<TContractState>) -> ContractAddress {
            self.owner.read()
        }

        // Queued contract owner, used for ownership transfers
        fn queued_owner(self: @ComponentState<TContractState>) -> ContractAddress {
            self.queued_owner.read()
        }

        // Withdraw fee rate for a given market
        fn withdraw_fee_rate(self: @ComponentState<TContractState>, market_id: felt252) -> u16 {
            self.withdraw_fee_rate.read(market_id)
        }

        // Accumulated withdraw fee balance for a given asset
        fn withdraw_fees(self: @ComponentState<TContractState>, token: ContractAddress) -> u256 {
            self.withdraw_fees.read(token)
        }

        // Get token balances held in solver market.
        // 
        // # Arguments
        // * `market_id` - market id
        //
        // # Returns
        // * `base_amount` - total base tokens owned
        // * `quote_amount` - total quote tokens owned
        fn get_balances(self: @ComponentState<TContractState>, market_id: felt252) -> (u256, u256) {
            let state: MarketState = self.market_state.read(market_id);
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
            self: @ComponentState<TContractState>, market_ids: Span<felt252>
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
            self: @ComponentState<TContractState>,
            users: Span<ContractAddress>,
            market_ids: Span<felt252>
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

        // Create market for solver.
        // At the moment, only callable by contract owner to prevent unwanted claiming of markets. 
        // Each market must be unique in `market_info`.
        //
        // # Arguments
        // * `market_info` - market info
        //
        // # Returns
        // * `market_id` - market id
        // * `vault_token` (optional) - vault token address (if public market)
        fn create_market(
            ref self: ComponentState<TContractState>, market_info: MarketInfo
        ) -> (felt252, Option<ContractAddress>) {
            // Only callable by contract owner.
            self.assert_owner();

            // Check market is not already initialised.
            let market_id = id::market_id(market_info);
            let existing_market_info: MarketInfo = self.market_info.read(market_id);
            assert(
                existing_market_info.base_token == contract_address_const::<0x0>(), 'MarketExists'
            );

            // Check params.
            assert(market_info.base_token != contract_address_const::<0x0>(), 'BaseTokenNull');
            assert(market_info.quote_token != contract_address_const::<0x0>(), 'QuoteTokenNull');
            assert(market_info.owner != contract_address_const::<0x0>(), 'OwnerNull');

            // Set market info.
            self.market_info.write(market_id, market_info);

            // If vault is public, deploy vault token and update state.
            let mut vault_token: Option<ContractAddress> = Option::None(());
            if market_info.is_public {
                let vault_token_addr = self._deploy_vault_token(market_info);
                vault_token = Option::Some(vault_token_addr);
                let mut state: MarketState = self.market_state.read(market_id);
                state.vault_token = vault_token_addr;
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
                            vault_token: match vault_token {
                                Option::Some(addr) => addr,
                                Option::None => contract_address_const::<0x0>(),
                            },
                        }
                    )
                );

            // Return market id
            (market_id, vault_token)
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
            ref self: ComponentState<TContractState>, market_id: felt252, swap_params: SwapParams,
        ) -> (u256, u256) {
            // Get amounts.
            let solver_hooks = ISolverHooksDispatcher { contract_address: get_contract_address() };
            let (amount_in, amount_out) = solver_hooks.quote(market_id, swap_params);

            // Check amounts non-zero and satisfy threshold amounts.
            assert(amount_in != 0 && amount_out != 0, 'AmountZero');
            if swap_params.threshold_amount.is_some() {
                let threshold_amount_val = swap_params.threshold_amount.unwrap();
                assert(threshold_amount_val != 0, 'ThresholdAmountZero');
                if swap_params.exact_input && (amount_out < threshold_amount_val) {
                    panic(array!['ThresholdAmount', amount_out.low.into(), amount_out.high.into()]);
                }
                if !swap_params.exact_input && (amount_in > threshold_amount_val) {
                    panic(array!['ThresholdAmount', amount_in.low.into(), amount_in.high.into()]);
                }
            }

            // Transfer tokens.
            let market_info: MarketInfo = self.market_info.read(market_id);
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
            let mut state: MarketState = self.market_state.read(market_id);
            if swap_params.is_buy {
                state.quote_reserves += amount_in;
                state.base_reserves -= amount_out;
            } else {
                state.base_reserves += amount_in;
                state.quote_reserves -= amount_out;
            }
            self.market_state.write(market_id, state);

            // Execute after swap hook.
            solver_hooks.after_swap(market_id, swap_params);

            // Emit events.
            self
                .emit(
                    Event::Swap(
                        Swap {
                            market_id,
                            caller,
                            is_buy: swap_params.is_buy,
                            exact_input: swap_params.exact_input,
                            amount_in,
                            amount_out
                        }
                    )
                );

            (amount_in, amount_out)
        }

        // Deposit initial liquidity to market.
        // Should be used whenever total deposits in a market are zero. This can happen both
        // when a market is first initialised, or subsequently whenever all deposits are withdrawn.
        //
        // # Arguments
        // * `market_id` - market id
        // * `base_amount` - amount of base asset requested to be deposited
        // * `quote_amount` - amount of quote asset requested to be deposited
        //
        // # Returns
        // * `base_deposit` - base asset deposited
        // * `quote_deposit` - quote asset deposited
        // * `shares` - pool shares minted in the form of liquidity
        fn deposit_initial(
            ref self: ComponentState<TContractState>,
            market_id: felt252,
            base_amount: u256,
            quote_amount: u256
        ) -> (u256, u256, u256) {
            // Fetch market info and state.
            let market_info = self.market_info.read(market_id);
            let mut state: MarketState = self.market_state.read(market_id);

            // Run checks
            assert(!state.is_paused, 'Paused');
            assert(market_info.base_token != contract_address_const::<0x0>(), 'MarketNull');
            assert(state.base_reserves == 0 && state.quote_reserves == 0, 'UseDeposit');
            if !market_info.is_public {
                self.assert_market_owner(market_id);
            }

            // Cap deposit at available.
            let caller = get_caller_address();
            let base_token = ERC20ABIDispatcher { contract_address: market_info.base_token };
            let quote_token = ERC20ABIDispatcher { contract_address: market_info.quote_token };
            let base_available = base_token.balanceOf(caller);
            let quote_available = quote_token.balanceOf(caller);
            let base_deposit = min(base_amount, base_available);
            let quote_deposit = min(quote_amount, quote_available);
            assert(base_deposit != 0 || quote_deposit != 0, 'AmountsZero');

            // Transfer tokens to contract.
            let contract = get_contract_address();
            if base_deposit != 0 {
                assert(base_token.balanceOf(caller) >= base_deposit, 'BaseBalance');
                assert(base_token.allowance(caller, contract) >= base_deposit, 'BaseAllowance');
                base_token.transferFrom(caller, contract, base_deposit);
            }
            if quote_deposit != 0 {
                assert(quote_token.balanceOf(caller) >= quote_deposit, 'QuoteBalance');
                assert(quote_token.allowance(caller, contract) >= quote_deposit, 'QuoteAllowance');
                quote_token.transferFrom(caller, contract, quote_deposit);
            }

            // Update reserves.
            // Must commit state here to be able to fetch virtual positions.
            state.base_reserves += base_deposit;
            state.quote_reserves += quote_deposit;
            self.market_state.write(market_id, state);

            // Mint starting shares based on liquidity of virtual positions.
            let mut shares: u256 = 0;
            if market_info.is_public {
                let solver_hooks = ISolverHooksDispatcher {
                    contract_address: get_contract_address()
                };
                shares = solver_hooks.initial_supply(market_id);
                assert(shares != 0, 'SharesZero');
                let token = IVaultTokenDispatcher { contract_address: state.vault_token };
                token.mint(caller, shares);
            }

            // Emit event.
            self
                .emit(
                    Event::Deposit(
                        Deposit {
                            market_id,
                            caller,
                            base_amount: base_deposit,
                            quote_amount: quote_deposit,
                            shares
                        }
                    )
                );

            (base_deposit, quote_deposit, shares)
        }

        // Same as `deposit_initial`, but with a referrer.
        //
        // # Arguments
        // * `market_id` - market id
        // * `base_requested` - base asset requested to be deposited
        // * `quote_requested` - quote asset requested to be deposited
        // * `referrer` - referrer address
        //
        // # Returns
        // * `base_deposit` - base asset deposited
        // * `quote_deposit` - quote asset deposited
        // * `shares` - pool shares minted in the form of liquidity
        fn deposit_initial_with_referrer(
            ref self: ComponentState<TContractState>,
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
            ref self: ComponentState<TContractState>,
            market_id: felt252,
            base_amount: u256,
            quote_amount: u256
        ) -> (u256, u256, u256) {
            // Fetch market info and state.
            let market_info = self.market_info.read(market_id);
            let mut state: MarketState = self.market_state.read(market_id);

            // Run checks.
            assert(!state.is_paused, 'Paused');
            assert(market_info.base_token != contract_address_const::<0x0>(), 'MarketNull');
            assert(state.base_reserves != 0 || state.quote_reserves != 0, 'UseDepositInitial');
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

            // Calculate deposit amounts.
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
            ref self: ComponentState<TContractState>,
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
            ref self: ComponentState<TContractState>, market_id: felt252, shares: u256
        ) -> (u256, u256) {
            // Fetch state.
            let market_info = self.market_info.read(market_id);
            let mut state: MarketState = self.market_state.read(market_id);

            // Run checks.
            assert(market_info.base_token != contract_address_const::<0x0>(), 'MarketNull');
            assert(shares != 0, 'SharesZero');
            assert(market_info.is_public, 'UseWithdraw');
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
        fn withdraw(
            ref self: ComponentState<TContractState>,
            market_id: felt252,
            base_amount: u256,
            quote_amount: u256
        ) -> (u256, u256) {
            // Fetch state.
            let market_info = self.market_info.read(market_id);
            let mut state: MarketState = self.market_state.read(market_id);

            // Run checks.
            assert(market_info.base_token != contract_address_const::<0x0>(), 'MarketNull');
            assert(!market_info.is_public, 'UseWithdrawAtRatio');
            self.assert_market_owner(market_id);

            // Cap withdraw amount at available. Commit state changes.
            let base_withdraw = min(base_amount, state.base_reserves);
            let quote_withdraw = min(quote_amount, state.quote_reserves);

            // Commit state updates.
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
        fn collect_withdraw_fees(
            ref self: ComponentState<TContractState>,
            receiver: ContractAddress,
            token: ContractAddress
        ) -> u256 {
            // Run checks.
            self.assert_owner();
            let fees = self.withdraw_fees.read(token);
            assert(fees > 0, 'NoFees');

            // Update fee balance.
            self.withdraw_fees.write(token, 0);

            // Transfer fees to caller.
            let dispatcher = ERC20ABIDispatcher { contract_address: token };
            dispatcher.transfer(get_caller_address(), fees);

            // Emit event.
            self
                .emit(
                    Event::CollectWithdrawFee(CollectWithdrawFee { receiver, token, amount: fees })
                );

            // Return amount collected.
            fees
        }

        // Set withdraw fee for a given market.
        // Only callable by contract owner.
        //
        // # Arguments
        // * `market_id` - market id
        // * `fee_rate` - fee rate
        fn set_withdraw_fee(
            ref self: ComponentState<TContractState>, market_id: felt252, fee_rate: u16
        ) {
            self.assert_owner();
            let old_fee_rate = self.withdraw_fee_rate.read(market_id);
            assert(old_fee_rate != fee_rate, 'FeeUnchanged');
            assert(fee_rate <= MAX_FEE_RATE, 'FeeOF');
            self.withdraw_fee_rate.write(market_id, fee_rate);
            self.emit(Event::SetWithdrawFee(SetWithdrawFee { market_id, fee_rate }));
        }

        // Set vault token class hash.
        // Only callable by contract owner.
        // 
        // # Arguments
        // * `new_class_hash` - new class hash of vault token
        fn change_vault_token_class(
            ref self: ComponentState<TContractState>, new_class_hash: ClassHash
        ) {
            self.assert_owner();
            let old_class_hash = self.vault_token_class.read();
            assert(old_class_hash != new_class_hash, 'ClassHashUnchanged');
            assert(new_class_hash.into() != 0, 'ClassHashZero');
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
        fn transfer_owner(ref self: ComponentState<TContractState>, new_owner: ContractAddress) {
            self.assert_owner();
            let old_owner = self.owner.read();
            assert(new_owner != old_owner, 'SameOwner');
            self.queued_owner.write(new_owner);
        }

        // Called by new owner to accept ownership of the contract.
        // Part 2 of 2 step process to transfer ownership.
        fn accept_owner(ref self: ComponentState<TContractState>) {
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
        fn pause(ref self: ComponentState<TContractState>, market_id: felt252) {
            self.assert_market_owner(market_id);
            let mut state: MarketState = self.market_state.read(market_id);
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
        fn unpause(ref self: ComponentState<TContractState>, market_id: felt252) {
            self.assert_market_owner(market_id);
            let mut state: MarketState = self.market_state.read(market_id);
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
        fn upgrade(ref self: ComponentState<TContractState>, new_class_hash: ClassHash) {
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
    pub impl InternalImpl<
        TContractState, +HasComponent<TContractState>
    > of InternalTrait<TContractState> {
        // Internal function to init the contract by setting the solver name and symbol, contract owner,
        // and vault token class hash. This function should only be called inside the constructor.
        //
        // # Arguments
        // * `name` - solver name
        // * `symbol` - solver symbol
        // * `owner` - contract owner
        // * `vault_token_class` - vault token class hash
        fn _initializer(
            ref self: ComponentState<TContractState>,
            name: ByteArray,
            symbol: ByteArray,
            owner: ContractAddress,
            vault_token_class: ClassHash
        ) {
            self.name.write(name);
            self.symbol.write(symbol);
            self.owner.write(owner);
            self.vault_token_class.write(vault_token_class);
        }

        // Internal function to deploy vault token for a market on initialisation.
        //
        // # Arguments
        // * `market_info` - market info
        fn _deploy_vault_token(
            ref self: ComponentState<TContractState>, market_info: MarketInfo
        ) -> ContractAddress {
            // Fetch symbols of base and quote tokens.
            // We use a special versioned call for compatibility with both 
            // felt252 and ByteArray symbols.
            let base_symbol = erc20_versioned_call::get_symbol(market_info.base_token);
            let quote_symbol = erc20_versioned_call::get_symbol(market_info.quote_token);
            let name: ByteArray = format!("Haiko {} {}-{}", self.name(), base_symbol, quote_symbol);
            let symbol: ByteArray = format!(
                "HAIKO-{}-{}-{}", self.symbol(), base_symbol, quote_symbol
            );
            let decimals: u8 = 18;
            let owner = get_contract_address();

            // Populate calldata
            let mut calldata: Array<felt252> = array![];
            name.serialize(ref calldata);
            symbol.serialize(ref calldata);
            decimals.serialize(ref calldata);
            owner.serialize(ref calldata);

            // Ensure uniqueness of token by hashing MarketInfo as salt.
            let mut salt_data: Array<felt252> = array![];
            market_info.base_token.serialize(ref salt_data);
            market_info.quote_token.serialize(ref salt_data);
            market_info.owner.serialize(ref salt_data);
            let salt = poseidon_hash_span(salt_data.span());

            // Deploy vault token.
            let (token, _) = deploy_syscall(
                self.vault_token_class.read(), salt, calldata.span(), false
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
            ref self: ComponentState<TContractState>,
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
            let market_info: MarketInfo = self.market_info.read(market_id);
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
