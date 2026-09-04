import { existsSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const PROJECT_ROOT = join(__dirname, "..", "..", "..");
const MACHINE_ENV_PATH = join(PROJECT_ROOT, "deploy", "boot", "machine.env");

/** @typedef {{ workerBaseUrl: string, bootMachineToken: string, cfAccessClientId?: string, cfAccessClientSecret?: string, lmStudioModel: string, nextHealthUrl: string, searxngUrl: string }} BootConfig */

/** @returns {BootConfig} */
export function loadBootConfig() {
  if (!existsSync(MACHINE_ENV_PATH)) {
    throw new Error(
      `Fichier manquant : ${MACHINE_ENV_PATH}\nCopiez deploy/boot/machine.env.example → deploy/boot/machine.env`
    );
  }

  /** @type {Record<string, string>} */
  const values = {};
  for (const line of readFileSync(MACHINE_ENV_PATH, "utf8").split(/\r?\n/)) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#")) continue;
    const idx = trimmed.indexOf("=");
    if (idx <= 0) continue;
    const key = trimmed.slice(0, idx).trim();
    const value = trimmed.slice(idx + 1).trim();
    values[key] = value;
  }

  const workerBaseUrl = values.WORKER_BASE_URL?.replace(/\/$/, "");
  const bootMachineToken = values.BOOT_MACHINE_TOKEN?.trim();
  if (!workerBaseUrl || !bootMachineToken) {
    throw new Error(
      "deploy/boot/machine.env doit définir WORKER_BASE_URL et BOOT_MACHINE_TOKEN"
    );
  }

  const cfAccessClientId = values.CF_ACCESS_CLIENT_ID?.trim();
  const cfAccessClientSecret = values.CF_ACCESS_CLIENT_SECRET?.trim();

  return {
    workerBaseUrl,
    bootMachineToken,
    cfAccessClientId: cfAccessClientId || undefined,
    cfAccessClientSecret: cfAccessClientSecret || undefined,
    lmStudioModel: values.LM_STUDIO_MODEL?.trim() || "qwen/qwen3.5-9b",
    nextHealthUrl:
      values.NEXT_HEALTH_URL?.trim() || "http://127.0.0.1:3000/api/health",
    searxngUrl: values.SEARXNG_URL?.trim() || "http://localhost:8080",
  };
}

export { PROJECT_ROOT, MACHINE_ENV_PATH };
