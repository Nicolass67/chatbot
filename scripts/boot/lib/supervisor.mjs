import { spawn } from "node:child_process";
import { existsSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const PROJECT_ROOT = join(__dirname, "..", "..", "..");
const SUPERVISOR_HEALTH = "http://127.0.0.1:3927/health";
const RUN_FOREVER = join(
  PROJECT_ROOT,
  "scripts",
  "supervisor",
  "run-forever.cmd"
);

/**
 * Démarre le Supervisor seulement après un boot demandé par l'app.
 * Ne doit PAS être au login Windows (sinon contournement du boot conditionnel).
 * @returns {Promise<{ ok: boolean, alreadyRunning?: boolean, error?: string }>}
 */
export async function ensureSupervisorRunning() {
  try {
    const res = await fetch(SUPERVISOR_HEALTH, {
      signal: AbortSignal.timeout(1500),
    });
    if (res.ok) {
      return { ok: true, alreadyRunning: true };
    }
  } catch {
    // not running
  }

  if (!existsSync(RUN_FOREVER)) {
    return { ok: false, error: "supervisor_wrapper_missing" };
  }

  try {
    spawn("cmd.exe", ["/c", RUN_FOREVER], {
      cwd: PROJECT_ROOT,
      detached: true,
      stdio: "ignore",
      windowsHide: true,
    }).unref();
  } catch (error) {
    return {
      ok: false,
      error: error instanceof Error ? error.message : String(error),
    };
  }

  const started = Date.now();
  while (Date.now() - started < 15_000) {
    await new Promise((r) => setTimeout(r, 500));
    try {
      const res = await fetch(SUPERVISOR_HEALTH, {
        signal: AbortSignal.timeout(1500),
      });
      if (res.ok) return { ok: true, alreadyRunning: false };
    } catch {
      // retry
    }
  }

  return { ok: false, error: "supervisor_start_timeout" };
}
