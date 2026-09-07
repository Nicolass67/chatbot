import { spawn, spawnSync } from "node:child_process";
import { existsSync, mkdirSync, openSync, readFileSync, unlinkSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { sleep } from "./network.mjs";
import { isTcpPortOpen } from "./network.mjs";

const __dirname = dirname(fileURLToPath(import.meta.url));
const PROJECT_ROOT = join(__dirname, "..", "..", "..");
const BUILD_ID_PATH = join(PROJECT_ROOT, ".next", "BUILD_ID");
const PID_PATH = join(PROJECT_ROOT, "data", "next-prod.pid");
const LOG_PATH = join(PROJECT_ROOT, "data", "next-prod.log");

/** @type {import('node:child_process').ChildProcess | null} */
let nextProcess = null;

/**
 * Évite d'utiliser le Node embarqué Cursor (cassé pour spawn Next détaché).
 * @returns {string}
 */
function resolveNodeExecutable() {
  const candidates = [
    process.env.CHATBOT_NODE_PATH,
    process.platform === "win32" ? "C:\\Program Files\\nodejs\\node.exe" : null,
    process.execPath,
  ].filter(Boolean);
  for (const candidate of candidates) {
    if (
      typeof candidate === "string" &&
      existsSync(candidate) &&
      !/cursor-agent|anysphere/i.test(candidate)
    ) {
      return candidate;
    }
  }
  return process.execPath;
}

function loadHealthTokenFromEnvLocal() {
  if (process.env.HEALTH_CHECK_TOKEN) return;
  try {
    const raw = readFileSync(join(PROJECT_ROOT, ".env.local"), "utf8");
    for (const line of raw.split(/\r?\n/)) {
      const m = line.match(/^HEALTH_CHECK_TOKEN=(.*)$/);
      if (m) {
        process.env.HEALTH_CHECK_TOKEN = m[1].trim();
        return;
      }
    }
  } catch {
    // optional
  }
}

loadHealthTokenFromEnvLocal();

function isPidAlive(pid) {
  if (!pid || pid <= 0) return false;
  try {
    process.kill(pid, 0);
    return true;
  } catch {
    return false;
  }
}

export function getNextProcess() {
  return nextProcess;
}

export async function isNextJsListening() {
  return isTcpPortOpen("127.0.0.1", 3000);
}

/**
 * @param {string} healthUrl
 * @param {number} timeoutMs
 */
function healthFetchHeaders() {
  /** @type {Record<string, string>} */
  const headers = {};
  const token = process.env.HEALTH_CHECK_TOKEN;
  if (token) headers.Authorization = `Bearer ${token}`;
  return headers;
}

/**
 * @param {Response} response
 * @param {unknown} body
 */
function isHealthAcceptable(response, body) {
  if (response.status === 200) return true;
  if (response.status !== 200 && response.status !== 503) return false;
  const status =
    body && typeof body === "object" && "status" in body
      ? String(/** @type {{ status?: unknown }} */ (body).status)
      : "";
  if (status !== "ok" && status !== "degraded") return false;
  const sqliteOk =
    body &&
    typeof body === "object" &&
    "ready" in body &&
    /** @type {{ ready?: unknown }} */ (body).ready === true;
  const checksSqlite =
    body &&
    typeof body === "object" &&
    "checks" in body &&
    /** @type {{ checks?: { sqlite?: { status?: string } } }} */ (body).checks
      ?.sqlite?.status === "ok";
  return Boolean(sqliteOk || checksSqlite);
}

export async function waitForNextHealth(
  healthUrl,
  timeoutMs = 300_000,
  intervalMs = 1500
) {
  const started = Date.now();
  while (Date.now() - started < timeoutMs) {
    try {
      const response = await fetch(healthUrl, {
        signal: AbortSignal.timeout(8000),
        headers: healthFetchHeaders(),
      });
      const body = await response.json().catch(() => null);
      if (isHealthAcceptable(response, body)) {
        return { ok: true, health: body };
      }
    } catch {
      // retry
    }
    await sleep(intervalMs);
  }
  return { ok: false, error: "next_health_timeout" };
}

/**
 * @param {string} healthUrl
 */
export async function fetchNextHealth(healthUrl) {
  const response = await fetch(healthUrl, {
    signal: AbortSignal.timeout(10_000),
    headers: healthFetchHeaders(),
  });
  const health = await response.json();
  return { status: response.status, health };
}

const ISO_HOME = join(PROJECT_ROOT, ".build-home");

/**
 * HOME isolé pour le build : évite EPERM sur junctions Windows
 * sous Documents (ex. « Ma musique »).
 */
function ensureIsoHome() {
  for (const p of [
    ISO_HOME,
    join(ISO_HOME, "Documents"),
    join(ISO_HOME, "AppData", "Local"),
    join(ISO_HOME, "AppData", "Roaming"),
  ]) {
    mkdirSync(p, { recursive: true });
  }
}

function buildEnv() {
  ensureIsoHome();
  return {
    ...process.env,
    USERPROFILE: ISO_HOME,
    HOME: ISO_HOME,
    APPDATA: join(ISO_HOME, "AppData", "Roaming"),
    LOCALAPPDATA: join(ISO_HOME, "AppData", "Local"),
    NEXT_TELEMETRY_DISABLED: "1",
  };
}

/**
 * Lance `npm run build` si le build production est absent.
 */
export function ensureNextJsProductionBuild() {
  if (existsSync(BUILD_ID_PATH)) {
    return { ok: true, built: false };
  }

  console.log("[boot] Build Next.js absent — npm run build (peut prendre plusieurs minutes)…");
  const npmCmd = process.platform === "win32" ? "npm.cmd" : "npm";
  const result = spawnSync(npmCmd, ["run", "build"], {
    cwd: PROJECT_ROOT,
    stdio: "inherit",
    shell: process.platform === "win32",
    windowsHide: true,
    env: buildEnv(),
  });

  if (result.status !== 0) {
    return {
      ok: false,
      error: "next_build_failed",
      message: "npm run build a échoué",
    };
  }

  if (!existsSync(BUILD_ID_PATH)) {
    return {
      ok: false,
      error: "next_build_missing",
      message: "Build terminé mais .next/BUILD_ID introuvable",
    };
  }

  console.log("[boot] Build Next.js terminé");
  return { ok: true, built: true };
}

/**
 * Fallback si le build prod échoue : `npm run dev` détaché.
 */
export async function ensureNextJsDev() {
  if (await isNextJsListening()) {
    console.log("[boot] Next.js déjà actif sur :3000 (dev ou autre)");
    return { ok: true, started: false, mode: "dev" };
  }

  const npmCmd = process.platform === "win32" ? "npm.cmd" : "npm";
  mkdirSync(dirname(LOG_PATH), { recursive: true });
  const logFd = openSync(LOG_PATH, "a");

  console.log("[boot] Fallback Next.js dev (127.0.0.1:3000)…");
  nextProcess = spawn(npmCmd, ["run", "dev", "--", "-H", "127.0.0.1", "-p", "3000"], {
    cwd: PROJECT_ROOT,
    env: { ...process.env, NEXT_TELEMETRY_DISABLED: "1" },
    detached: true,
    stdio: ["ignore", logFd, logFd],
    shell: process.platform === "win32",
    windowsHide: process.platform === "win32",
  });

  nextProcess.on("error", (error) => {
    console.error(
      "[boot] Next.js dev spawn error:",
      error instanceof Error ? error.message : error
    );
  });

  nextProcess.unref();
  if (nextProcess.pid) {
    writeNextPid(nextProcess.pid);
  }

  // Turbopack compile à froid — laisser plus de marge qu'en prod.
  for (let i = 0; i < 40; i++) {
    await sleep(1500);
    if (await isNextJsListening()) {
      return { ok: true, started: true, mode: "dev" };
    }
  }

  return {
    ok: false,
    error: "next_dev_start_failed",
    message: "Next.js dev ne répond pas sur le port 3000",
  };
}

function writeNextPid(pid) {
  mkdirSync(dirname(PID_PATH), { recursive: true });
  writeFileSync(
    PID_PATH,
    JSON.stringify({ pid, startedAt: Date.now() })
  );
}

function clearNextPid() {
  if (existsSync(PID_PATH)) {
    try {
      unlinkSync(PID_PATH);
    } catch {
      // ignore
    }
  }
}

function readNextPid() {
  if (!existsSync(PID_PATH)) return null;
  try {
    const parsed = JSON.parse(readFileSync(PID_PATH, "utf8"));
    const pid = Number(parsed.pid ?? 0);
    return pid > 0 ? pid : null;
  } catch {
    return null;
  }
}

/**
 * Démarre Next.js production si absent.
 * @param {{ forceRestart?: boolean }} [options]
 */
export async function ensureNextJsProduction(options = {}) {
  if (await isNextJsListening()) {
    if (options.forceRestart) {
      const stopped = await stopNextJsProduction();
      if (!stopped.ok) {
        return { ok: false, error: "next_stop_failed", message: stopped.error };
      }
    } else {
      console.log("[boot] Next.js déjà actif sur :3000");
      return { ok: true, started: false };
    }
  }

  const build = ensureNextJsProductionBuild();
  if (!build.ok) {
    console.warn(
      `[boot] Build prod impossible (${build.error}) — bascule vers next dev…`
    );
    return ensureNextJsDev();
  }

  const nextBin = join(
    PROJECT_ROOT,
    "node_modules",
    "next",
    "dist",
    "bin",
    "next"
  );

  mkdirSync(dirname(LOG_PATH), { recursive: true });
  const logFd = openSync(LOG_PATH, "a");

  console.log("[boot] Démarrage Next.js production (127.0.0.1:3000)…");
  nextProcess = spawn(
    resolveNodeExecutable(),
    [nextBin, "start", "-p", "3000", "-H", "127.0.0.1"],
    {
      cwd: PROJECT_ROOT,
      env: process.env,
      detached: true,
      stdio: ["ignore", logFd, logFd],
      windowsHide: process.platform === "win32",
    }
  );

  nextProcess.on("error", (error) => {
    console.error(
      "[boot] Next.js spawn error:",
      error instanceof Error ? error.message : error
    );
  });

  nextProcess.unref();
  if (nextProcess.pid) {
    writeNextPid(nextProcess.pid);
  }

  for (let i = 0; i < 10; i++) {
    await sleep(1500);
    if (await isNextJsListening()) {
      return { ok: true, started: true, mode: "production" };
    }
  }

  console.warn("[boot] next start n'écoute pas — bascule vers next dev…");
  return ensureNextJsDev();
}

/**
 * Arrête Next.js (processus boot ou PID sur :3000).
 */
export async function stopNextJsProduction() {
  const pidFromFile = readNextPid();
  const pid = nextProcess?.pid ?? pidFromFile;

  if (pid && isPidAlive(pid)) {
    try {
      process.kill(pid);
    } catch {
      // ignore
    }
    nextProcess = null;
    clearNextPid();
    await sleep(1500);
    if (!(await isNextJsListening())) {
      return { ok: true, method: "boot_process" };
    }
  }

  if (nextProcess) {
    nextProcess.kill("SIGTERM");
    nextProcess = null;
    clearNextPid();
    await sleep(1500);
    if (!(await isNextJsListening())) {
      return { ok: true, method: "boot_process" };
    }
  }

  if (!(await isNextJsListening())) {
    return { ok: true, method: "already_stopped" };
  }

  if (process.platform === "win32") {
    const result = spawnSync(
      "powershell",
      [
        "-NoProfile",
        "-Command",
        "$pids = Get-NetTCPConnection -LocalPort 3000 -State Listen -ErrorAction SilentlyContinue | Select-Object -ExpandProperty OwningProcess -Unique; if (-not $pids) { exit 1 }; foreach ($p in $pids) { Stop-Process -Id $p -Force -ErrorAction SilentlyContinue }; exit 0",
      ],
      { encoding: "utf8", timeout: 15_000 }
    );
    if (result.status === 0) {
      await sleep(1000);
      if (!(await isNextJsListening())) {
        return { ok: true, method: "kill_port_win" };
      }
    }
  }

  return { ok: false, error: "next_stop_failed" };
}
