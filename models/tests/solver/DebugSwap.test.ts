import {
  getDelta,
  getVirtualPosition,
  getVirtualPositionRange,
} from "../../src/libraries/SpreadMath";
import { getSwapAmounts } from "../../src/libraries/SwapLib";

const isBuy = false;
const exactInput = false;
const amount = "10000000000";
const swapFeeRate = 25;
const range = 5000;
const maxDelta = 500;
const oraclePrice = "0.37067545";
const baseReserves = "268762.195878807302077639";
const quoteReserves = "96834.519855";
const baseDecimals = 18;
const quoteDecimals = 6;

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
const { amountIn, amountOut } = getSwapAmounts(
  isBuy,
  exactInput,
  swapFeeRate,
  amount,
  null,
  null,
  lowerSqrtPrice,
  upperSqrtPrice,
  liquidity,
  baseDecimals,
  quoteDecimals
);
console.log({ amountIn, amountOut });
