// Component to implement decentralised governance of parameters for solver markets.
// Note this component does not handle storage of proposed parameters. This should be
// handled by the solver by implementing `propose_market_params` and `set_passed_market_params`.

#[starknet::component]
pub mod GovernorComponent {
    // Core lib imports.
    use starknet::ContractAddress;
    use core::cmp::min;
    use starknet::{get_caller_address, get_block_timestamp, get_contract_address};
    use starknet::storage::StorageMemberAccessImpl;

    // Local imports.
    use haiko_solver_core::contracts::solver::{
        SolverComponent, SolverComponent::{SolverModifier, InternalImpl as SolverInternalImpl}
    };
    use haiko_solver_core::interfaces::{
        ISolver::ISolver,
        IGovernor::{IGovernor, IGovernorHooksDispatcher, IGovernorHooksDispatcherTrait},
    };
    use haiko_solver_core::types::governor::{GovernorParams, Proposal};

    // External imports.
    use openzeppelin::token::erc20::interface::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};

    ////////////////////////////////
    // STORAGE
    ///////////////////////////////

    #[storage]
    struct Storage {
        // Governance parameters for all solver markets
        governor_params: GovernorParams,
        // Indexed by market id
        enabled: LegacyMap::<felt252, bool>,
        // Indexed by market id
        current_proposal: LegacyMap::<felt252, felt252>,
        // Indexed by proposal id
        proposals: LegacyMap::<felt252, Proposal>,
        // Indexed by (voter address, proposal_id)
        user_votes: LegacyMap::<(ContractAddress, felt252), u256>,
        // Indexed by proposal id
        total_votes: LegacyMap::<felt252, u256>,
        // Last assigned proposal id
        last_proposal_id: felt252,
    }

    ////////////////////////////////
    // EVENTS
    ///////////////////////////////

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        SetEnableGovernor: SetEnableGovernor,
        ChangeGovernorParams: ChangeGovernorParams,
        VoteMarketParams: VoteMarketParams,
    }

    #[derive(Drop, starknet::Event)]
    pub struct SetEnableGovernor {
        #[key]
        pub market_id: felt252,
        pub enabled: bool,
    }

    #[derive(Drop, starknet::Event)]
    pub struct ChangeGovernorParams {
        pub quorum: u16,
        pub min_ownership: u32,
        pub duration: u64,
    }

    #[derive(Drop, starknet::Event)]
    pub struct VoteMarketParams {
        pub market_id: felt252,
        pub proposal_id: felt252,
        pub caller: ContractAddress,
        pub shares: u256,
    }

    ////////////////////////////////
    // FUNCTIONS
    ///////////////////////////////

    #[embeddable_as(GovernorImpl)]
    pub impl Governor<
        TContractState,
        +HasComponent<TContractState>,
        +Drop<TContractState>,
        impl Solver: SolverComponent::HasComponent<TContractState>,
    > of IGovernor<ComponentState<TContractState>> {
        // Get governance parameters.
        //
        // # Returns
        // * `params` - governance params
        fn governor_params(self: @ComponentState<TContractState>) -> GovernorParams {
            self.governor_params.read()
        }

        // Check if market-level governance is enabled.
        //
        // # Params
        // * `market_id` - market id
        //
        // # Returns
        // * `enabled` - whether governance is enabled
        fn governor_enabled(self: @ComponentState<TContractState>, market_id: felt252) -> bool {
            self.enabled.read(market_id)
        }

        // Get current proposal id for market.
        // This can be the current active proposal, or the last expired one.
        //
        // # Params
        // * `market_id` - market id
        //
        // # Returns
        // * `proposal_id` - proposal id
        fn current_proposal(self: @ComponentState<TContractState>, market_id: felt252) -> felt252 {
            self.current_proposal.read(market_id)
        }

        // Get market param proposal.
        //
        // # Params
        // * `proposal_id` - proposal id
        //
        // # Returns
        // * `proposal` - proposal details
        fn proposal(self: @ComponentState<TContractState>, proposal_id: felt252) -> Proposal {
            self.proposals.read(proposal_id)
        }

        // Get user vote weight for proposal.
        //
        // # Params
        // * `caller` - caller address
        // * `proposal_id` - proposal id
        //
        // # Returns
        // * `shares` - user vote weight
        fn user_votes(
            self: @ComponentState<TContractState>, caller: ContractAddress, proposal_id: felt252
        ) -> u256 {
            self.user_votes.read((caller, proposal_id))
        }

        // Get total votes for proposal.
        //
        // # Params
        // `proposal_id` - proposal id
        //
        // # Returns
        // * `total_votes` - total votes for proposal
        fn total_votes(self: @ComponentState<TContractState>, proposal_id: felt252) -> u256 {
            self.total_votes.read(proposal_id)
        }

        // Get last assigned proposal id.
        //
        // # Returns
        // * `last_proposal_id` - last proposal id
        fn last_proposal_id(self: @ComponentState<TContractState>) -> felt252 {
            self.last_proposal_id.read()
        }

        // Enable or disable governor for market.
        //
        // # Params
        // * `market_id` - market id
        fn toggle_governor_enabled(ref self: ComponentState<TContractState>, market_id: felt252) {
            // Check caller is market owner
            let solver_comp = get_dep_component!(@self, Solver);
            solver_comp.assert_market_owner(market_id);

            // Check market is public.
            let market_info = solver_comp.market_info(market_id);
            assert(market_info.is_public, 'NotPublic');

            // Toggle.
            let status = self.enabled.read(market_id);
            self.enabled.write(market_id, !status);

            // Emit event.
            self.emit(Event::SetEnableGovernor(SetEnableGovernor { market_id, enabled: !status }));
        }

        // Change quorum, minimum vote ownership or vote duration.
        // Only callable by contract owner.
        // 
        // # Params
        // * `params` - governance params
        fn change_governor_params(
            ref self: ComponentState<TContractState>, params: GovernorParams
        ) {
            // Check caller is contract owner
            let solver_comp = get_dep_component!(@self, Solver);
            solver_comp.assert_owner();

            // Check governance params are changed.
            let current_params = self.governor_params.read();
            assert(current_params != params, 'SameParams');

            // Verify params.
            assert(params.quorum > 0, 'QuorumZero');
            assert(params.quorum <= 10000, 'QuorumOF');
            assert(params.min_ownership > 0, 'OwnershipZero');
            assert(params.min_ownership <= 1000000, 'OwnershipOF');
            assert(params.duration > 0, 'DurationZero');

            // Update governance params.
            self.governor_params.write(params);

            // Emit event.
            self
                .emit(
                    Event::ChangeGovernorParams(
                        ChangeGovernorParams {
                            quorum: params.quorum,
                            min_ownership: params.min_ownership,
                            duration: params.duration,
                        }
                    )
                );
        }

        // Vote for the current proposed market params.
        //
        // # Params
        // * `market_id` - market id
        fn vote_proposed_market_params(
            ref self: ComponentState<TContractState>, market_id: felt252
        ) {
            // Caller must be a depositor of the market.
            let solver_comp = get_dep_component!(@self, Solver);
            let market_state = solver_comp.market_state(market_id);
            let vault_token = ERC20ABIDispatcher { contract_address: market_state.vault_token };
            let caller = get_caller_address();
            let shares = vault_token.balance_of(caller);
            assert(shares > 0, 'NoShares');

            // Check a proposal is ongoing.
            let proposal_id = self.current_proposal.read(market_id);
            assert(proposal_id != 0, 'NoProposal');
            let proposal: Proposal = self.proposals.read(proposal_id);
            let now = get_block_timestamp();
            assert(proposal.expiry > now, 'ProposalExpired');

            // To prevent double voting, we apply the diff between existing user vote and 
            // current balance to the total votes.
            let user_vote = self.user_votes.read((caller, proposal_id));
            let mut total_vote = self.total_votes.read(proposal_id);
            total_vote += shares;
            total_vote -= user_vote;
            self.user_votes.write((caller, proposal_id), shares);
            self.total_votes.write(proposal_id, total_vote);

            // Emit event.
            self
                .emit(
                    Event::VoteMarketParams(
                        VoteMarketParams { market_id, proposal_id, caller, shares, }
                    )
                );

            // Check quorum is reached, and if so, apply the new params.
            // Note that we don't emit any events here as this falls on the hook function
            // implemented by individual solver implementations.
            let params = self.governor_params.read();
            let total_supply = vault_token.total_supply();
            if total_vote * 10000 >= total_supply * params.quorum.into() {
                let contract = get_contract_address();
                let governance_hooks = IGovernorHooksDispatcher { contract_address: contract };
                let mut solver_comp_mut = get_dep_component_mut!(ref self, Solver);
                solver_comp_mut.unlocked.write(true);
                governance_hooks.set_passed_market_params(proposal.market_id, proposal.proposal_id);
                solver_comp_mut.unlocked.write(false);
            }
        }

        // After withdraw hook call to be called by solver implementation.
        fn after_withdraw_governor(
            ref self: ComponentState<TContractState>,
            market_id: felt252,
            depositor: ContractAddress,
            shares: u256
        ) {
            // Check caller is solver.
            let solver_comp = get_dep_component!(@self, Solver);
            assert(solver_comp.unlocked.read(), 'NotSolver');

            // Check a proposal is ongoing.
            let proposal_id = self.current_proposal.read(market_id);
            if proposal_id == 0 {
                return;
            }

            // Check user has voted for it.
            let mut user_vote = self.user_votes.read((depositor, proposal_id));
            if user_vote == 0 {
                return;
            }

            // Update user vote.
            let mut total_vote = self.total_votes.read(proposal_id);
            let debit = min(shares, user_vote);
            user_vote -= debit;
            total_vote -= debit;
            self.user_votes.write((depositor, proposal_id), user_vote);
            self.total_votes.write(proposal_id, total_vote);

            // Emit event to update voter balance.
            self
                .emit(
                    Event::VoteMarketParams(
                        VoteMarketParams { market_id, proposal_id, caller: depositor, shares: 0 }
                    )
                );
        }
    }

    ////////////////////////////////
    // INTERNAL FUNCTIONS
    ////////////////////////////////

    #[abi(per_item)]
    #[generate_trait]
    pub impl InternalImpl<
        TContractState,
        +HasComponent<TContractState>,
        impl Solver: SolverComponent::HasComponent<TContractState>,
    > of InternalTrait<TContractState> {
        // Internal function to initiate proposal to update market params.

        // Can only be called for a public market with pool-level governance enabled. 
        // Passing a proposal requires a yes vote from market owners totaling above quorum 
        // to confirm the change. Callable by market owner, or any depositor with
        // ownership above the min threshold (to prevent ddos). Only one proposal can be
        // active at any time. Proposals last for the set duration, or until accepted.
        //
        // Note this function is a low-level function that should be called from a higher level
        // `propose_market_params` function that stores proposed params and emits events. 
        //
        // # Params
        // * `market_id` - market id
        // 
        // # Returns
        // * `proposal_id` - proposal id
        fn _propose_market_params(
            ref self: ComponentState<TContractState>, market_id: felt252,
        ) -> felt252 {
            // Run checks.
            // Check market is public.
            let solver_comp = get_dep_component!(@self, Solver);
            let market_info = solver_comp.market_info(market_id);
            assert(market_info.is_public, 'NotPublic');

            // Governance must be enabled by owner.
            let enabled = self.enabled.read(market_id);
            assert(enabled, 'NotEnabled');

            // Governor params must be set.
            let params = self.governor_params.read();
            assert(params != Default::default(), 'ParamsNotSet');

            // No other proposal must be ongoing.
            // It is possible that the current proposal expired without passing, so check its expiry.
            let current_proposal_id = self.current_proposal.read(market_id);
            let now = get_block_timestamp();
            if current_proposal_id != 0 {
                let current_proposal: Proposal = self.proposals.read(current_proposal_id);
                assert(now >= current_proposal.expiry, 'VoteOngoing');
            }

            // Caller must be market owner or depositor with above min threshold.
            let caller = get_caller_address();
            let market_state = solver_comp.market_state(market_id);
            let vault_token = ERC20ABIDispatcher { contract_address: market_state.vault_token };
            let caller_shares = vault_token.balance_of(caller);
            let total_shares = vault_token.total_supply();
            assert(
                caller_shares * 10000 >= total_shares * params.min_ownership.into(), 'SharesTooLow'
            );

            // Assign and update proposal id
            let proposal_id = self.last_proposal_id.read() + 1;
            self.last_proposal_id.write(proposal_id);

            // Define proposal.
            let now = get_block_timestamp();
            let proposal = Proposal {
                proposer: caller, market_id, proposal_id, expiry: now + params.duration,
            };

            // Update state.
            self.proposals.write(proposal_id, proposal);
            self.current_proposal.write(market_id, proposal_id);
            self.user_votes.write((caller, proposal_id), caller_shares);
            self.total_votes.write(proposal_id, caller_shares);

            // Return proposal id.
            // Note: no events are emitted here as it is a low level function. 
            // Solvers should implement a `propose_market_params` function to emit relevant events.
            proposal_id
        }
    }
}
