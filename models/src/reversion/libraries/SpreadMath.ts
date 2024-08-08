import Decimal from "decimal.js";
import {
  baseToLiquidity,
  quoteToLiquidity,
} from "../../common/math/liquidityMath";
import { PRECISION, ROUNDING } from "../../common/config";
import { limitToSqrtPrice, priceToLimit } from "../../common/math/priceMath";
import { Trend } from "../types";

type PositionInfo = {
  lowerSqrtPrice: Decimal.Value;
  upperSqrtPrice: Decimal.Value;
  liquidity: Decimal.Value;
};

type PositionRange = {
  bidLower: Decimal.Value;
  bidUpper: Decimal.Value;
  askLower: Decimal.Value;
  askUpper: Decimal.Value;
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
  trend: Trend,
  range: Decimal.Value,
  cachedPrice: Decimal.Value,
  oraclePrice: Decimal.Value
): PositionRange => {
  Decimal.set({ precision: PRECISION, rounding: ROUNDING });

  if (new Decimal(oraclePrice).isZero()) {
    throw new Error("Oracle price is zero");
  }

  const oracleLimit = priceToLimit(oraclePrice, 1);
  const newBidLower = oracleLimit.sub(range);
  const newBidUpper = oracleLimit;
  const newAskLower = oracleLimit;
  const newAskUpper = oracleLimit.add(range);

  let cachedPriceSet = cachedPrice;
  if (new Decimal(cachedPrice).isZero()) {
    cachedPriceSet = oraclePrice;
  }

  const cachedLimit = priceToLimit(cachedPriceSet, 1);
  const bidLower = cachedLimit.sub(range);
  const bidUpper = cachedLimit;
  const askLower = cachedLimit;
  const askUpper = cachedLimit.add(range);

  switch (trend) {
    case Trend.Up:
      if (newBidUpper.gt(bidUpper)) {
        return {
          bidLower: newBidLower,
          bidUpper: newBidUpper,
          askLower: 0,
          askUpper: 0,
        };
      } else if (newAskLower.lte(bidLower)) {
        return {
          bidLower: 0,
          bidUpper: 0,
          askLower: bidLower,
          askUpper: bidUpper,
        };
      } else {
        if (newAskLower.gte(bidUpper)) {
          return {
            bidLower: bidLower,
            bidUpper: newBidUpper,
            askLower: 0,
            askUpper: 0,
          };
        }
        return {
          bidLower: bidLower,
          bidUpper: newBidUpper,
          askLower: newAskLower,
          askUpper: bidUpper,
        };
      }
    case Trend.Down:
      if (newAskLower.lt(askLower)) {
        return {
          bidLower: 0,
          bidUpper: 0,
          askLower: newAskLower,
          askUpper: newAskUpper,
        };
      } else if (newBidUpper.gte(askUpper)) {
        return {
          bidLower: askLower,
          bidUpper: askUpper,
          askLower: 0,
          askUpper: 0,
        };
      } else {
        if (newBidUpper.lte(askLower)) {
          return {
            bidLower: 0,
            bidUpper: 0,
            askLower: newAskLower,
            askUpper: askUpper,
          };
        }
        return {
          bidLower: askLower,
          bidUpper: newBidUpper,
          askLower: newAskLower,
          askUpper: askUpper,
        };
      }
    default:
      return {
        bidLower: newBidLower,
        bidUpper: newBidUpper,
        askLower: newAskLower,
        askUpper: newAskUpper,
      };
  }
};
