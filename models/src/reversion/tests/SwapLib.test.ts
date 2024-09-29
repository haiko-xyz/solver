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
    },
  ];

  const baseDecimals = 18;
  const quoteDecimals = 18;

  for (let i = 0; i < cases.length; i++) {
    const params = cases[i];
    const { amountIn, amountOut, fees } = getSwapAmounts(
      params.isBuy,
      params.exactInput,
      params.amount,
      params.swapFeeRate,
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
      fees: new Decimal(fees).mul(1e18).toFixed(0),
    });
  }
};

testGetSwapAmounts();
