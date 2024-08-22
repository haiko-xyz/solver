import Decimal from "decimal.js";
import { getSwapAmounts } from "../../src/libraries/SwapLib";

const testGetSwapAmounts = () => {
  const cases = [
    {
      isBuy: true,
      exactInput: true,
      amount: 1,
      thresholdSqrtPrice: null,
      thresholdAmount: null,
      lowerSqrtPrice: 1,
      upperSqrtPrice: 1.2 ** 0.5,
      liquidity: 10000,
    },
    {
      isBuy: true,
      exactInput: true,
      amount: 1,
      thresholdSqrtPrice: null,
      thresholdAmount: null,
      lowerSqrtPrice: 1,
      upperSqrtPrice: 1.2 ** 0.5,
      liquidity: 0,
    },
    {
      isBuy: false,
      exactInput: true,
      amount: 10,
      thresholdSqrtPrice: 0.95 ** 0.5,
      thresholdAmount: null,
      lowerSqrtPrice: 0.8 ** 0.5,
      upperSqrtPrice: 1,
      liquidity: 200,
    },
    {
      isBuy: true,
      exactInput: true,
      amount: 10,
      thresholdSqrtPrice: 1.05 ** 0.5,
      thresholdAmount: null,
      lowerSqrtPrice: 1,
      upperSqrtPrice: 1.2 ** 0.5,
      liquidity: 200,
    },
  ];

  const baseDecimals = 18;
  const quoteDecimals = 18;

  for (let i = 0; i < cases.length; i++) {
    const params = cases[i];
    const { amountIn, amountOut } = getSwapAmounts(
      params.isBuy,
      params.exactInput,
      params.amount,
      params.thresholdSqrtPrice,
      params.thresholdAmount,
      params.lowerSqrtPrice,
      params.upperSqrtPrice,
      params.liquidity,
      baseDecimals,
      quoteDecimals
    );
    console.log(`Case ${i + 1}`);
    console.log({
      amountIn: new Decimal(amountIn).mul(1e18).toFixed(0),
      amountOut: new Decimal(amountOut).mul(1e18).toFixed(0),
    });
  }
};

testGetSwapAmounts();
