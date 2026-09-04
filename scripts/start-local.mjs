#!/usr/bin/env node
/**
 * Bootstrap SearXNG puis démarre Next.js en mode développement.
 * Ne modifie pas npm run dev (debug classique sans bootstrap).
 */
import { spawn } from "node:child_process";
import { existsSync } from "node:fs";
import { resolve, dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { bootstrapSearxng } from "./lib/searxng-bootstrap.mjs";

const __dirname = dirname(fileURLToPath(import.meta.url));
const PROJECT_ROOT = resolve(__dirname, "..");

function spawnNextDev() {
  const nextBin = join(
    PROJECT_ROOT,
    "node_modules",
    ".bin",
    process.platform === "win32" ? "next.cmd" : "next"
  );

  if (!existsSync(nextBin)) {
    console.error(
      "✕ Next.js introuvable — exécutez d'abord : npm.cmd install"
    );
    process.exit(1);
  }

  return spawn(nextBin, ["dev", "--turbopack"], {
    cwd: PROJECT_ROOT,
    stdio: "inherit",
    shell: process.platform === "win32",
  });
}

async function main() {
  console.log("=== Chatbot local — démarrage ===\n");

  const bootstrap = await bootstrapSearxng({ fatal: false });
  if (!bootstrap.ok) {
    console.warn(
      `\n⚠ Web indisponible : ${bootstrap.message ?? "SearXNG non joignable"}`
    );
    console.warn(
      "  Le chatbot démarre quand même — seules les fonctions Web seront limitées.\n"
    );
  } else {
    console.log("");
  }

  console.log("▶ Démarrage Next.js…\n");
  console.log(
    "  Rappel : démarrez LM Studio (serveur local) pour l'inférence IA.\n"
  );

  const child = spawnNextDev();

  child.on("exit", (code) => {
    process.exit(code ?? 0);
  });

  process.on("SIGINT", () => child.kill("SIGINT"));
  process.on("SIGTERM", () => child.kill("SIGTERM"));
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
