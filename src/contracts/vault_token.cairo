#[starknet::contract]
pub mod VaultToken {
    // Core lib imports.
    use starknet::ContractAddress;
    use starknet::get_caller_address;

    // Local imports.
    use haiko_solver_replicating::interfaces::IVaultToken::IVaultToken;

    // External imports.
    use openzeppelin::token::erc20::ERC20Component;
    use openzeppelin::token::erc20::interface::IERC20Metadata;

    component!(path: ERC20Component, storage: erc20, event: ERC20Event);

    #[abi(embed_v0)]
    pub impl ERC20Impl = ERC20Component::ERC20Impl<ContractState>;
    #[abi(embed_v0)]
    pub impl ERC20CamelOnlyImpl = ERC20Component::ERC20CamelOnlyImpl<ContractState>;
    pub impl ERC20InternalImpl = ERC20Component::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        erc20: ERC20Component::Storage,
        // The decimals value is stored locally
        decimals: u8,
        // Owner contract address
        owner: ContractAddress
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        ERC20Event: ERC20Component::Event
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        name: felt252,
        symbol: felt252,
        decimals: u8,
        owner: ContractAddress,
    ) {
        // Call the internal function that writes decimals to storage
        self.set_decimals(decimals);
        self.erc20.initializer(name, symbol);
        self.owner.write(owner);
    }

    #[abi(embed_v0)]
    impl ERC20MetadataImpl of IERC20Metadata<ContractState> {
        fn name(self: @ContractState) -> felt252 {
            self.erc20.name()
        }

        fn symbol(self: @ContractState) -> felt252 {
            self.erc20.symbol()
        }

        fn decimals(self: @ContractState) -> u8 {
            self.decimals.read()
        }
    }

    #[abi(embed_v0)]
    impl IVaultTokenImpl of IVaultToken<ContractState> {
        fn owner(self: @ContractState) -> ContractAddress {
            self.owner.read()
        }

        fn mint(ref self: ContractState, account: ContractAddress, amount: u256) {
            self.assert_owner();
            self.erc20._mint(account, amount);
        }

        fn burn(ref self: ContractState, account: ContractAddress, amount: u256) {
            self.assert_owner();
            self.erc20._burn(account, amount);
        }
    }

    #[abi(per_item)]
    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn set_decimals(ref self: ContractState, decimals: u8) {
            self.decimals.write(decimals);
        }

        fn assert_owner(ref self: ContractState) {
            assert(get_caller_address() == self.owner.read(), 'OnlyOwner');
        }
    }
}
