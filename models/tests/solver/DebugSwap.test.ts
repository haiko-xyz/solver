import {
  getDelta,
  getVirtualPosition,
  getVirtualPositionRange,
} from "../../src/libraries/SpreadMath";
import { getSwapAmounts } from "../../src/libraries/SwapLib";

const isBuy = false;
const exactInput = false;
const amount = "1";
const swapFeeRate = 0.003;
const range = 11400;
const maxDelta = 0;
const oraclePrice = "0.00016718";
const baseReserves = "10000";
const quoteReserves = "16.707738619115042000";
const baseDecimals = 18;
const quoteDecimals = 18;

const delta = getDelta(maxDelta, baseReserves, quoteReserves, oraclePrice);
const { lowerLimit, upperLimit } = getVirtualPositionRange(
  !isBuy,
  delta,
  range,
  oraclePrice,
  baseDecimals,
  quoteDecimals
);
console.log({ lowerLimit, upperLimit });
const { lowerSqrtPrice, upperSqrtPrice, liquidity } = getVirtualPosition(
  !isBuy,
  lowerLimit,
  upperLimit,
  isBuy ? baseReserves : quoteReserves
);
console.log({ lowerSqrtPrice, upperSqrtPrice, liquidity });
const { amountIn, amountOut } = getSwapAmounts({
  isBuy,
  exactInput,
  amount,
  swapFeeRate,
  thresholdSqrtPrice: null,
  thresholdAmount: null,
  lowerSqrtPrice,
  upperSqrtPrice,
  liquidity,
  baseDecimals,
  quoteDecimals,
});
console.log({ amountIn, amountOut });
