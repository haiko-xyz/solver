import fs from "fs";
import { RpcProvider, Account, Contract, json } from "starknet";
import dotenv from "dotenv";
import { bigIntToAddress, shortenAddress, toDecimals } from "./utils";
dotenv.config();

import { ENV } from "./env";
import { INITIAL_MARKETS } from "./configs";

// Import abi
const replicatingSolverAbi = json.parse(
  fs.readFileSync("src/abis/ReplicatingSolver.json").toString("ascii")
);
const erc20Abi = json.parse(
  fs.readFileSync("src/abis/ERC20.json").toString("ascii")
);

// Logger constants
const reset = "\x1b[0m";
const cyan = "\x1b[36m";
const yellow = "\x1b[33m";
const green = "\x1b[32m";
const magenta = "\x1b[35m";

// Contract call fn
export type RunnerConfigs = {
  createMarkets: boolean;
  setMarketParams: boolean;
  getMarketOwners: boolean;
  getTokenDecimals: boolean;
  getVaultTokens: boolean;
  getOwnerTokenBalances: boolean;
  getLPTokenBalances: boolean;
  getOwnerVaultTokenBalances: boolean;
  getLPVaultTokenBalances: boolean;
  depositInitialApprove: boolean;
  depositInitial: boolean;
  depositThirdPartyApprove: boolean;
  depositThirdParty: boolean;
  swap: boolean;
  withdraw: boolean;
};
const execute = async (configs: RunnerConfigs) => {
  // Define Starknet provider
  const provider = new RpcProvider({ nodeUrl: ENV.RPC_URL });

  // Define accounts
  const owner = new Account(provider, ENV.OWNER_ADDRESS, ENV.OWNER_PRIVATE_KEY);
  const lp = new Account(provider, ENV.LP_ADDRESS, ENV.LP_PRIVATE_KEY);

  // Connect to contract
  const solver = new Contract(
    replicatingSolverAbi,
    ENV.REPLICATING_SOLVER_ADDRESS,
    provider
  );
  solver.connect(owner);

  // Loop through markets and create them, setting params
  for (const market of INITIAL_MARKETS) {
    // Get market id
    const marketInfo = {
      base_token: market.base_token,
      quote_token: market.quote_token,
      owner: market.owner,
      is_public: market.is_public,
    };
    let marketId: string;
    try {
      marketId = await solver.market_id(marketInfo);
    } catch (e) {
      console.error(e);
      continue;
    }

    // Create market (disable if already created)
    if (configs.createMarkets) {
      console.log(
        `Creating ${market.base_symbol}-${market.quote_symbol} market...`
      );
      try {
        const res = await solver.create_market(marketInfo);
        await provider.waitForTransaction(res.transaction_hash);
        console.log(`✅ Created market`);
      } catch (e) {
        console.error(e);
        continue;
      }
    }

    // Get market owners
    if (configs.getMarketOwners) {
      try {
        const fetchedMarketInfo = await solver.market_info(marketId);
        console.log(
          `Market owner (${market.base_symbol}-${
            market.quote_symbol
          }): ${bigIntToAddress(fetchedMarketInfo.owner)}`
        );
      } catch (e) {
        console.error(e);
        continue;
      }
    }

    // Get token decimals
    if (configs.getTokenDecimals) {
      try {
        const baseTokenContract = new Contract(
          erc20Abi,
          market.base_token,
          provider
        );
        baseTokenContract.connect(owner);
        const baseDecimals = await baseTokenContract.decimals();

        const quoteTokenContract = new Contract(
          erc20Abi,
          market.quote_token,
          provider
        );
        quoteTokenContract.connect(owner);
        const quoteDecimals = await quoteTokenContract.decimals();

        console.log(
          `${market.base_symbol} decimals: ${yellow}${baseDecimals}${reset}, ${market.quote_symbol} decimals: ${yellow}${quoteDecimals}${reset}`
        );
      } catch (e) {
        console.error(e);
        continue;
      }
    }

    // Get LP token balances
    if (configs.getOwnerTokenBalances) {
      try {
        const msgBase = await getTokenBalance(
          provider,
          owner,
          market.base_token,
          market.base_symbol
        );
        const msgQuote = await getTokenBalance(
          provider,
          owner,
          market.quote_token,
          market.quote_symbol
        );
        console.log(`${msgBase}, ${msgQuote}`);
      } catch (e) {
        console.error(e);
        continue;
      }
    }

    // Get LP token balances
    if (configs.getLPTokenBalances) {
      try {
        const msgBase = await getTokenBalance(
          provider,
          lp,
          market.base_token,
          market.base_symbol
        );
        const msgQuote = await getTokenBalance(
          provider,
          lp,
          market.quote_token,
          market.quote_symbol
        );
        console.log(`${msgBase}, ${msgQuote}`);
      } catch (e) {
        console.error(e);
        continue;
      }
    }

    // Get vault tokens.
    if (configs.getVaultTokens) {
      try {
        const marketState = await solver.market_state(marketId);
        console.log(
          `Vault token ${market.base_symbol}-${
            market.quote_symbol
          }: ${green}${bigIntToAddress(marketState.vault_token)}${reset}`
        );
      } catch (e) {
        console.error(e);
        continue;
      }
    }

    // Get vault token balance for owner.
    if (configs.getOwnerVaultTokenBalances) {
      try {
        await getVaultTokenBalance(provider, owner, solver, marketId, "owner");
      } catch (e) {
        console.error(e);
        continue;
      }
    }
    // Get vault token balance for LP.
    if (configs.getLPVaultTokenBalances) {
      try {
        await getVaultTokenBalance(provider, lp, solver, marketId, "lp");
      } catch (e) {
        console.error(e);
        continue;
      }
    }

    // Set market params
    if (configs.setMarketParams) {
      console.log(
        `Setting ${market.base_symbol}-${market.quote_symbol} market params...`
      );
      try {
        const marketParams = {
          min_spread: market.min_spread,
          range: market.range,
          max_delta: market.max_delta,
          max_skew: market.max_skew,
          base_currency_id: market.base_currency_id,
          quote_currency_id: market.quote_currency_id,
          min_sources: market.min_sources,
          max_age: market.max_age,
        };
        const res = await solver.set_market_params(marketId, marketParams);
        await provider.waitForTransaction(res.transaction_hash);
        console.log(`✅ Set market params`);
      } catch (e) {
        console.error(e);
        continue;
      }
    }

    // Deposit initial liquidity
    if (configs.depositInitial) {
      console.log(
        `Depositing initial liquidity into ${market.base_symbol}-${market.quote_symbol} market...`
      );
      try {
        if (configs.depositInitialApprove) {
          // Approve spend.
          await approve(
            provider,
            owner,
            market.base_token,
            market.base_symbol,
            ENV.REPLICATING_SOLVER_ADDRESS,
            market.base_deposit_initial
          );
          await approve(
            provider,
            owner,
            market.quote_token,
            market.quote_symbol,
            ENV.REPLICATING_SOLVER_ADDRESS,
            market.quote_deposit_initial
          );
        }
        // Deposit tokens.
        const res = await solver.deposit_initial(
          marketId,
          market.base_deposit_initial,
          market.quote_deposit_initial
        );
        await provider.waitForTransaction(res.transaction_hash);
        console.log(
          `✅ Deposited ${market.base_deposit_initial} ${market.base_symbol} and ${market.quote_deposit_initial} ${market.quote_symbol}`
        );
      } catch (e) {
        console.error(e);
        continue;
      }
    }

    // Deposit 3rd party liquidity
    if (configs.depositThirdParty) {
      console.log(
        `Depositing 3rd party liquidity into ${market.base_symbol}-${market.quote_symbol} market...`
      );
      try {
        if (configs.depositThirdPartyApprove) {
          // Approve spend.
          await approve(
            provider,
            lp,
            market.base_token,
            market.base_symbol,
            ENV.REPLICATING_SOLVER_ADDRESS,
            market.base_deposit
          );
          await approve(
            provider,
            lp,
            market.quote_token,
            market.quote_symbol,
            ENV.REPLICATING_SOLVER_ADDRESS,
            market.quote_deposit
          );
        }
        // Deposit tokens.
        solver.connect(lp);
        const res = await solver.deposit(
          marketId,
          market.base_deposit,
          market.quote_deposit
        );
        await provider.waitForTransaction(res.transaction_hash);
        console.log(
          `✅ Deposited ${market.base_deposit} ${market.base_symbol} and ${market.quote_deposit} ${market.quote_symbol}`
        );
      } catch (e) {
        console.error(e);
        continue;
      }
    }
  }
};

