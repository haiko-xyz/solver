// Import environment variables
const envVars = [
  "RPC_URL",
  "OWNER_ADDRESS",
  "OWNER_PRIVATE_KEY",
  "LP_ADDRESS",
  "LP_PRIVATE_KEY",
  "REPLICATING_SOLVER_ADDRESS",
  "ETH_ADDRESS",
  "STRK_ADDRESS",
  "USDC_ADDRESS",
  "USDT_ADDRESS",
  "DPI_ADDRESS",
];
for (const envVar of envVars) {
  if (!process.env[envVar]) {
    throw new Error(`Missing env: ${envVar}`);
  }
}

const ENV = {} as { [key: string]: string };
for (const envVar of envVars) {
  ENV[envVar] = process.env[envVar] as string;
}

export { ENV };
