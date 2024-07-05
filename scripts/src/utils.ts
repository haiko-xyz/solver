import Decimal from "decimal.js";

const setPrecision = () => {
  Decimal.set({ precision: 78, rounding: Decimal.ROUND_DOWN });
};

export const bigIntToAddress = (bigint: string) => {
  const hex = BigInt(bigint).toString(16);
  const paddingLength = 64 - hex.length;
  const padding = "0".repeat(paddingLength);
  return `0x${padding}${hex}`;
};

export const toFixed = (number: Decimal.Value, decimals: Decimal.Value) => {
  setPrecision();
  return new Decimal(number).mul(new Decimal(10).pow(decimals)).toFixed(0);
};

export const toDecimals = (number: Decimal.Value, decimals: Decimal.Value) => {
  setPrecision();
  return new Decimal(number).div(new Decimal(10).pow(decimals)).toFixed();
};

export const shortenAddress = (address: string) => {
  return `${address.slice(0, 7)}...${address.slice(-4)}`;
};