const approve = async (
  provider: RpcProvider,
  account: Account,
  tokenAddress: string,
  tokenSymbol: string,
  spender: string,
  amount: string
) => {
  const tokenContract = new Contract(erc20Abi, tokenAddress, provider);
  tokenContract.connect(account);
  const decimals = await tokenContract.decimals();
  const res = await tokenContract.approve(spender, amount);
  await provider.waitForTransaction(res.transaction_hash);
  console.log(
    `✅ Approved ${green}${shortenAddress(
      bigIntToAddress(spender)
    )}${reset} for ${yellow}${toDecimals(
      amount,
      BigInt(decimals).toString(10)
    )} ${tokenSymbol}${reset}`
  );
};

const getVaultTokenBalance = async (
  provider: RpcProvider,
  account: Account,
  solver: Contract,
  marketId: string,
  userSlug?: string
) => {
  const marketState = await solver.market_state(marketId);
  const vaultToken = new Contract(
    erc20Abi,
    bigIntToAddress(marketState.vault_token),
    provider
  );
  vaultToken.connect(account);
  const balance = await vaultToken.balanceOf(account.address);
  const decimals = await vaultToken.decimals();
  const symbol = await vaultToken.symbol();
  console.log(
    `${green} ${symbol} [${userSlug ?? "User"}: ${shortenAddress(
      account.address
    )}]${reset}: ${yellow}${toDecimals(
      BigInt(balance).toString(10),
      BigInt(decimals).toString(10)
    )}${reset}`
  );
};

const getTokenBalance = async (
  provider: RpcProvider,
  account: Account,
  tokenAddress: string,
  tokenSymbol: string
) => {
  const tokenContract = new Contract(erc20Abi, tokenAddress, provider);
  tokenContract.connect(account);
  const balance = await tokenContract.balanceOf(account.address);
  const decimals = await tokenContract.decimals();
  return `${tokenSymbol} balance ${green}[User: ${shortenAddress(
    account.address
  )}]${reset}: ${yellow}${toDecimals(
    BigInt(balance).toString(10),
    BigInt(decimals).toString(10)
  )}${reset}`;
};

// Execute steps.
execute({
  createMarkets: false,
  setMarketParams: false,
  getMarketOwners: false,
  getTokenDecimals: false,
  getOwnerTokenBalances: true,
  getLPTokenBalances: true,
  getVaultTokens: true,
  getOwnerVaultTokenBalances: true,
  getLPVaultTokenBalances: true,
  depositInitialApprove: false,
  depositInitial: false,
  depositThirdPartyApprove: false,
  depositThirdParty: false,
  swap: false,
  withdraw: false,
});
