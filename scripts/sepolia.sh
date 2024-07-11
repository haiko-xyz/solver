#############################
# Environment variables
#############################

export STARKNET_RPC=https://free-rpc.nethermind.io/sepolia-juno
export DEPLOYER=0x03c6f656e7f951a5ffc9d192e0c555970030e7af42015ba1e78c2dd239bb49a1
export OWNER=0x0469334529F1414f16B7eC53Ce369e79928847cC6A022993f155B44D3378C50C
export STARKNET_KEYSTORE=~/.starkli-wallets/deployer/sepolia_deployer_keystore.json
export STARKNET_ACCOUNT=~/.starkli-wallets/deployer/sepolia_deployer_account.json
export ORACLE=0x36031daa264c24520b11d93af622c848b2499b66b41d611bac95e13cfca131a

#############################
# Declare contract class
#############################

# Vault token
starkli declare --rpc $STARKNET_RPC --account $STARKNET_ACCOUNT --keystore $STARKNET_KEYSTORE '/Users/parkyeung/dev/solver/target/dev/haiko_solver_replicating_VaultToken.contract_class.json'

# Solver
starkli declare --rpc $STARKNET_RPC --account $STARKNET_ACCOUNT --keystore $STARKNET_KEYSTORE '/Users/parkyeung/dev/solver/target/dev/haiko_solver_replicating_ReplicatingSolver.contract_class.json'

#############################
# Deploy contracts
#############################

# Replicating Solver
starkli deploy --rpc $STARKNET_RPC $REPLICATING_SOLVER_CLASS $OWNER $ORACLE $VAULT_TOKEN_CLASS

#############################
# Deployments
#############################

# 10 July 2024
export REPLICATING_SOLVER_CLASS=0x0082584c2a39b356c029756b15e669369cfdc00b968c2905d57cc73e08b1eb97

# 5 July 2024
export REPLICATING_SOLVER=0x017ddcf29753c9780c964ece0dbb3015c52d26047c6abdfae503df6a59d466da
export REPLICATING_SOLVER_CLASS=0x06dac55bfd3ecc8fd164e2cc52ef52bcdfc9fba083bbccdfa4d4485a33b58b54
export VAULT_TOKEN_CLASS=0x04c73cd841298b8ce734d5c6bd5ab4fc4eb18ef7ad3be7d87d450f8ef98d703b

# 12 June 2024
export REPLICATING_SOLVER=0x06a8999834af14ab47c4f70632214c95e9c658e79d05d1b2aebc07afd881333c
export REPLICATING_SOLVER_CLASS=0x01368802ac8a80f85ec109e218cb68a0e4519a0727a9d3b95897ded3978a3470
export VAULT_TOKEN_CLASS=0x0375ac4a5e2fcf5323f3992541e050bd59c7aaa1b37ab6a1b271ebfbdf74a47b