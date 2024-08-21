import Decimal from "decimal.js";
import { PRECISION, ROUNDING } from "../config";
import { baseToLiquidity, quoteToLiquidity } from "../math/liquidityMath";
import { limitToSqrtPrice, priceToLimit } from "../math/priceMath";

type PositionInfo = {
  lowerSqrtPrice: Decimal.Value;
  upperSqrtPrice: Decimal.Value;
  liquidity: Decimal.Value;
};

type PositionRange = {
  lowerLimit: Decimal.Value;
  upperLimit: Decimal.Value;
};

export const getVirtualPosition = (
  isBid: boolean,
  lowerLimit: Decimal.Value,
  upperLimit: Decimal.Value,
  amount: Decimal.Value
): PositionInfo => {
  Decimal.set({ precision: PRECISION, rounding: ROUNDING });

  const lowerSqrtPrice = limitToSqrtPrice(lowerLimit, 1);
  const upperSqrtPrice = limitToSqrtPrice(upperLimit, 1);
  if (isBid) {
    const liquidity = quoteToLiquidity(
      lowerSqrtPrice,
      upperSqrtPrice,
      amount
    ).toFixed();
    return { lowerSqrtPrice, upperSqrtPrice, liquidity };
  } else {
    const liquidity = baseToLiquidity(
      lowerSqrtPrice,
      upperSqrtPrice,
      amount
    ).toFixed();
    return { lowerSqrtPrice, upperSqrtPrice, liquidity };
  }
};

export const getVirtualPositionRange = (
  isBid: boolean,
  minSpread: Decimal.Value,
  delta: Decimal.Value,
  range: Decimal.Value,
  oraclePrice: Decimal.Value
): PositionRange => {
  Decimal.set({ precision: PRECISION, rounding: ROUNDING });

  let limit = priceToLimit(oraclePrice, 1, !isBid);

  if (isBid) {
    const upperLimit = new Decimal(limit).sub(minSpread).add(delta);
    const lowerLimit = upperLimit.sub(range);
    return { lowerLimit, upperLimit };
  } else {
    const lowerLimit = new Decimal(limit).add(minSpread).add(delta);
    const upperLimit = lowerLimit.add(range);
    return { lowerLimit, upperLimit };
  }
};

export const getDelta = (
  maxDelta: Decimal.Value,
  baseReserves: Decimal.Value,
  quoteReserves: Decimal.Value,
  price: Decimal.Value
): Decimal.Value => {
  Decimal.set({ precision: PRECISION, rounding: ROUNDING });

  const skew = getSkew(baseReserves, quoteReserves, price);
  const delta = new Decimal(maxDelta).mul(skew);

  return delta.toDP(0, Decimal.ROUND_DOWN);
};

export const getSkew = (
  baseReserves: Decimal.Value,
  quoteReserves: Decimal.Value,
  price: Decimal.Value
): Decimal.Value => {
  Decimal.set({ precision: PRECISION, rounding: ROUNDING });

  const baseInQuote = new Decimal(baseReserves).mul(price);
  const diff = new Decimal(quoteReserves).sub(baseInQuote);
  const sum = new Decimal(baseInQuote).add(quoteReserves);
  const skew = diff.div(sum);

  return skew.toDP(4, Decimal.ROUND_DOWN);
};
