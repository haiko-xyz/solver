import Decimal from "decimal.js";
import {
  liquidityToBase,
  liquidityToQuote,
} from "../../common/math/liquidityMath";
import { PRECISION, ROUNDING } from "../../common/config";

export const getSwapAmounts = (
  isBuy: boolean,
  exactInput: boolean,
  amount: Decimal.Value,
  thresholdSqrtPrice: Decimal.Value | null,
  thresholdAmount: Decimal.Value | null,
  lowerSqrtPrice: Decimal.Value,
  upperSqrtPrice: Decimal.Value,
  liquidity: Decimal.Value
): { amountIn: Decimal.Value; amountOut: Decimal.Value } => {
  if (
    new Decimal(liquidity).isZero() ||
    new Decimal(lowerSqrtPrice).eq(upperSqrtPrice)
  ) {
    return { amountIn: "0", amountOut: "0" };
  }

  const startSqrtPrice = isBuy ? lowerSqrtPrice : upperSqrtPrice;
  const targetSqrtPrice = isBuy
    ? thresholdSqrtPrice
      ? Decimal.min(thresholdSqrtPrice, upperSqrtPrice)
      : upperSqrtPrice
    : thresholdSqrtPrice
    ? Decimal.max(thresholdSqrtPrice, lowerSqrtPrice)
    : lowerSqrtPrice;

  const { amountIn, amountOut, nextSqrtPrice } = computeSwapAmount(
    startSqrtPrice,
    targetSqrtPrice,
    liquidity,
    amount,
    exactInput
  );

  if (thresholdAmount) {
    if (exactInput) {
      if (amountOut < thresholdAmount)
        throw new Error("Threshold amount not met");
    } else {
      if (amountIn > thresholdAmount)
        throw new Error("Threshold amount exceeded");
    }
  }

  return { amountIn, amountOut };
};

export const computeSwapAmount = (
  currSqrtPrice: Decimal.Value,
  targetSqrtPrice: Decimal.Value,
  liquidity: Decimal.Value,
  amountRem: Decimal.Value,
  exactInput: boolean
) => {
  Decimal.set({ precision: PRECISION, rounding: ROUNDING });
  const isBuy = new Decimal(targetSqrtPrice).gt(currSqrtPrice);
  let amountIn: Decimal.Value = "0";
  let amountOut: Decimal.Value = "0";
  let nextSqrtPrice: Decimal.Value = "0";

  if (exactInput) {
    amountIn = isBuy
      ? liquidityToQuote(currSqrtPrice, targetSqrtPrice, liquidity)
      : liquidityToBase(targetSqrtPrice, currSqrtPrice, liquidity);
    if (new Decimal(amountRem).gte(amountIn)) {
      nextSqrtPrice = targetSqrtPrice;
    } else {
      nextSqrtPrice = nextSqrtPriceAmountIn(
        currSqrtPrice,
        liquidity,
        amountRem,
        isBuy
      );
    }
  } else {
    amountOut = isBuy
      ? liquidityToBase(currSqrtPrice, targetSqrtPrice, liquidity)
      : liquidityToQuote(targetSqrtPrice, currSqrtPrice, liquidity);
    if (new Decimal(amountRem).gte(amountOut)) {
      nextSqrtPrice = targetSqrtPrice;
    } else {
      nextSqrtPrice = nextSqrtPriceAmountOut(
        currSqrtPrice,
        liquidity,
        amountRem,
        isBuy
      );
    }
  }

  const max = targetSqrtPrice === nextSqrtPrice;

  if (isBuy) {
    if (!max || !exactInput) {
      amountIn = liquidityToQuote(currSqrtPrice, nextSqrtPrice, liquidity);
    }
    if (!max || exactInput) {
      amountOut = liquidityToBase(currSqrtPrice, nextSqrtPrice, liquidity);
    }
  } else {
    if (!max || !exactInput) {
      amountIn = liquidityToBase(nextSqrtPrice, currSqrtPrice, liquidity);
    }
    if (!max || exactInput) {
      amountOut = liquidityToQuote(nextSqrtPrice, currSqrtPrice, liquidity);
    }
  }

  if (!exactInput && amountOut > amountRem) {
    amountOut = amountRem;
  }

  // In Uniswap, if target price is not reached, LP takes the remainder of the maximum input as fee.
  // We don't do that here.
  return { amountIn, amountOut, nextSqrtPrice };
};

export const nextSqrtPriceAmountIn = (
  currSqrtPrice: Decimal.Value,
  liquidity: Decimal.Value,
  amountIn: Decimal.Value,
  isBuy: boolean
) => {
  Decimal.set({ precision: PRECISION, rounding: ROUNDING });
  const currSqrtPriceBN = new Decimal(currSqrtPrice);
  const liquidityBN = new Decimal(liquidity);
  const amountInBN = new Decimal(amountIn);
  const nextSqrtPrice = isBuy
    ? currSqrtPriceBN.add(amountInBN.div(liquidityBN))
    : liquidityBN
        .mul(currSqrtPriceBN)
        .div(liquidityBN.add(amountInBN.mul(currSqrtPriceBN)));
  return nextSqrtPrice;
};

export const nextSqrtPriceAmountOut = (
  currSqrtPrice: Decimal.Value,
  liquidity: Decimal.Value,
  amountOut: Decimal.Value,
  isBuy: boolean
) => {
  Decimal.set({ precision: PRECISION, rounding: ROUNDING });
  const currSqrtPriceBN = new Decimal(currSqrtPrice);
  const liquidityBN = new Decimal(liquidity);
  const amountOutBN = new Decimal(amountOut);
  const nextSqrtPrice = isBuy
    ? liquidityBN
        .mul(currSqrtPriceBN)
        .div(liquidityBN.sub(amountOutBN.mul(currSqrtPriceBN)))
    : currSqrtPriceBN.sub(amountOutBN.div(liquidityBN));
  return nextSqrtPrice;
};
