////////////////////////////////
// Imports
////////////////////////////////

import fs from "fs";
import { RpcProvider, Account, Contract, json } from "starknet";
import dotenv from "dotenv";
import {
  bigIntToAddress,
  mul,
  round,
  shortenAddress,
  toDecimals,
} from "./utils";
dotenv.config();

import { ENV } from "./env";
import { MARKET_PARAMS } from "./configs";

const replicatingSolverAbi = json.parse(
  fs.readFileSync("src/abis/ReplicatingSolver.json").toString("ascii")
);
const erc20Abi = json.parse(
  fs.readFileSync("src/abis/ERC20.json").toString("ascii")
);

////////////////////////////////
// Constants
////////////////////////////////

// For logging
const reset = "\x1b[0m";
const cyan = "\x1b[36m";
const yellow = "\x1b[33m";
const green = "\x1b[32m";
const magenta = "\x1b[35m";

////////////////////////////////
// Functions
////////////////////////////////

type RunnerConfigs = {
  createMarkets: boolean;
  setMarketParams: boolean;
  getMarketIds: boolean;
  getMarketOwners: boolean;
  getTokenDecimals: boolean;
  getVaultTokens: boolean;
  getOwnerTokenBalances: boolean;
  getLPTokenBalances: boolean;
  getOwnerVaultTokenBalances: boolean;
  getLPVaultTokenBalances: boolean;
  getDeposits: boolean;
  depositInitialApprove: boolean;
  depositInitial: boolean;
  depositThirdPartyApprove: boolean;
  depositThirdParty: boolean;
  depositThirdPartyReferral: boolean;
  quote: boolean;
  swap: boolean;
  withdrawPublic: boolean;
  withdrawPrivate: boolean;
  pause: boolean;
  unpause: boolean;
  setWithdrawFee: boolean;
};

type MarketInfo = {
  base_token: string;
  quote_token: string;
  owner: string;
  is_public: boolean;
};

