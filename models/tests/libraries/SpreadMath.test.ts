import Decimal from "decimal.js";
import {
  getVirtualPosition,
  getVirtualPositionRange,
} from "../../src/libraries/SpreadMath";

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
  const baseDecimals = 18;
  const quoteDecimals = 18;

  const cases = [
    {
      delta: 0,
      range: 1,
      oraclePrice: 1,
    },
    {
      delta: 0,
      range: 1000,
      oraclePrice: 1,
    },
    {
      delta: -100,
      range: 1000,
      oraclePrice: 1,
    },
    {
      delta: 100,
      range: 1000,
      oraclePrice: 1,
    },
    {
      delta: -5000,
      range: 1000,
      oraclePrice: 1,
    },
    {
      delta: 5000,
      range: 1000,
      oraclePrice: 1,
    },
    {
      delta: -7905625,
      range: 1000,
      oraclePrice: 1,
    },
    {
      delta: 7905625,
      range: 1000,
      oraclePrice: 1,
    },
    {
      delta: 0,
      range: 1000,
      oraclePrice: "0.0000000000000000000000000001",
    },
    {
      delta: 0,
      range: 1000,
      oraclePrice:
        "21445968470833706281754813411422482.6295263805072231182393896500",
    },
  ];

  for (let i = 0; i < cases.length; i++) {
    const c = cases[i];
    console.log(`Case ${i + 1}`);
    const bid = getVirtualPositionRange(
      true,
      c.delta,
      c.range,
      c.oraclePrice,
      baseDecimals,
      quoteDecimals
    );
    const ask = getVirtualPositionRange(
      false,
      c.delta,
      c.range,
      c.oraclePrice,
      baseDecimals,
      quoteDecimals
    );
    console.log({
      bidLower: new Decimal(bid.lowerLimit).toFixed(0),
      bidUpper: new Decimal(bid.upperLimit).toFixed(0),
      askLower: new Decimal(ask.lowerLimit).toFixed(0),
      askUpper: new Decimal(ask.upperLimit).toFixed(0),
    });
  }
};

// testGetVirtualPositionCases();
testGetVirtualPositionRangeCases();
