#!/usr/bin/env node
/**
 * Démarre Next.js en production (port 3000), processus détaché.
 */
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import {
  ensureNextJsProduction,
  waitForNextHealth,
} from "./boot/lib/nextjs.mjs";

const __dirname = dirname(fileURLToPath(import.meta.url));
const root = join(__dirname, "..");
const healthUrl =
  process.env.NEXT_HEALTH_URL ?? "http://127.0.0.1:3000/api/health";

const started = await ensureNextJsProduction();
if (!started.ok) {
  console.error(
    `[prod] Échec démarrage : ${started.message ?? started.error ?? "unknown"}`
  );
  process.exit(1);
}

const health = await waitForNextHealth(healthUrl, 120_000);
if (!health.ok) {
  console.error("[prod] Next.js démarré mais health check en échec");
  process.exit(1);
}

console.log("[prod] Next.js prêt — http://127.0.0.1:3000");