// Contract call fn
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

  // Loop through markets
  for (const market of MARKET_PARAMS) {
    // Define market info
    const marketInfo: MarketInfo = {
      base_token: market.base_token,
      quote_token: market.quote_token,
      owner: market.owner,
      is_public: market.is_public,
    };

    // Get market id
    let marketId: string;
    try {
      marketId = await solver.market_id(marketInfo);
    } catch (e) {
      console.error(e);
      continue;
    }

    // Print market ids
    if (configs.getMarketIds) {
      console.log(
        `Market ID (${market.base_symbol}-${
          market.quote_symbol
        }): ${green}${bigIntToAddress(marketId)}${reset}`
      );
    }

    // Create markets
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
        const baseDecimals = await getTokenDecimals(
          provider,
          owner,
          market.base_token
        );
        const quoteDecimals = await getTokenDecimals(
          provider,
          owner,
          market.quote_token
        );
        console.log(
          `${market.base_symbol} decimals: ${yellow}${baseDecimals}${reset}, ${market.quote_symbol} decimals: ${yellow}${quoteDecimals}${reset}`
        );
      } catch (e) {
        console.error(e);
        continue;
      }
    }

    // Get owner token balances
    if (configs.getOwnerTokenBalances) {
      console.log(
        `Getting owner token balances for ${market.base_symbol}-${market.quote_symbol} market...`
      );
      try {
        const { balance: baseBalance, decimals: baseDecimals } =
          await getTokenBalance(provider, owner, market.base_token);
        const { balance: quoteBalance, decimals: quoteDecimals } =
          await getTokenBalance(provider, owner, market.quote_token);
        logBalance(
          market.base_symbol,
          owner.address,
          baseBalance,
          baseDecimals
        );
        logBalance(
          market.quote_symbol,
          owner.address,
          quoteBalance,
          quoteDecimals
        );
      } catch (e) {
        console.error(e);
        continue;
      }
    }

    // Get LP token balances
    if (configs.getLPTokenBalances) {
      console.log(
        `Getting LP token balances for ${market.base_symbol}-${market.quote_symbol} market...`
      );
      try {
        const { balance: baseBalance, decimals: baseDecimals } =
          await getTokenBalance(provider, lp, market.base_token);
        const { balance: quoteBalance, decimals: quoteDecimals } =
          await getTokenBalance(provider, lp, market.quote_token);
        logBalance(market.base_symbol, lp.address, baseBalance, baseDecimals);
        logBalance(
          market.quote_symbol,
          lp.address,
          quoteBalance,
          quoteDecimals
        );
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
      console.log(
        `Getting owner vault token balances for ${market.base_symbol}-${market.quote_symbol} market...`
      );
      try {
        const { balance, decimals, symbol } = await getVaultTokenBalance(
          provider,
          owner,
          solver,
          marketId
        );
        logBalance(symbol, owner.address, balance, decimals, "owner");
      } catch (e) {
        console.error(e);
        continue;
      }
    }
    // Get vault token balance for LP.
    if (configs.getLPVaultTokenBalances) {
      console.log(
        `Getting LP vault token balances for ${market.base_symbol}-${market.quote_symbol} market...`
      );
      try {
        const { balance, decimals, symbol } = await getVaultTokenBalance(
          provider,
          lp,
          solver,
          marketId
        );
        logBalance(symbol, lp.address, balance, decimals, "lp");
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

    // Get deposits
    if (configs.getDeposits) {
      console.log(
        `Getting user deposits for ${market.base_symbol}-${market.quote_symbol} market...`
      );
      try {
        // Get decimals.
        const baseDecimals = await getTokenDecimals(
          provider,
          owner,
          market.base_token
        );
        const quoteDecimals = await getTokenDecimals(
          provider,
          owner,
          market.quote_token
        );
        // Query user balances
        const res = (await solver.get_user_balances_array(
          [owner.address, lp.address],
          [marketId, marketId]
        )) as { 0: bigint; 1: bigint; 2: bigint; 3: bigint }[];
        const ownerBaseAmount = toDecimals(
          BigInt(res[0]["0"]).toString(10),
          baseDecimals
        );
        const ownerQuoteAmount = toDecimals(
          BigInt(res[0]["1"]).toString(10),
          quoteDecimals
        );
        const ownerShares = toDecimals(BigInt(res[0]["2"]).toString(10), 18);
        const totalShares = toDecimals(BigInt(res[0]["3"]).toString(10), 18);
        const lpBaseAmount = toDecimals(
          BigInt(res[1]["0"]).toString(10),
          baseDecimals
        );
        const lpQuoteAmount = toDecimals(
          BigInt(res[1]["1"]).toString(10),
          quoteDecimals
        );
        const lpShares = toDecimals(BigInt(res[1]["2"]).toString(10), 18);
        const ownerShare =
          Number(totalShares) === 0
            ? 0
            : Math.round((Number(ownerShares) / Number(totalShares)) * 100);
        const lpShare =
          Number(totalShares) === 0
            ? 0
            : Math.round((Number(lpShares) / Number(totalShares)) * 100);
        // Log balances.
        console.log(
          `    Owner deposits: ${yellow}${ownerBaseAmount}${reset} ${market.base_symbol}, ${yellow}${ownerQuoteAmount}${reset} ${market.quote_symbol}`
        );
        console.log(
          `    Owner shares: ${yellow}${ownerShares}${reset} / ${yellow}${totalShares}${reset} (${green}${ownerShare}%${reset})`
        );
        console.log(
          `    LP deposits: ${yellow}${lpBaseAmount}${reset} ${market.base_symbol}, ${yellow}${lpQuoteAmount}${reset} ${market.quote_symbol}`
        );
        console.log(
          `    LP shares: ${yellow}${lpShares}${reset} / ${yellow}${totalShares}${reset} (${green}${lpShare}%${reset})`
        );
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
          `    ✅ Deposited ${market.base_deposit_initial} ${market.base_symbol} and ${market.quote_deposit_initial} ${market.quote_symbol}`
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
          `    ✅ Deposited ${market.base_deposit} ${market.base_symbol} and ${market.quote_deposit} ${market.quote_symbol}`
        );
      } catch (e) {
        console.error(e);
        continue;
      }
    }

    // Deposit 3rd party liquidity with referral
    if (configs.depositThirdPartyReferral) {
      console.log(
        `Depositing 3rd party liquidity with referrer into ${market.base_symbol}-${market.quote_symbol} market...`
      );
      try {
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
        // Deposit tokens with referrer.
        solver.connect(lp);
        const referrer = ENV.OWNER_ADDRESS;
        const res = await solver.deposit_with_referrer(
          marketId,
          market.base_deposit,
          market.quote_deposit,
          referrer
        );
        await provider.waitForTransaction(res.transaction_hash);
        console.log(
          `    ✅ Deposited ${yellow}${market.base_deposit} ${
            market.base_symbol
          }${reset} and ${yellow}${market.quote_deposit} ${
            market.quote_symbol
          }${reset} with referrer ${green}${shortenAddress(referrer)}${reset}`
        );
      } catch (e) {
        console.error(e);
        continue;
      }
    }

    // Swap quote
    if (configs.quote) {
      for (const swap of market.swaps) {
        const inSymbol = swap.is_buy ? market.quote_symbol : market.base_symbol;
        const outSymbol = swap.is_buy
          ? market.base_symbol
          : market.quote_symbol;
        const baseDecimals = await getTokenDecimals(
          provider,
          owner,
          market.base_token
        );
        const quoteDecimals = await getTokenDecimals(
          provider,
          owner,
          market.quote_token
        );
        const inDecimals = swap.is_buy ? quoteDecimals : baseDecimals;
        const outDecimals = swap.is_buy ? baseDecimals : quoteDecimals;
        try {
          const res = await solver.quote(marketId, swap);
          const amountIn = BigInt(res["0"]).toString(10);
          const amountOut = BigInt(res["1"]).toString(10);
          console.log(
            `Quote: ${yellow}${toDecimals(
              amountIn,
              inDecimals
            )}${reset} ${inSymbol} = ${yellow}${toDecimals(
              amountOut,
              outDecimals
            )}${reset} ${outSymbol}`
          );
        } catch (e) {
          console.error(e);
          continue;
        }
      }
    }

    // Swap
    if (configs.swap) {
      for (const swap of market.swaps) {
        const baseDecimals = await getTokenDecimals(
          provider,
          owner,
          market.base_token
        );
        const quoteDecimals = await getTokenDecimals(
          provider,
          owner,
          market.quote_token
        );
        const inDecimals = swap.is_buy ? quoteDecimals : baseDecimals;
        const outDecimals = swap.is_buy ? baseDecimals : quoteDecimals;
        const inToken = swap.is_buy ? market.quote_token : market.base_token;
        const inSymbol = swap.is_buy ? market.quote_symbol : market.base_symbol;
        const outSymbol = swap.is_buy
          ? market.base_symbol
          : market.quote_symbol;
        console.log(
          `Swapping ${toDecimals(
            swap.amount,
            inDecimals
          )} ${inSymbol} for ${outSymbol}...`
        );
        try {
          // Approve spend.
          await approve(
            provider,
            owner,
            inToken,
            inSymbol,
            ENV.REPLICATING_SOLVER_ADDRESS,
            swap.amount
          );
          // Swap tokens.
          solver.connect(owner);
          const res = await solver.swap(marketId, swap);
          const receipt = (await provider.waitForTransaction(
            res.transaction_hash
          )) as {
            events: {
              data: [string, string, string, string, string, string];
            }[];
          };
          const amountIn = (
            BigInt(receipt.events[3].data[2]) +
            BigInt(receipt.events[3].data[3]) * BigInt(2 ** 128)
          ).toString(10);
          const amountOut = (
            BigInt(receipt.events[3].data[4]) +
            BigInt(receipt.events[3].data[5]) * BigInt(2 ** 128)
          ).toString(10);
          console.log(
            `    ✅ Swapped ${yellow}${toDecimals(
              amountIn,
              inDecimals
            )}${reset} ${inSymbol} for ${yellow}${toDecimals(
              amountOut,
              outDecimals
            )}${reset} ${outSymbol}`
          );
        } catch (e) {
          console.error(e);
          continue;
        }
      }
    }

    // Withdraw
    if (configs.withdrawPublic) {
      try {
        // Get vault token shares.
        const { balance } = await getVaultTokenBalance(
          provider,
          lp,
          solver,
          marketId
        );
        const sharesToWithdraw = round(
          mul(balance, market.withdraw_public_proportion)
        );
        console.log(
          `Withdrawing ${sharesToWithdraw} shares from ${market.base_symbol}-${market.quote_symbol} market...`
        );

        // Withdraw tokens.
        const res = await solver.withdraw_public(marketId, sharesToWithdraw);
        const receipt = (await provider.waitForTransaction(
          res.transaction_hash
        )) as {
          events: {
            data: [string, string, string, string, string, string];
          }[];
        };
        const baseAmount = (
          BigInt(receipt.events[3].data[0]) +
          BigInt(receipt.events[3].data[1]) * BigInt(2 ** 128)
        ).toString(10);
        const quoteAmount = (
          BigInt(receipt.events[3].data[2]) +
          BigInt(receipt.events[3].data[3]) * BigInt(2 ** 128)
        ).toString(10);
        const shares = (
          BigInt(receipt.events[3].data[4]) +
          BigInt(receipt.events[3].data[5]) * BigInt(2 ** 128)
        ).toString(10);
        const baseDecimals = await getTokenDecimals(
          provider,
          lp,
          market.base_token
        );
        const quoteDecimals = await getTokenDecimals(
          provider,
          lp,
          market.quote_token
        );
        console.log(
          `    ✅ Withdrew ${yellow}${toDecimals(baseAmount, baseDecimals)} ${
            market.base_symbol
          }${reset} and ${yellow}${toDecimals(quoteAmount, quoteDecimals)} ${
            market.quote_symbol
          }${reset} (shares: ${yellow}${shares}${reset})`
        );
      } catch (e) {
        console.error(e);
        continue;
      }
    }

    // Pause
    if (configs.pause) {
      console.log(
        `Pausing ${market.base_symbol}-${market.quote_symbol} market...`
      );
      try {
        const res = await solver.pause(marketId);
        await provider.waitForTransaction(res.transaction_hash);
        console.log(`✅ Paused market`);
      } catch (e) {
        console.error(e);
        continue;
      }
    }

    // Unpause
    if (configs.unpause) {
      console.log(
        `Unpausing ${market.base_symbol}-${market.quote_symbol} market...`
      );
      try {
        const res = await solver.unpause(marketId);
        await provider.waitForTransaction(res.transaction_hash);
        console.log(`✅ Unpaused market`);
      } catch (e) {
        console.error(e);
        continue;
      }
    }

    // Set withdraw fee
    if (configs.setWithdrawFee) {
      console.log(
        `Setting withdraw fee for ${market.base_symbol}-${market.quote_symbol} market...`
      );
      try {
        const res = await solver.set_withdraw_fee(
          marketId,
          market.withdraw_fee_rate
        );
        await provider.waitForTransaction(res.transaction_hash);
        console.log(
          `✅ Set withdraw fee to ${market.withdraw_fee_rate / 100}%`
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
    `    ✅ Approved ${green}${shortenAddress(
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
  marketId: string
): Promise<{ balance: string; decimals: string; symbol: string }> => {
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
  return {
    balance: BigInt(balance).toString(10),
    decimals: BigInt(decimals).toString(10),
    symbol,
  };
};

const getTokenBalance = async (
  provider: RpcProvider,
  account: Account,
  tokenAddress: string
) => {
  const tokenContract = new Contract(erc20Abi, tokenAddress, provider);
  tokenContract.connect(account);
  const balance = await tokenContract.balanceOf(account.address);
  const decimals = await tokenContract.decimals();
  return { balance, decimals };
};

const getTokenDecimals = async (
  provider: RpcProvider,
  user: Account,
  tokenAddress: string
) => {
  const tokenContract = new Contract(erc20Abi, tokenAddress, provider);
  tokenContract.connect(user);
  const decimals = await tokenContract.decimals();
  return BigInt(decimals).toString(10);
};

const logBalance = (
  symbol: string,
  userAddress: string,
  balance: string,
  decimals: string,
  userSlug?: string
) => {
  console.log(
    `    ${green} ${symbol} [${userSlug ?? "User"}: ${shortenAddress(
      userAddress
    )}]${reset}: ${yellow}${toDecimals(
      BigInt(balance).toString(10),
      BigInt(decimals).toString(10)
    )}${reset}`
  );
};

////////////////////////////////
// Run
////////////////////////////////

execute({
  createMarkets: false,
  setMarketParams: false,
  getMarketIds: false,
  getMarketOwners: false,
  getTokenDecimals: false,
  getOwnerTokenBalances: false,
  getLPTokenBalances: false,
  getVaultTokens: false,
  getOwnerVaultTokenBalances: false,
  getLPVaultTokenBalances: false,
  getDeposits: false,
  depositInitialApprove: false,
  depositInitial: false,
  depositThirdPartyApprove: false,
  depositThirdParty: false,
  depositThirdPartyReferral: false,
  quote: false,
  swap: false,
  withdrawPublic: true,
  withdrawPrivate: false,
  pause: false,
  unpause: false,
  setWithdrawFee: false,
});
