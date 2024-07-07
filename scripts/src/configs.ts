import { toFixed } from "./utils";
import { ENV } from "./env";
import { CairoOption, CairoOptionVariant, Uint256 } from "starknet";

// Pragma oracle currency ids
const ETH_CURR_ID = "4543560";
const STRK_CURR_ID = "1398035019";
const USDC_CURR_ID = "1431520323";
const USDT_CURR_ID = "1431520340";
const DPI_CURR_ID = "4477001";

export type RunnerMarketParams = {
  base_symbol: string;
  quote_symbol: string;
  base_token: string;
  quote_token: string;
  owner: string;
  is_public: boolean;
  min_spread: number;
  range: number;
  max_delta: number;
  max_skew: number;
  base_currency_id: string;
  quote_currency_id: string;
  min_sources: number;
  max_age: number;
  base_deposit_initial: string;
  quote_deposit_initial: string;
  base_deposit: string;
  quote_deposit: string;
  swaps: SwapParams[];
  withdraw_public_proportion: number;
};

type SwapParams = {
  is_buy: boolean;
  amount: string;
  exact_input: boolean;
  threshold_sqrt_price: CairoOption<Uint256>;
  threshold_amount: CairoOption<Uint256>;
};

// Define list of markets to create
export const MARKET_PARAMS: RunnerMarketParams[] = [
  {
    base_symbol: "ETH",
    quote_symbol: "USDC",
    base_token: ENV.ETH_ADDRESS,
    quote_token: ENV.USDC_ADDRESS,
    owner: ENV.OWNER_ADDRESS,
    is_public: true,
    min_spread: 25,
    range: 5000,
    max_delta: 500,
    max_skew: 5000,
    base_currency_id: ETH_CURR_ID,
    quote_currency_id: USDC_CURR_ID,
    min_sources: 3,
    max_age: 600,
    base_deposit_initial: toFixed(10, 18),
    quote_deposit_initial: toFixed(10000, 6),
    base_deposit: toFixed(1, 18),
    quote_deposit: toFixed(1000, 6),
    swaps: [
      {
        is_buy: true,
        exact_input: true,
        amount: toFixed(500, 6),
        threshold_amount: new CairoOption(CairoOptionVariant.None),
        threshold_sqrt_price: new CairoOption(CairoOptionVariant.None),
      },
    ],
    withdraw_public_proportion: 0.5,
  },
  {
    base_symbol: "STRK",
    quote_symbol: "USDC",
    base_token: ENV.STRK_ADDRESS,
    quote_token: ENV.USDC_ADDRESS,
    owner: ENV.OWNER_ADDRESS,
    is_public: true,
    min_spread: 25,
    range: 5000,
    max_delta: 500,
    max_skew: 5000,
    base_currency_id: STRK_CURR_ID,
    quote_currency_id: USDC_CURR_ID,
    min_sources: 3,
    max_age: 1000,
    base_deposit_initial: toFixed(20000, 18),
    quote_deposit_initial: toFixed(10000, 6),
    base_deposit: toFixed(20000, 18),
    quote_deposit: toFixed(10000, 6),
    swaps: [
      {
        is_buy: false,
        exact_input: true,
        amount: toFixed(1000, 18),
        threshold_amount: new CairoOption(CairoOptionVariant.None),
        threshold_sqrt_price: new CairoOption(CairoOptionVariant.None),
      },
    ],
    withdraw_public_proportion: 0.5,
  },
  {
    base_symbol: "STRK",
    quote_symbol: "ETH",
    base_token: ENV.STRK_ADDRESS,
    quote_token: ENV.ETH_ADDRESS,
    owner: ENV.OWNER_ADDRESS,
    is_public: true,
    min_spread: 25,
    range: 5000,
    max_delta: 500,
    max_skew: 5000,
    base_currency_id: STRK_CURR_ID,
    quote_currency_id: ETH_CURR_ID,
    min_sources: 3,
    max_age: 1000,
    base_deposit_initial: toFixed(20000, 18),
    quote_deposit_initial: toFixed(10, 18),
    base_deposit: toFixed(40000, 18),
    quote_deposit: toFixed(20, 18),
    swaps: [
      {
        is_buy: false,
        exact_input: false,
        amount: toFixed(1, 18),
        threshold_amount: new CairoOption(CairoOptionVariant.None),
        threshold_sqrt_price: new CairoOption(CairoOptionVariant.None),
      },
    ],
    withdraw_public_proportion: 0.5,
  },
  {
    base_symbol: "USDC",
    quote_symbol: "USDT",
    base_token: ENV.USDC_ADDRESS,
    quote_token: ENV.USDT_ADDRESS,
    owner: ENV.OWNER_ADDRESS,
    is_public: true,
    min_spread: 5,
    range: 100,
    max_delta: 0,
    max_skew: 5000,
    base_currency_id: USDC_CURR_ID,
    quote_currency_id: USDT_CURR_ID,
    min_sources: 3,
    max_age: 600,
    base_deposit_initial: toFixed(15000, 6),
    quote_deposit_initial: toFixed(15000, 8),
    base_deposit: toFixed(1000, 6),
    quote_deposit: toFixed(1000, 8),
    swaps: [
      {
        is_buy: true,
        exact_input: false,
        amount: toFixed(1000, 6),
        threshold_amount: new CairoOption(CairoOptionVariant.None),
        threshold_sqrt_price: new CairoOption(CairoOptionVariant.None),
      },
    ],
    withdraw_public_proportion: 0.5,
  },
  {
    base_symbol: "DPI",
    quote_symbol: "USDC",
    base_token: ENV.DPI_ADDRESS,
    quote_token: ENV.USDC_ADDRESS,
    owner: ENV.OWNER_ADDRESS,
    is_public: true,
    min_spread: 25,
    range: 5000,
    max_delta: 500,
    max_skew: 5000,
    base_currency_id: DPI_CURR_ID,
    quote_currency_id: USDC_CURR_ID,
    min_sources: 3,
    max_age: 600,
    base_deposit_initial: toFixed(100, 18),
    quote_deposit_initial: toFixed(10, 6),
    base_deposit: toFixed(1000, 18),
    quote_deposit: toFixed(100, 6),
    swaps: [
      {
        is_buy: true,
        exact_input: true,
        amount: toFixed(50, 6),
        threshold_amount: new CairoOption(CairoOptionVariant.None),
        threshold_sqrt_price: new CairoOption(CairoOptionVariant.None),
      },
    ],
    withdraw_public_proportion: 0.5,
  },
];
