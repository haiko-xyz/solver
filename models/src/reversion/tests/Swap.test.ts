import Decimal from "decimal.js";
import { getSwapAmounts } from "../libraries/SwapLib";
import {
  getVirtualPosition,
  getVirtualPositionRange,
} from "../libraries/SpreadMath";
import { Trend } from "../types";

const reset = "\x1b[0m";
const green = "\x1b[32m";

type Case = {
  description: string;
  oraclePrice: Decimal.Value;
  baseReserves: Decimal.Value;
  quoteReserves: Decimal.Value;
  feeRate: Decimal.Value;
  range: Decimal.Value;
  amount: Decimal.Value;
  thresholdSqrtPrice: Decimal.Value | null;
  thresholdAmount: Decimal.Value | null;
  swapCasesOverride?: SwapCase[];
  trendCasesOverride?: Trend[];
};

type SwapCase = {
  isBuy: boolean;
  exactInput: boolean;
};

const getSwapCases = (): SwapCase[] => {
  const swapCases: SwapCase[] = [
    {
      isBuy: true,
      exactInput: true,
    },
    {
      isBuy: false,
      exactInput: true,
    },
    {
      isBuy: true,
      exactInput: false,
    },
    {
      isBuy: false,
      exactInput: false,
    },
  ];
  return swapCases;
};

