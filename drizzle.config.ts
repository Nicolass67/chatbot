import { defineConfig } from "drizzle-kit";
import path from "node:path";

export default defineConfig({
  schema: "./src/lib/db/schema.ts",
  out: "./drizzle",
  dialect: "sqlite",
  dbCredentials: {
    url: process.env.DATABASE_URL ?? path.join("data", "local.db"),
  },
});
