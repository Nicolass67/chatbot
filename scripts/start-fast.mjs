#!/usr/bin/env node
/**
 * Build + start Next en production (démarrage iPhone bien plus rapide que `next dev`).
 * Contourne les junctions Windows cassées sous Documents (EPERM « Ma musique »).
 */
import { spawn, spawnSync } from "node:child_process";
import { existsSync, mkdirSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const isoHome = join(root, ".build-home");
const buildId = join(root, ".next", "BUILD_ID");
const npmCmd = process.platform === "win32" ? "npm.cmd" : "npm";

function loadEnvLocal() {
  try {
    const raw = readFileSync(join(root, ".env.local"), "utf8");
    for (const line of raw.split(/\r?\n/)) {
      const m = line.match(/^([^#=]+)=(.*)$/);
      if (!m) continue;
      const key = m[1].trim();
      if (!process.env[key]) process.env[key] = m[2].trim();
    }
  } catch {
    /* optional */
  }
}

loadEnvLocal();

function ensureIsoHome() {
  for (const p of [
    isoHome,
    join(isoHome, "Documents"),
    join(isoHome, "AppData", "Local"),
    join(isoHome, "AppData", "Roaming"),
  ]) {
    mkdirSync(p, { recursive: true });
  }
}

function buildEnv() {
  return {
    ...process.env,
    USERPROFILE: isoHome,
    HOME: isoHome,
    APPDATA: join(isoHome, "AppData", "Roaming"),
    LOCALAPPDATA: join(isoHome, "AppData", "Local"),
    NEXT_TELEMETRY_DISABLED: "1",
  };
}

console.log("[fast] Build production Next.js…");
ensureIsoHome();
const build = spawnSync(npmCmd, ["run", "build"], {
  cwd: root,
  env: buildEnv(),
  stdio: "inherit",
  shell: process.platform === "win32",
});
if (build.status !== 0 || !existsSync(buildId)) {
  console.error("[fast] Build échoué");
  process.exit(1);
}

console.log("[fast] Arrêt éventuel du port 3000…");
if (process.platform === "win32") {
  spawnSync(
    "powershell",
    [
      "-NoProfile",
      "-Command",
      "Get-NetTCPConnection -LocalPort 3000 -State Listen -ErrorAction SilentlyContinue | ForEach-Object { if ($_.OwningProcess -gt 0) { Stop-Process -Id $_.OwningProcess -Force -ErrorAction SilentlyContinue } }",
    ],
    { stdio: "ignore" }
  );
}

await new Promise((r) => setTimeout(r, 1500));

console.log("[fast] next start…");
const child = spawn(npmCmd, ["run", "start"], {
  cwd: root,
  env: { ...process.env, NODE_ENV: "production" },
  stdio: "inherit",
  shell: process.platform === "win32",
});

const healthToken = process.env.HEALTH_CHECK_TOKEN;
const started = Date.now();
while (Date.now() - started < 120_000) {
  try {
    const headers = {};
    if (healthToken) headers.Authorization = `Bearer ${healthToken}`;
    const res = await fetch("http://127.0.0.1:3000/api/health", {
      headers,
      signal: AbortSignal.timeout(5000),
    });
    if (res.ok) {
      console.log("[fast] Health OK — warm /chat/new…");
      await fetch("http://127.0.0.1:3000/chat/new", {
        signal: AbortSignal.timeout(15000),
      }).catch(() => {});
      console.log("[fast] Prêt — http://127.0.0.1:3000 (mode production)");
      break;
    }
  } catch {
    /* retry */
  }
  await new Promise((r) => setTimeout(r, 1000));
}

child.on("exit", (code) => process.exit(code ?? 0));
