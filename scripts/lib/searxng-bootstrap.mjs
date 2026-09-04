import { spawnSync } from "node:child_process";
import { loadEnvLocal, getSearxngUrl, PROJECT_ROOT } from "./env.mjs";
import {
  checkSearxngHealth,
  waitForSearxngHealth,
} from "./searxng-health.mjs";

const COMPOSE_FILE = "docker-compose.searxng.yml";

export function isDockerAvailable() {
  try {
    const result = spawnSync("docker", ["info"], {
      encoding: "utf8",
      timeout: 15_000,
      stdio: ["ignore", "pipe", "pipe"],
    });
    return result.status === 0;
  } catch {
    return false;
  }
}

function dockerCompose(args) {
  return spawnSync("docker", ["compose", "-f", COMPOSE_FILE, ...args], {
    cwd: PROJECT_ROOT,
    encoding: "utf8",
    timeout: 120_000,
    stdio: ["ignore", "pipe", "pipe"],
    shell: process.platform === "win32",
  });
}

export async function bootstrapSearxng(options = {}) {
  loadEnvLocal();
  const baseUrl = getSearxngUrl();
  const fatal = options.fatal ?? false;
  const waitTimeoutMs = options.waitTimeoutMs ?? 60_000;

  console.log(`[Web] Vérification SearXNG (${baseUrl})…`);
  const initial = await checkSearxngHealth(baseUrl, 4000);

  if (initial.status === "connected") {
    console.log(`✓ SearXNG déjà disponible (${baseUrl})`);
    return { ok: true, health: initial, started: false };
  }

  if (!isDockerAvailable()) {
    const message =
      "Docker indisponible — démarrez Docker Desktop ou lancez SearXNG manuellement";
    console.warn(`✕ ${message}`);
    if (fatal) {
      return { ok: false, health: initial, started: false, message };
    }
    return { ok: false, health: initial, started: false, message };
  }

  console.log("◌ SearXNG absent — démarrage via Docker Compose…");
  const up = dockerCompose(["up", "-d"]);
  if (up.status !== 0) {
    const message = `Échec docker compose : ${up.stderr || up.stdout || "erreur inconnue"}`;
    console.error(`✕ ${message}`);
    return { ok: false, health: initial, started: true, message };
  }

  console.log(`◌ Attente SearXNG (timeout ${Math.round(waitTimeoutMs / 1000)}s)…`);
  const final = await waitForSearxngHealth(baseUrl, {
    timeoutMs: waitTimeoutMs,
    intervalMs: 2000,
    checkTimeoutMs: 8000,
    onProgress: (elapsedMs, last) => {
      const secs = Math.round(elapsedMs / 1000);
      const hint =
        last.status === "starting"
          ? " (démarrage…)"
          : last.status === "unavailable"
            ? " (en attente…)"
            : "";
      process.stdout.write(`\r◌ Attente SearXNG… ${secs}s${hint}   `);
    },
  });
  process.stdout.write("\n");

  if (final.status === "connected") {
    console.log(`✓ SearXNG prêt (${baseUrl})`);
    return { ok: true, health: final, started: true };
  }

  const message = `SearXNG n'a pas répondu à temps — ${final.message ?? "timeout"}`;
  console.error(`✕ ${message}`);
  return { ok: false, health: final, started: true, message };
}

export function stopSearxngStack() {
  loadEnvLocal();
  if (!isDockerAvailable()) {
    console.error("✕ Docker indisponible");
    return { ok: false };
  }
  console.log("◌ Arrêt SearXNG…");
  const down = dockerCompose(["down"]);
  if (down.status !== 0) {
    console.error(`✕ ${down.stderr || down.stdout}`);
    return { ok: false };
  }
  console.log("✓ SearXNG arrêté");
  return { ok: true };
}

export async function printSearxngStatus() {
  loadEnvLocal();
  const baseUrl = getSearxngUrl();
  const docker = isDockerAvailable();
  const health = await checkSearxngHealth(baseUrl, 5000);

  console.log(`URL      : ${baseUrl}`);
  console.log(`Docker   : ${docker ? "disponible" : "indisponible"}`);
  console.log(`SearXNG  : ${health.status}`);
  if (health.message) console.log(`Détail   : ${health.message}`);
  if (health.resultCount !== undefined) {
    console.log(`Résultats: ${health.resultCount} (requête test)`);
  }

  return { docker, health };
}
