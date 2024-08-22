import Decimal from "decimal.js";
import {
  getDelta,
  getVirtualPosition,
  getVirtualPositionRange,
} from "../../src/libraries/SpreadMath";
import { getSwapAmounts } from "../../src/libraries/SwapLib";

type Case = {
  description: string;
  oraclePrice: Decimal.Value;
  baseReserves: Decimal.Value;
  quoteReserves: Decimal.Value;
  minSpread: Decimal.Value;
  range: Decimal.Value;
  maxDelta: Decimal.Value;
  maxSkew: Decimal.Value;
  amount: Decimal.Value;
  thresholdSqrtPrice: Decimal.Value | null;
  thresholdAmount: Decimal.Value | null;
  swapCasesOverride?: SwapCase[];
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
      description: "1) Full range liq, price 1, no spread",
      oraclePrice: 1,
      baseReserves: 1000,
      quoteReserves: 1000,
      minSpread: 0,
      range: 7906625,
      maxDelta: 0,
      maxSkew: 0,
      amount: 100,
      thresholdSqrtPrice: null,
      thresholdAmount: null,
    },
    {
      description: "2) Full range liq, price 0.1, no spread",
      oraclePrice: 0.1,
      baseReserves: 100,
      quoteReserves: 1000,
      minSpread: 0,
      range: 7676365,
      maxDelta: 0,
      maxSkew: 0,
      amount: 10,
      thresholdSqrtPrice: null,
      thresholdAmount: null,
    },
    {
      description: "3) Full range liq, price 10, no spread",
      oraclePrice: 10,
      baseReserves: 1000,
      quoteReserves: 100,
      minSpread: 0,
      range: 7676365,
      maxDelta: 0,
      maxSkew: 0,
      amount: 100,
      thresholdSqrtPrice: null,
      thresholdAmount: null,
    },
    {
      description: "4) Concentrated liq, price 1, no spread",
      oraclePrice: 1,
      baseReserves: 1000,
      quoteReserves: 1000,
      minSpread: 0,
      range: 5000,
      maxDelta: 0,
      maxSkew: 0,
      amount: 100,
      thresholdSqrtPrice: null,
      thresholdAmount: null,
    },
    {
      description: "5) Concentrated liq, price 1, 100 spread",
      oraclePrice: 1,
      baseReserves: 1000,
      quoteReserves: 1000,
      minSpread: 100,
      range: 5000,
      maxDelta: 0,
      maxSkew: 0,
      amount: 100,
      thresholdSqrtPrice: null,
      thresholdAmount: null,
    },
    {
      description: "6) Concentrated liq, price 10, 50000 spread",
      oraclePrice: 10,
      baseReserves: 1000,
      quoteReserves: 1000,
      minSpread: 50000,
      range: 5000,
      maxDelta: 0,
      maxSkew: 0,
      amount: 100,
      thresholdSqrtPrice: null,
      thresholdAmount: null,
    },
    {
      description: "7) Concentrated liq, price 1, 100 spread, 500 max delta",
      oraclePrice: 1,
      baseReserves: 500,
      quoteReserves: 1000,
      minSpread: 100,
      range: 5000,
      maxDelta: 500,
      maxSkew: 0,
      amount: 100,
      thresholdSqrtPrice: null,
      thresholdAmount: null,
    },
    {
      description:
        "8) Concentrated liq, price 0.1, 100 spread, 20000 max delta",
      oraclePrice: 0.1,
      baseReserves: 500,
      quoteReserves: 1000,
      minSpread: 100,
      range: 5000,
      maxDelta: 20000,
      maxSkew: 0,
      amount: 100,
      thresholdSqrtPrice: null,
      thresholdAmount: null,
    },
    {
      description: "9) Swap with liquidity exhausted",
      oraclePrice: 1,
      baseReserves: 100,
      quoteReserves: 100,
      minSpread: 100,
      range: 5000,
      maxDelta: 0,
      maxSkew: 0,
      amount: 200,
      thresholdSqrtPrice: null,
      thresholdAmount: null,
    },
    {
      description: "10) Swap with high oracle price",
      oraclePrice: 1000000000000000,
      baseReserves: 1000,
      quoteReserves: 1000,
      minSpread: 100,
      range: 5000,
      maxDelta: 0,
      maxSkew: 0,
      amount: 100,
      thresholdSqrtPrice: null,
      thresholdAmount: null,
    },
    {
      description: "11) Swap with low oracle price",
      oraclePrice: "0.00000001",
      baseReserves: 1000,
      quoteReserves: 1000,
      minSpread: 100,
      range: 5000,
      maxDelta: 0,
      maxSkew: 0,
      amount: 100,
      thresholdSqrtPrice: null,
      thresholdAmount: null,
    },
    {
      description: "12) Swap buy capped at threshold price",
      oraclePrice: 1,
      baseReserves: 100,
      quoteReserves: 100,
      minSpread: 100,
      range: 50000,
      maxDelta: 0,
      maxSkew: 0,
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
      description: "13) Swap sell capped at threshold price",
      oraclePrice: 1,
      baseReserves: 100,
      quoteReserves: 100,
      minSpread: 100,
      range: 50000,
      maxDelta: 0,
      maxSkew: 0,
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
      description: "14) Swap exact in with threshold amount",
      oraclePrice: 1,
      baseReserves: 1000,
      quoteReserves: 1000,
      minSpread: 100,
      range: 5000,
      maxDelta: 0,
      maxSkew: 0,
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
      description: "15) Swap exact out with threshold amount",
      oraclePrice: 1,
      baseReserves: 1000,
      quoteReserves: 1000,
      minSpread: 100,
      range: 5000,
      maxDelta: 0,
      maxSkew: 0,
      amount: 100,
      thresholdSqrtPrice: null,
      thresholdAmount: "1.00350000000000000000",
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
      minSpread,
      range,
      maxDelta,
      amount,
      thresholdSqrtPrice,
      thresholdAmount,
      swapCasesOverride,
    } = cases[i];

    const baseDecimals = 18;
    const quoteDecimals = 18;

    console.log(`Test Case ${description}`);
    const delta = getDelta(maxDelta, baseReserves, quoteReserves, oraclePrice);

    const swapCases = swapCasesOverride ?? getSwapCases();
    let j = 0;
    for (const { isBuy, exactInput } of swapCases) {
      console.log(
        `Swap Case ${j + 1}) isBuy: ${isBuy}, exactInput: ${exactInput}`
      );
      const { lowerLimit, upperLimit } = getVirtualPositionRange(
        !isBuy,
        minSpread,
        delta,
        range,
        oraclePrice,
        baseDecimals,
        quoteDecimals
      );
      const { lowerSqrtPrice, upperSqrtPrice, liquidity } = getVirtualPosition(
        !isBuy,
        lowerLimit,
        upperLimit,
        isBuy ? baseReserves : quoteReserves
      );
      const { amountIn, amountOut } = getSwapAmounts(
        isBuy,
        exactInput,
        amount,
        thresholdSqrtPrice,
        thresholdAmount,
        lowerSqrtPrice,
        upperSqrtPrice,
        liquidity,
        baseDecimals,
        quoteDecimals
      );
      console.log({
        amountIn: new Decimal(amountIn).mul(1e18).toFixed(0),
        amountOut: new Decimal(amountOut).mul(1e18).toFixed(0),
      });
      j++;
    }
  }
};

console.log("testing");
testSwapCases();
