import Decimal from "decimal.js";
import { baseToLiquidity, quoteToLiquidity } from "../math/liquidityMath";
import { PRECISION, ROUNDING } from "../config";
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

  if (isBid) {
    const lowerSqrtPrice = limitToSqrtPrice(lowerLimit, 1);
    const upperSqrtPrice = limitToSqrtPrice(upperLimit, 1);
    const liquidity = quoteToLiquidity(
      lowerSqrtPrice,
      upperSqrtPrice,
      amount
    ).toFixed();
    return { lowerSqrtPrice, upperSqrtPrice, liquidity };
  } else {
    const lowerSqrtPrice = limitToSqrtPrice(lowerLimit, 1);
    const upperSqrtPrice = limitToSqrtPrice(upperLimit, 1);
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

  let limit = priceToLimit(oraclePrice, 1);

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
