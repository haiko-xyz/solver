import Decimal from "decimal.js";
import { getSwapAmounts } from "../libraries/SwapLib";

type SwapParams = {
  isBuy: boolean;
  exactInput: boolean;
  amount: Decimal.Value;
  swapFeeRate: Decimal.Value;
  thresholdSqrtPrice: Decimal.Value | null;
  thresholdAmount: Decimal.Value | null;
  lowerSqrtPrice: Decimal.Value;
  upperSqrtPrice: Decimal.Value;
  liquidity: Decimal.Value;
  baseDecimals: number;
  quoteDecimals: number;
};
const testGetSwapAmounts = () => {
  const cases: SwapParams[] = [
    {
      isBuy: true,
      exactInput: true,
      amount: 1,
      swapFeeRate: 0,
      thresholdSqrtPrice: null,
      thresholdAmount: null,
      lowerSqrtPrice: 0.8 ** 0.5,
      upperSqrtPrice: 1,
      liquidity: 10000,
      baseDecimals: 18,
      quoteDecimals: 18,
    },
    {
      isBuy: true,
      exactInput: true,
      amount: 1,
      swapFeeRate: 0.005,
      thresholdSqrtPrice: null,
      thresholdAmount: null,
      lowerSqrtPrice: 1,
      upperSqrtPrice: 1.2 ** 0.5,
      liquidity: 0,
      baseDecimals: 18,
      quoteDecimals: 18,
    },
    {
      isBuy: false,
      exactInput: true,
      amount: 10,
      swapFeeRate: 0.005,
      thresholdSqrtPrice: 0.95 ** 0.5,
      thresholdAmount: null,
      lowerSqrtPrice: 0.8 ** 0.5,
      upperSqrtPrice: 1,
      liquidity: 200,
      baseDecimals: 18,
      quoteDecimals: 18,
    },
    {
      isBuy: true,
      exactInput: true,
      amount: 10,
      swapFeeRate: 0.005,
      thresholdSqrtPrice: 1.05 ** 0.5,
      thresholdAmount: null,
      lowerSqrtPrice: 1,
      upperSqrtPrice: 1.2 ** 0.5,
      liquidity: 200,
      baseDecimals: 18,
      quoteDecimals: 18,
    },
    {
      isBuy: true,
      exactInput: true,
      amount: 9.26891,
      swapFeeRate: 0.005,
      thresholdSqrtPrice: null,
      thresholdAmount: null,
      lowerSqrtPrice: 0.375 ** 0.5,
      upperSqrtPrice: 0.4 ** 0.5,
      liquidity: 1,
      baseDecimals: 18,
      quoteDecimals: 6,
    },
  ];

  for (let i = 0; i < cases.length; i++) {
    const params = cases[i];
    const { amountIn, amountOut, fees } = getSwapAmounts({
      isBuy: params.isBuy,
      exactInput: params.exactInput,
      amount: params.amount,
      swapFeeRate: params.swapFeeRate,
      thresholdSqrtPrice: params.thresholdSqrtPrice,
      thresholdAmount: params.thresholdAmount,
      lowerSqrtPrice: params.lowerSqrtPrice,
      upperSqrtPrice: params.upperSqrtPrice,
      liquidity: params.liquidity,
      baseDecimals: params.baseDecimals,
      quoteDecimals: params.quoteDecimals,
    });
    console.log(`Case ${i + 1}`);
    const inDecimals = params.isBuy
      ? params.quoteDecimals
      : params.baseDecimals;
    const outDecimals = params.isBuy
      ? params.baseDecimals
      : params.quoteDecimals;
    console.log({
      amountIn: new Decimal(amountIn)
        .mul(new Decimal(10).pow(inDecimals))
        .toFixed(0),
      amountOut: new Decimal(amountOut)
        .mul(new Decimal(10).pow(outDecimals))
        .toFixed(0),
      fees: new Decimal(fees).mul(new Decimal(10).pow(inDecimals)).toFixed(0),
    });
  }
};

testGetSwapAmounts();