const testSwapCases = () => {
  const cases: Case[] = [
    {
      description: "1) Full range liq, price 1, 0% fee",
      oraclePrice: 1,
      baseReserves: 1000,
      quoteReserves: 1000,
      feeRate: 0,
      range: 7906625,
      amount: 100,
      thresholdSqrtPrice: null,
      thresholdAmount: null,
    },
    {
      description: "2) Full range liq, price 0.1, 0% fee",
      oraclePrice: 0.1,
      baseReserves: 100,
      quoteReserves: 1000,
      feeRate: 0,
      range: 7676365,
      amount: 10,
      thresholdSqrtPrice: null,
      thresholdAmount: null,
    },
    {
      description: "3) Full range liq, price 10, 0% fee",
      oraclePrice: 10,
      baseReserves: 1000,
      quoteReserves: 100,
      feeRate: 0,
      range: 7676365,
      amount: 100,
      thresholdSqrtPrice: null,
      thresholdAmount: null,
    },
    {
      description: "4) Concentrated liq, price 1, 0% fee",
      oraclePrice: 1,
      baseReserves: 1000,
      quoteReserves: 1000,
      feeRate: 0,
      range: 5000,
      amount: 100,
      thresholdSqrtPrice: null,
      thresholdAmount: null,
    },
    {
      description: "5) Concentrated liq, price 1, 1% fee",
      oraclePrice: 1,
      baseReserves: 1000,
      quoteReserves: 1000,
      feeRate: 0.01,
      range: 5000,
      amount: 100,
      thresholdSqrtPrice: null,
      thresholdAmount: null,
    },
    {
      description: "6) Concentrated liq, price 10, 50% fee",
      oraclePrice: 10,
      baseReserves: 1000,
      quoteReserves: 1000,
      feeRate: 0.5,
      range: 5000,
      amount: 100,
      thresholdSqrtPrice: null,
      thresholdAmount: null,
    },
    {
      description: "7) Swap with liquidity exhausted",
      oraclePrice: 1,
      baseReserves: 100,
      quoteReserves: 100,
      feeRate: 0.01,
      range: 5000,
      amount: 200,
      thresholdSqrtPrice: null,
      thresholdAmount: null,
    },
    {
      description: "8) Swap with high oracle price",
      oraclePrice: 1000000000000000,
      baseReserves: 1000,
      quoteReserves: 1000,
      feeRate: 0.01,
      range: 5000,
      amount: 100,
      thresholdSqrtPrice: null,
      thresholdAmount: null,
    },
    {
      description: "9) Swap with low oracle price",
      oraclePrice: "0.00000001",
      baseReserves: 1000,
      quoteReserves: 1000,
      feeRate: 0.01,
      range: 5000,
      amount: 100,
      thresholdSqrtPrice: null,
      thresholdAmount: null,
    },
    {
      description: "10) Swap buy capped at threshold price",
      oraclePrice: 1,
      baseReserves: 100,
      quoteReserves: 100,
      feeRate: 0.01,
      range: 50000,
      amount: 50,
      thresholdSqrtPrice: "1.0488088481701515469914535136",
      thresholdAmount: null,
      swapCasesOverride: [
        {
          isBuy: true,
          exactInput: true,
        },
        {
          isBuy: true,
          exactInput: false,
        },
      ],
    },
    {
      description: "11) Swap sell capped at threshold price",
      oraclePrice: 1,
      baseReserves: 100,
      quoteReserves: 100,
      feeRate: 0.01,
      range: 50000,
      amount: 50,
      thresholdSqrtPrice: "0.9486832980505137995996680633",
      thresholdAmount: null,
      swapCasesOverride: [
        {
          isBuy: false,
          exactInput: true,
        },
        {
          isBuy: false,
          exactInput: false,
        },
      ],
    },
    {
      description: "12) Swap exact in with threshold amount",
      oraclePrice: 1,
      baseReserves: 1000,
      quoteReserves: 1000,
      feeRate: 0.01,
      range: 5000,
      amount: 100,
      thresholdSqrtPrice: null,
      thresholdAmount: "0.99650000000000000000",
      swapCasesOverride: [
        {
          isBuy: true,
          exactInput: true,
        },
        {
          isBuy: false,
          exactInput: true,
        },
      ],
    },
    {
      description: "13) Swap exact out with threshold amount",
      oraclePrice: 1,
      baseReserves: 1000,
      quoteReserves: 1000,
      feeRate: 0.01,
      range: 5000,
      amount: 100,
      thresholdSqrtPrice: null,
      thresholdAmount: "102",
      swapCasesOverride: [
        {
          isBuy: true,
          exactInput: false,
        },
        {
          isBuy: false,
          exactInput: false,
        },
      ],
    },
  ];

  for (let i = 0; i < cases.length; i++) {
    const {
      description,
      oraclePrice,
      baseReserves,
      quoteReserves,
      feeRate,
      range,
      amount,
      thresholdSqrtPrice,
      thresholdAmount,
      swapCasesOverride,
      trendCasesOverride,
    } = cases[i];

    const baseDecimals = 18;
    const quoteDecimals = 18;

    console.log(`Test Case ${description}`);

    // Loop through swap cases
    const swapCases = swapCasesOverride ?? getSwapCases();
    let j = 0;
    for (const { isBuy, exactInput } of swapCases) {
      console.log(
        `  Swap Case ${j + 1}) isBuy: ${isBuy}, exactInput: ${exactInput}`
      );
      const { bidLower, bidUpper, askLower, askUpper } =
        getVirtualPositionRange(Trend.Range, range, 0, oraclePrice);
      const { lowerSqrtPrice, upperSqrtPrice, liquidity } = getVirtualPosition(
        !isBuy,
        isBuy ? askLower : bidLower,
        isBuy ? askUpper : bidUpper,
        isBuy ? baseReserves : quoteReserves
      );
      const { amountIn, amountOut, fees } = getSwapAmounts({
        isBuy,
        exactInput,
        amount,
        swapFeeRate: feeRate,
        thresholdSqrtPrice,
        thresholdAmount,
        lowerSqrtPrice,
        upperSqrtPrice,
        liquidity,
        baseDecimals,
        quoteDecimals,
      });
      console.log(
        `    amountIn: ${green}${new Decimal(amountIn)
          .mul(1e18)
          .toFixed(0)}${reset}, amountOut: ${green}${new Decimal(amountOut)
          .mul(1e18)
          .toFixed(0)}${reset}, fees: ${green}${new Decimal(fees)
          .mul(1e18)
          .toFixed(0)}${reset}`
      );
      j++;
    }
  }
};

console.log("testing");
testSwapCases();
