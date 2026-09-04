import { spawn, spawnSync } from "node:child_process";
import { existsSync } from "node:fs";
import { join } from "node:path";
import { sleep } from "./network.mjs";
import { isTcpPortOpen } from "./network.mjs";

const LM_API_BASE = "http://127.0.0.1:1234";
const LM_API_KEY = "lm-studio";

const LM_STUDIO_PATHS = [
  join(
    process.env.LOCALAPPDATA ?? "",
    "Programs",
    "LM Studio",
    "LM Studio.exe"
  ),
  join(process.env.ProgramFiles ?? "C:\\Program Files", "LM Studio", "LM Studio.exe"),
];

export function isLmsCliAvailable() {
  const lms = spawnSync("lms", ["--version"], {
    encoding: "utf8",
    timeout: 10_000,
    shell: process.platform === "win32",
  });
  return lms.status === 0;
}

function runLmsSync(args, timeoutMs = 300_000) {
  const result = spawnSync("lms", args, {
    encoding: "utf8",
    timeout: timeoutMs,
    shell: process.platform === "win32",
    stdio: ["ignore", "pipe", "pipe"],
    windowsHide: true,
  });
  return {
    ok: result.status === 0,
    stdout: result.stdout ?? "",
    stderr: result.stderr ?? "",
    status: result.status ?? 1,
  };
}

export async function lmStudioModelsStatus() {
  try {
    const response = await fetch(`${LM_API_BASE}/api/v1/models`, {
      headers: { Authorization: `Bearer ${LM_API_KEY}` },
      signal: AbortSignal.timeout(5000),
    });
    return response.status;
  } catch {
    return 0;
  }
}

export async function isLmStudioApiReady() {
  return (await lmStudioModelsStatus()) === 200;
}

function findLmStudioExe() {
  return LM_STUDIO_PATHS.find((p) => p && existsSync(p)) ?? null;
}

async function tryStartLmStudioServer() {
  if (isLmsCliAvailable()) {
    console.log("[boot] Démarrage serveur LM Studio via CLI lms…");
    spawn("lms", ["server", "start"], {
      detached: true,
      stdio: "ignore",
      shell: process.platform === "win32",
    }).unref();
    return true;
  }

  const exe = findLmStudioExe();
  if (!exe) return false;
  console.log("[boot] Lancement LM Studio (GUI) — activez le serveur local si besoin…");
  spawn(exe, [], { detached: true, stdio: "ignore" }).unref();
  return true;
}

/** @param {number} timeoutMs */
export async function ensureLmStudioServer(timeoutMs = 120_000) {
  if (await isLmStudioApiReady()) {
    console.log("[boot] LM Studio API déjà disponible");
    return { ok: true, started: false };
  }

  await tryStartLmStudioServer();

  const started = Date.now();
  while (Date.now() - started < timeoutMs) {
    if (await isLmStudioApiReady()) {
      console.log("[boot] LM Studio API prête");
      return { ok: true, started: true };
    }
    await sleep(1000);
  }

  return { ok: false, error: "lm_studio_api_timeout" };
}

async function fetchModelsPayload(retries = 5) {
  let lastError;
  for (let attempt = 0; attempt < retries; attempt += 1) {
    try {
      const response = await fetch(`${LM_API_BASE}/api/v1/models`, {
        headers: { Authorization: `Bearer ${LM_API_KEY}` },
        signal: AbortSignal.timeout(15_000),
      });
      if (!response.ok) {
        throw new Error(`models_http_${response.status}`);
      }
      return response.json();
    } catch (error) {
      lastError = error;
      if (attempt < retries - 1) {
        await sleep(1000);
      }
    }
  }
  throw lastError instanceof Error ? lastError : new Error("models_fetch_failed");
}

/** @returns {Promise<Array<{ modelKey: string, instanceId: string }>>} */
export async function listLoadedLlmInstances() {
  const data = await fetchModelsPayload();
  /** @type {Array<{ modelKey: string, instanceId: string }>} */
  const instances = [];
  for (const model of data.models ?? []) {
    if (model.type !== "llm") continue;
    for (const inst of model.loaded_instances ?? []) {
      instances.push({ modelKey: model.key, instanceId: inst.id });
    }
  }
  return instances;
}

/** @param {string} instanceId @param {number} timeoutMs */
async function unloadModelInstance(instanceId, timeoutMs = 120_000) {
  const unloadRes = await fetch(`${LM_API_BASE}/api/v1/models/unload`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${LM_API_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ instance_id: instanceId }),
    signal: AbortSignal.timeout(timeoutMs),
  });

  if (!unloadRes.ok) {
    const text = await unloadRes.text();
    return {
      ok: false,
      error: `unload_failed_${unloadRes.status}`,
      detail: text.slice(0, 200),
    };
  }

  const started = Date.now();
  while (Date.now() - started < timeoutMs) {
    const loaded = await listLoadedLlmInstances();
    if (!loaded.some((inst) => inst.instanceId === instanceId)) {
      return { ok: true };
    }
    await sleep(500);
  }

  return { ok: false, error: "unload_timeout" };
}

