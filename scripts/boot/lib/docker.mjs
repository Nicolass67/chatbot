import { spawn, spawnSync } from "node:child_process";
import { existsSync } from "node:fs";
import { join } from "node:path";
import { sleep } from "./network.mjs";

const DOCKER_DESKTOP_PATHS = [
  join(
    process.env.ProgramFiles ?? "C:\\Program Files",
    "Docker",
    "Docker",
    "Docker Desktop.exe"
  ),
  join(
    process.env["ProgramFiles(x86)"] ?? "C:\\Program Files (x86)",
    "Docker",
    "Docker",
    "Docker Desktop.exe"
  ),
];

export function dockerInfoExitCode() {
  const result = spawnSync("docker", ["info"], {
    encoding: "utf8",
    timeout: 20_000,
    stdio: ["ignore", "pipe", "pipe"],
    shell: process.platform === "win32",
    windowsHide: process.platform === "win32",
  });
  return result.status ?? 1;
}

export function isDockerReady() {
  return dockerInfoExitCode() === 0;
}

function findDockerDesktopExe() {
  return DOCKER_DESKTOP_PATHS.find((p) => existsSync(p)) ?? null;
}

/**
 * @param {number} timeoutMs
 */
export async function ensureDockerReady(timeoutMs = 300_000) {
  if (isDockerReady()) {
    console.log("[boot] Docker déjà prêt");
    return { ok: true, started: false };
  }

  const exe = findDockerDesktopExe();
  if (!exe) {
    return { ok: false, error: "docker_desktop_not_found" };
  }

  console.log("[boot] Démarrage Docker Desktop…");
  spawn(exe, [], { detached: true, stdio: "ignore" }).unref();

  const started = Date.now();
  while (Date.now() - started < timeoutMs) {
    if (isDockerReady()) {
      console.log("[boot] Docker prêt");
      return { ok: true, started: true };
    }
    await sleep(2000);
  }

  return { ok: false, error: "docker_timeout" };
}
