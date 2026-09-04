import { existsSync, mkdirSync, readFileSync, unlinkSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const PROJECT_ROOT = join(__dirname, "..", "..", "..");
const LOCK_PATH = join(PROJECT_ROOT, "data", "boot-stack.lock");
const LOCK_MAX_AGE_MS = 20 * 60 * 1000;

function isPidAlive(pid) {
  if (!pid || pid <= 0) return false;
  try {
    process.kill(pid, 0);
    return true;
  } catch {
    return false;
  }
}

export function acquireBootStackLock(label = "boot") {
  mkdirSync(dirname(LOCK_PATH), { recursive: true });
  if (existsSync(LOCK_PATH)) {
    try {
      const parsed = JSON.parse(readFileSync(LOCK_PATH, "utf8"));
      const age = Date.now() - Number(parsed.startedAt ?? 0);
      const pidAlive = isPidAlive(Number(parsed.pid ?? 0));
      if (age >= 0 && age < LOCK_MAX_AGE_MS && pidAlive) {
        return {
          ok: false,
          reason: "boot_in_progress",
          owner: parsed.label ?? "unknown",
        };
      }
    } catch {
      // stale lock
    }
  }

  writeFileSync(
    LOCK_PATH,
    JSON.stringify({
      pid: process.pid,
      startedAt: Date.now(),
      label,
    })
  );
  return { ok: true };
}

export function releaseBootStackLock() {
  if (!existsSync(LOCK_PATH)) return;
  try {
    const parsed = JSON.parse(readFileSync(LOCK_PATH, "utf8"));
    if (Number(parsed.pid) !== process.pid) return;
    unlinkSync(LOCK_PATH);
  } catch {
    try {
      unlinkSync(LOCK_PATH);
    } catch {
      // ignore
    }
  }
}
