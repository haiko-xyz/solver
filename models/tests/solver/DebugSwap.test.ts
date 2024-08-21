import {
  getDelta,
  getVirtualPosition,
  getVirtualPositionRange,
} from "../../src/libraries/SpreadMath";
import { getSwapAmounts } from "../../src/libraries/SwapLib";

const isBuy = false;
const exactInput = true;
const amount = "1000";
const minSpread = 25;
const range = 5000;
const maxDelta = 500;
const oraclePrice = "0.00013734";
const baseReserves = "80000";
const quoteReserves = "11.428658419735305956";

const delta = getDelta(maxDelta, baseReserves, quoteReserves, oraclePrice);
console.log({ delta });
const { lowerLimit, upperLimit } = getVirtualPositionRange(
  !isBuy,
  minSpread,
  delta,
  range,
  oraclePrice
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
  amount,
  null,
  null,
  lowerSqrtPrice,
  upperSqrtPrice,
  liquidity
);
console.log({ amountIn, amountOut });
