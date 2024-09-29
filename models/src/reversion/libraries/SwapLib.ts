import Decimal from "decimal.js";
import { PRECISION, ROUNDING } from "../../common/config";
import {
  liquidityToBase,
  liquidityToQuote,
} from "../../common/math/liquidityMath";
import { grossToNet, netToFee } from "../../common/math/feeMath";

export const getSwapAmounts = ({
  isBuy,
  exactInput,
  amount,
  swapFeeRate,
  thresholdSqrtPrice,
  thresholdAmount,
  lowerSqrtPrice,
  upperSqrtPrice,
  liquidity,
  baseDecimals,
  quoteDecimals,
}: {
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
}): {
  amountIn: Decimal.Value;
  amountOut: Decimal.Value;
  fees: Decimal.Value;
} => {
  const scaledLowerSqrtPrice = new Decimal(lowerSqrtPrice).mul(
    new Decimal(10).pow((baseDecimals - quoteDecimals) / 2)
  );
  const scaledUpperSqrtPrice = new Decimal(upperSqrtPrice).mul(
    new Decimal(10).pow((baseDecimals - quoteDecimals) / 2)
  );

  const startSqrtPrice = isBuy ? scaledLowerSqrtPrice : scaledUpperSqrtPrice;
  const targetSqrtPrice = isBuy
    ? thresholdSqrtPrice
      ? Decimal.min(thresholdSqrtPrice, scaledUpperSqrtPrice)
      : scaledUpperSqrtPrice
    : thresholdSqrtPrice
    ? Decimal.max(thresholdSqrtPrice, scaledLowerSqrtPrice)
    : scaledLowerSqrtPrice;

  const { amountIn, amountOut, fees, nextSqrtPrice } = computeSwapAmount({
    currSqrtPrice: startSqrtPrice,
    targetSqrtPrice,
    liquidity,
    amountRem: amount,
    swapFeeRate,
    exactInput,
  });

  const grossAmountIn = new Decimal(amountIn).add(fees);

  if (thresholdAmount) {
    if (exactInput) {
      if (amountOut < thresholdAmount)
        throw new Error("Threshold amount not met");
    } else {
      if (grossAmountIn > thresholdAmount)
        throw new Error("Threshold amount exceeded");
    }
  }

  return { amountIn: grossAmountIn, amountOut, fees };
};

export const computeSwapAmount = ({
  currSqrtPrice,
  targetSqrtPrice,
  liquidity,
  amountRem,
  swapFeeRate,
  exactInput,
}: {
  currSqrtPrice: Decimal.Value;
  targetSqrtPrice: Decimal.Value;
  liquidity: Decimal.Value;
  amountRem: Decimal.Value;
  swapFeeRate: Decimal.Value;
  exactInput: boolean;
}) => {
  Decimal.set({ precision: PRECISION, rounding: ROUNDING });
  const isBuy = new Decimal(targetSqrtPrice).gt(currSqrtPrice);
  let amountIn: Decimal.Value = "0";
  let amountOut: Decimal.Value = "0";
  let nextSqrtPrice: Decimal.Value = "0";
  let fees: Decimal.Value = "0";

  if (exactInput) {
    const amountRemainingLessFee = grossToNet(amountRem, swapFeeRate);
    amountIn = isBuy
      ? liquidityToQuote(currSqrtPrice, targetSqrtPrice, liquidity)
      : liquidityToBase(targetSqrtPrice, currSqrtPrice, liquidity);
    if (new Decimal(amountRemainingLessFee).gte(amountIn)) {
      nextSqrtPrice = targetSqrtPrice;
    } else {
      nextSqrtPrice = nextSqrtPriceAmountIn(
        currSqrtPrice,
        liquidity,
        amountRemainingLessFee,
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
  fees = netToFee(amountIn, swapFeeRate);

  return { amountIn, amountOut, fees, nextSqrtPrice };
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
