import Decimal from "decimal.js";
import {
  getVirtualPosition,
  getVirtualPositionRange,
} from "../../replicating/libraries/SpreadMath";

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
    getVirtualPositionRange(true, 0, 0, 1, 1, baseDecimals, quoteDecimals),
    getVirtualPositionRange(false, 0, 0, 1, 1, baseDecimals, quoteDecimals),
  ];

  for (let i = 0; i < cases.length; i++) {
    const pos = cases[i];
    console.log(`Case ${i + 1}`);
    console.log({
      lowerLimit: new Decimal(pos.lowerLimit).toFixed(0),
      upperLimit: new Decimal(pos.upperLimit).toFixed(0),
    });
  }
};

// testGetVirtualPositionCases();
testGetVirtualPositionRangeCases();
