import Decimal from "decimal.js";
import { PRECISION, ROUNDING } from "../config";

export const netToFee = (netAmount: Decimal.Value, feeRate: Decimal.Value) => {
  Decimal.set({ precision: PRECISION, rounding: ROUNDING });
  let netAmountBN = new Decimal(netAmount);
  let one = new Decimal(1);
  let fee = netAmountBN.mul(feeRate).div(one.sub(feeRate));
  return fee.toFixed();
};

export const grossToNet = (
  grossAmount: Decimal.Value,
  feeRate: Decimal.Value
) => {
  Decimal.set({ precision: PRECISION, rounding: ROUNDING });
  let grossAmountDec = new Decimal(grossAmount);
  let one = new Decimal(1);
  let netAmount = grossAmountDec.mul(one.sub(feeRate));
  return netAmount.toFixed();
};
