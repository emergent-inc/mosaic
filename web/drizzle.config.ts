import { defineConfig } from "drizzle-kit";

function defaultDatabaseURL(): string {
  const rawPort = process.env.MOSAIC_PORT ?? process.env.PORT ?? "3777";
  const mosaicPort = /^\d+$/.test(rawPort) ? Number(rawPort) : 3777;
  const offset = Number(process.env.MOSAIC_DB_PORT_OFFSET ?? "10000");
  const dbPort = process.env.MOSAIC_DB_PORT ?? String(mosaicPort + offset);
  const user = process.env.MOSAIC_DB_USER ?? "mosaic";
  const password = process.env.MOSAIC_DB_PASSWORD ?? "mosaic";
  const database = process.env.MOSAIC_DB_NAME ?? "mosaic";
  return `postgres://${user}:${password}@localhost:${dbPort}/${database}`;
}

export default defineConfig({
  schema: "./db/schema.ts",
  out: "./db/migrations",
  dialect: "postgresql",
  dbCredentials: {
    url: process.env.DIRECT_DATABASE_URL ?? process.env.DATABASE_URL ?? defaultDatabaseURL(),
  },
  strict: true,
  verbose: true,
});