function unloadAllViaLmsCli(timeoutMs = 180_000) {
  if (!isLmsCliAvailable()) {
    return { ok: true, used: false };
  }

  const ps = runLmsSync(["ps"], 15_000);
  const output = `${ps.stdout}\n${ps.stderr}`.trim();
  if (!ps.ok || !output || /no models loaded/i.test(output)) {
    return { ok: true, used: false };
  }

  console.log("[boot] lms unload --all…");
  const unload = runLmsSync(["unload", "--all"], timeoutMs);
  if (!unload.ok) {
    return {
      ok: false,
      used: true,
      error: "lms_unload_all_failed",
      detail: unload.stderr || unload.stdout,
      status: unload.status,
    };
  }
  return { ok: true, used: true };
}

export async function unloadAllLoadedModels() {
  const cli = unloadAllViaLmsCli();
  if (!cli.ok) {
    return { ok: false, error: cli.error, detail: cli.detail };
  }

  let loaded = await listLoadedLlmInstances();
  if (loaded.length === 0) {
    return { ok: true, unloadedCount: 0 };
  }

  console.log(`[boot] Déchargement API de ${loaded.length} modèle(s) restant(s)…`);
  const results = await Promise.all(
    loaded.map((inst) =>
      unloadModelInstance(inst.instanceId).then((result) => ({ inst, result }))
    )
  );

  let unloadedCount = 0;
  for (const { inst, result } of results) {
    if (!result.ok) {
      return {
        ok: false,
        error: result.error,
        detail: result.detail,
        failedModel: inst.modelKey,
        unloadedCount,
      };
    }
    unloadedCount += 1;
  }

  loaded = await listLoadedLlmInstances();
  if (loaded.length > 0) {
    return {
      ok: false,
      error: "models_still_loaded",
      remaining: loaded.map((inst) => inst.modelKey),
      unloadedCount,
    };
  }

  return { ok: true, unloadedCount };
}

async function loadModelViaApi(modelKey, timeoutMs) {
  const loadRes = await fetch(`${LM_API_BASE}/api/v1/models/load`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${LM_API_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ model: modelKey }),
    signal: AbortSignal.timeout(timeoutMs),
  });

  if (!loadRes.ok) {
    const text = await loadRes.text();
    return {
      ok: false,
      error: `load_failed_${loadRes.status}`,
      detail: text.slice(0, 200),
    };
  }
  return { ok: true };
}

async function waitForSingleModel(modelKey, timeoutMs) {
  const started = Date.now();
  while (Date.now() - started < timeoutMs) {
    const loaded = await listLoadedLlmInstances();
    if (loaded.length === 1 && loaded[0].modelKey === modelKey) {
      console.log(`[boot] Modèle prêt : ${modelKey}`);
      return { ok: true, loaded: true, instanceId: loaded[0].instanceId };
    }
    if (loaded.length > 1) {
      return { ok: false, error: "multiple_models_loaded", loaded };
    }
    await sleep(1000);
  }
  return { ok: false, error: "model_load_timeout" };
}

/**
 * @param {string} modelKey
 * @param {{ timeoutMs?: number, forceReload?: boolean }} [options]
 */
export async function ensureModelLoaded(modelKey, options = {}) {
  const timeoutMs = options.timeoutMs ?? 600_000;
  const forceReload = options.forceReload ?? false;

  let loaded;
  try {
    loaded = await listLoadedLlmInstances();
  } catch (error) {
    return {
      ok: false,
      error: error instanceof Error ? error.message : "models_fetch_failed",
    };
  }

  const onlyTarget =
    loaded.length === 1 && loaded[0].modelKey === modelKey && !forceReload;
  if (onlyTarget) {
    console.log(`[boot] Modèle déjà chargé : ${modelKey}`);
    return { ok: true, loaded: false, instanceId: loaded[0].instanceId };
  }

  if (loaded.length > 0) {
    const unloaded = await unloadAllLoadedModels();
    if (!unloaded.ok) {
      return unloaded;
    }
  }

  console.log(`[boot] Chargement modèle ${modelKey}…`);
  if (isLmsCliAvailable()) {
    const load = runLmsSync(["load", modelKey, "-y"], timeoutMs);
    if (!load.ok) {
      const stillLoaded = await listLoadedLlmInstances();
      if (stillLoaded.length > 0) {
        console.warn(
          `[boot] Chargement ${modelKey} échoué — utilisation de ${stillLoaded[0].modelKey}`
        );
        return {
          ok: true,
          loaded: false,
          instanceId: stillLoaded[0].instanceId,
          warning: "model_load_fallback",
        };
      }
      return {
        ok: false,
        error: "lms_load_failed",
        detail: load.stderr || load.stdout,
      };
    }
  } else {
    const apiLoad = await loadModelViaApi(modelKey, timeoutMs);
    if (!apiLoad.ok) {
      return apiLoad;
    }
  }

  return waitForSingleModel(modelKey, timeoutMs);
}

export async function isLmStudioPortListening() {
  return isTcpPortOpen("127.0.0.1", 1234);
}
