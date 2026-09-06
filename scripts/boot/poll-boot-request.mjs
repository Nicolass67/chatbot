#!/usr/bin/env node
/**
 * Sonde légère pour PC déjà allumé : consume + start/restart direct.
 */
import { existsSync, mkdirSync, readFileSync, unlinkSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { spawn } from "node:child_process";
import { isNextJsProductionReady } from "./boot-logic.mjs";
import { loadBootConfig, PROJECT_ROOT } from "./lib/config.mjs";
import { fetchNextHealth } from "./lib/nextjs.mjs";
import { peekBootRequest } from "./lib/worker-client.mjs";

const __dirname = dirname(fileURLToPath(import.meta.url));
const LOCK_PATH = join(PROJECT_ROOT, "data", "boot-poll.lock");
const LOCK_MAX_AGE_MS = 10 * 60 * 1000;

function isPidAlive(pid) {
  if (!pid || pid <= 0) return false;
  try {
    process.kill(pid, 0);
    return true;
  } catch {
    return false;
  }
}

function acquireLock() {
  mkdirSync(dirname(LOCK_PATH), { recursive: true });
  if (existsSync(LOCK_PATH)) {
    try {
      const raw = readFileSync(LOCK_PATH, "utf8");
      const parsed = JSON.parse(raw);
      const age = Date.now() - Number(parsed.startedAt ?? 0);
      const pidAlive = isPidAlive(Number(parsed.pid ?? 0));
      if (age >= 0 && age < LOCK_MAX_AGE_MS && pidAlive) {
        return false;
      }
    } catch {
      // stale lock
    }
  }
  writeFileSync(
    LOCK_PATH,
    JSON.stringify({ pid: process.pid, startedAt: Date.now() })
  );
  return true;
}

function releaseLock() {
  if (existsSync(LOCK_PATH)) {
    try {
      unlinkSync(LOCK_PATH);
    } catch {
      // ignore
    }
  }
}

/** @param {import("./lib/config.mjs").BootConfig} config */
function accessAuthFromConfig(config) {
  return {
    cfAccessClientId: config.cfAccessClientId,
    cfAccessClientSecret: config.cfAccessClientSecret,
  };
}

function runExecuteBootRequest() {
  return new Promise((resolve) => {
    const child = spawn(
      process.execPath,
      [join(__dirname, "execute-boot-request.mjs")],
      {
        cwd: PROJECT_ROOT,
        stdio: "inherit",
        windowsHide: process.platform === "win32",
      }
    );
    child.on("close", (code) => resolve(code ?? 1));
    child.on("error", () => resolve(1));
  });
}

async function main() {
  if (!acquireLock()) {
    console.log("[poll] Déjà en cours — skip.");
    process.exit(0);
  }

  try {
    let config;
    try {
      config = loadBootConfig();
    } catch (error) {
      console.log(
        `[poll] Config absente — skip (${error instanceof Error ? error.message : error}).`
      );
      process.exit(0);
    }

    const peekRes = await peekBootRequest(
      config.workerBaseUrl,
      config.bootMachineToken,
      fetch,
      accessAuthFromConfig(config)
    );

    if (peekRes.error === "access_blocked") {
      console.error("[poll] Cloudflare Access bloque /boot-request.");
      process.exit(1);
    }

    if (!peekRes.ok || !peekRes.body?.pending) {
      console.log("[poll] Aucune demande Worker pending — skip.");
      process.exit(0);
    }

    const action = peekRes.body.action ?? "start";

    if (action === "start") {
      try {
        const healthRes = await fetchNextHealth(config.nextHealthUrl);
        if (
          healthRes.status === 200 &&
          isNextJsProductionReady(healthRes.health)
        ) {
          // Consommer quand même pour ne pas laisser une demande pending orpheline.
          const { consumeBootRequest } = await import("./lib/worker-client.mjs");
          await consumeBootRequest(
            config.workerBaseUrl,
            config.bootMachineToken,
            peekRes.body.requestId,
            fetch,
            accessAuthFromConfig(config)
          );
          console.log(
            "[poll] Services déjà en ligne — demande consommée, skip démarrage."
          );
          process.exit(0);
        }
      } catch {
        // continue
      }
    }

    console.log(
      `[poll] Demande ${action} pending (${peekRes.body.requestId}) — exécution directe…`
    );
    const code = await runExecuteBootRequest();
    process.exit(code === 0 ? 0 : 1);
  } finally {
    releaseLock();
  }
}

main().catch((error) => {
  console.error("[poll] Erreur fatale:", error);
  releaseLock();
  process.exit(1);
});
