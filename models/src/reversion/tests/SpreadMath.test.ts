import Decimal from "decimal.js";
import {
  getVirtualPosition,
  getVirtualPositionRange,
} from "../libraries/SpreadMath";
import { Trend } from "../types";

const testGetVirtualPositionCases = () => {
  const cases = [
    { lowerLimit: 7906624, upperLimit: 7906625, amount: 1000 },
    { lowerLimit: 7906625, upperLimit: 7907625, amount: 0 },
    { lowerLimit: 7906625 - 600000, upperLimit: 7906625 - 500000, amount: 1 },
    { lowerLimit: 7906625 - 100000, upperLimit: 7906625 - 90000, amount: 1 },
    { lowerLimit: 7906625 + 90000, upperLimit: 7906625 + 100000, amount: 1 },
    { lowerLimit: 7906625 + 500000, upperLimit: 7906625 + 600000, amount: 1 },
    {
      lowerLimit: 7906625,
      upperLimit: 7907625,
      amount: "0.000000000000000001",
    },
    {
      lowerLimit: 7906625,
      upperLimit: 7907625,
      amount: "100000000000000000",
    },
  ];

  for (let i = 0; i < cases.length; i++) {
    const params = cases[i];
    const bid = getVirtualPosition(
      true,
      params.lowerLimit,
      params.upperLimit,
      params.amount
    );
    const ask = getVirtualPosition(
      false,
      params.lowerLimit,
      params.upperLimit,
      params.amount
    );
    console.log(`Case ${i + 1}`);
    console.log({
      lowerSqrtPrice: new Decimal(bid.lowerSqrtPrice).mul(1e28).toFixed(0),
      upperSqrtPrice: new Decimal(bid.upperSqrtPrice).mul(1e28).toFixed(0),
      bidLiquidity: new Decimal(bid.liquidity).mul(1e18).toFixed(0),
      askLiquidity: new Decimal(ask.liquidity).mul(1e18).toFixed(0),
    });
  }
};

const testGetVirtualPositionRangeCases = () => {
  const cases = [
    getVirtualPositionRange(Trend.Up, 1000, 1, 1.1),
    getVirtualPositionRange(Trend.Up, 1000, 1, 1),
    getVirtualPositionRange(Trend.Up, 1000, 1, 0.995),
    getVirtualPositionRange(Trend.Up, 1000, 1, 0.99005),
    getVirtualPositionRange(Trend.Up, 1000, 1, 0.95),
    getVirtualPositionRange(Trend.Up, 1000, 0, 0.9),
    getVirtualPositionRange(Trend.Down, 1000, 1, 0.9),
    getVirtualPositionRange(Trend.Down, 1000, 1, 1),
    getVirtualPositionRange(Trend.Down, 1000, 1, 1.005),
    getVirtualPositionRange(Trend.Down, 1000, 1, 1.01006),
    getVirtualPositionRange(Trend.Down, 1000, 1, 1.05),
    getVirtualPositionRange(Trend.Down, 1000, 0, 1.1),
    getVirtualPositionRange(Trend.Range, 1000, 1, 1),
    getVirtualPositionRange(Trend.Range, 1000, 1, 1.5),
    getVirtualPositionRange(Trend.Range, 1000, 1, 0.5),
  ];

  for (let i = 0; i < cases.length; i++) {
    const pos = cases[i];
    console.log(`Case ${i + 1}`);
    console.log({
      bidLower: new Decimal(pos.bidLower).toFixed(0),
      bidUpper: new Decimal(pos.bidUpper).toFixed(0),
      askLower: new Decimal(pos.askLower).toFixed(0),
      askUpper: new Decimal(pos.askUpper).toFixed(0),
    });
  }
};

// testGetVirtualPositionCases();
testGetVirtualPositionRangeCases();
