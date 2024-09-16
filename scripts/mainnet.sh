#############################
# Environment variables
#############################

export STARKNET_RPC=https://free-rpc.nethermind.io/mainnet-juno
export DEPLOYER=0x1418f16f5981dd3a79ddccc7b466d93c22c47f3203808a387145bd7b70d6daf
export OWNER=0x043777a54d5e36179709060698118f1f6f5553ca1918d1004b07640dfc425000
export STARKNET_KEYSTORE=~/.starkli-wallets/deployer/mainnet_deployer_keystore.json
export STARKNET_ACCOUNT=~/.starkli-wallets/deployer/mainnet_deployer_account.json
export ORACLE=0x2a85bd616f912537c50a49a4076db02c00b29b2cdc8a197ce92ed1837fa875b

#############################
# Declare contract class
#############################

# Vault token
starkli declare --rpc $STARKNET_RPC --account $STARKNET_ACCOUNT --keystore $STARKNET_KEYSTORE '/Users/parkyeung/dev/solver/target/dev/haiko_solver_replicating_VaultToken.contract_class.json'

# Replicating Solver
starkli declare --rpc $STARKNET_RPC --account $STARKNET_ACCOUNT --keystore $STARKNET_KEYSTORE '/Users/parkyeung/dev/solver/target/dev/haiko_solver_replicating_ReplicatingSolver.contract_class.json'

#############################
# Deploy contracts
#############################

# Replicating Solver
starkli deploy --rpc $STARKNET_RPC $REPLICATING_SOLVER_CLASS $OWNER $ORACLE $VAULT_TOKEN_CLASS

#############################
# Deployments
#############################

# 13 September 2024
export REPLICATING_SOLVER=0x073cc79b07a02fe5dcd714903d62f9f3081e15aeb34e3725f44e495ecd88a5a1
export REPLICATING_SOLVER_CLASS=0x030ba3f1857330dfe032ae7e43f51d4b206756ec4757fa3ac14e79ff79a98a44

# 28 August 2024
export REPLICATING_SOLVER=0x07f2975ef3d288a031a842bdb50253d6255344356f9f4a02e54fbc147b007a13
export REPLICATING_SOLVER_CLASS=0x0589858bd41fc0c922ff5c656f3373f7072fb8a69fcd02c8cdad0dce6666d4fb
export VAULT_TOKEN_CLASS=0x04c73cd841298b8ce734d5c6bd5ab4fc4eb18ef7ad3be7d87d450f8ef98d703b