/**
 * Client LM Studio isolé (benchmark only) — ne touche pas aux settings app.
 */
import { spawnSync } from "node:child_process";

const LM_V1 = (
  process.env.LM_STUDIO_BASE_URL || "http://127.0.0.1:1234/v1"
).replace(/\/$/, "");
const LM_ROOT = LM_V1.replace(/\/v1\/?$/, "");
const KEY = process.env.LM_STUDIO_API_KEY || "lm-studio";

function headers() {
  return {
    Authorization: `Bearer ${KEY}`,
    "Content-Type": "application/json",
  };
}

export function estimateTokens(text) {
  return Math.ceil(String(text || "").length / 4);
}

export function normalizeModelKey(id) {
  return String(id || "")
    .trim()
    .toLowerCase()
    .replace(/@.*$/, "")
    .replace(/^.*\//, "");
}

export function modelKeysMatch(a, b) {
  if (!a || !b) return false;
  return a === b || normalizeModelKey(a) === normalizeModelKey(b);
}

export async function fetchNativeModels() {
  const res = await fetch(`${LM_ROOT}/api/v1/models`, {
    headers: headers(),
    signal: AbortSignal.timeout(15_000),
  });
  if (!res.ok) throw new Error(`GET /api/v1/models ${res.status}`);
  const data = await res.json();
  return data.models ?? [];
}

export async function listAvailableLlms() {
  const models = await fetchNativeModels();
  return models
    .filter((m) => m.type === "llm")
    .map((m) => ({
      key: m.key,
      displayName: m.display_name,
      quantization: m.quantization?.name ?? null,
      bitsPerWeight: m.quantization?.bits_per_weight ?? null,
      params: m.params_string ?? null,
      architecture: m.architecture ?? null,
      maxContextLength: m.max_context_length ?? null,
      publisher: m.publisher ?? null,
      loadedInstances: (m.loaded_instances ?? []).map((i) => ({
        id: i.id,
        config: i.config ?? null,
      })),
      capabilities: m.capabilities ?? null,
    }));
}

export async function listLoadedInstances() {
  const models = await fetchNativeModels();
  const out = [];
  for (const m of models) {
    if (m.type !== "llm") continue;
    for (const inst of m.loaded_instances ?? []) {
      out.push({
        modelKey: m.key,
        instanceId: inst.id,
        displayName: m.display_name,
        quantization: m.quantization?.name ?? null,
        config: inst.config ?? null,
      });
    }
  }
  return out;
}

function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

function runLms(args, timeoutMs = 600_000) {
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

export async function unloadAll() {
  const before = await listLoadedInstances();
  if (before.length === 0) return { ok: true, unloaded: [] };

  const cli = runLms(["unload", "--all"], 180_000);
  await sleep(800);

  let remaining = await listLoadedInstances();
  for (const inst of remaining) {
    const res = await fetch(`${LM_ROOT}/api/v1/models/unload`, {
      method: "POST",
      headers: headers(),
      body: JSON.stringify({ instance_id: inst.instanceId }),
      signal: AbortSignal.timeout(120_000),
    });
    if (!res.ok) {
      const text = await res.text();
      return {
        ok: false,
        error: `unload_failed_${res.status}`,
        detail: text.slice(0, 300),
        unloaded: before.map((b) => b.modelKey),
      };
    }
  }

  for (let i = 0; i < 60; i++) {
    remaining = await listLoadedInstances();
    if (remaining.length === 0) {
      return {
        ok: true,
        unloaded: before.map((b) => b.modelKey),
        cliUnload: cli.ok,
      };
    }
    await sleep(500);
  }
  return {
    ok: false,
    error: "unload_timeout",
    remaining: remaining.map((r) => r.modelKey),
  };
}

export async function loadModel(modelKey, loadConfig = {}) {
  const t0 = Date.now();
  const body = {
    model: modelKey,
    echo_load_config: true,
  };
  if (loadConfig.contextLength != null)
    body.context_length = loadConfig.contextLength;
  if (loadConfig.evalBatchSize != null)
    body.eval_batch_size = loadConfig.evalBatchSize;
  if (loadConfig.flashAttention != null)
    body.flash_attention = loadConfig.flashAttention;
  if (loadConfig.offloadKvCacheToGpu != null)
    body.offload_kv_cache_to_gpu = loadConfig.offloadKvCacheToGpu;
  if (loadConfig.parallel != null) body.parallel = loadConfig.parallel;
  // Optional MoE / experimental fields — only sent if caller provides them.
  // If the server rejects them, we fall back to CLI without inventing support.
  if (loadConfig.numExperts != null) body.num_experts = loadConfig.numExperts;
  // gpuOffloadRatio is CLI-only (`lms load --gpu`); native API rejects the key.

  let apiResult = null;
  let apiError = null;
  try {
    const res = await fetch(`${LM_ROOT}/api/v1/models/load`, {
      method: "POST",
      headers: headers(),
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(600_000),
    });
    const text = await res.text();
    if (!res.ok) {
      apiError = `${res.status} ${text.slice(0, 400)}`;
    } else {
      apiResult = JSON.parse(text);
    }
  } catch (e) {
    apiError = e instanceof Error ? e.message : String(e);
  }

  // Prefer CLI fallback on API errors / connection resets (large MoE loads).
  if (apiError) {
    const args = ["load", modelKey, "-y"];
    if (loadConfig.contextLength != null) {
      args.push("-c", String(loadConfig.contextLength));
    }
    if (loadConfig.parallel != null) {
      args.push("--parallel", String(loadConfig.parallel));
    }
    // CLI-supported GPU offload: "off" | "max" | 0..1
    const gpu =
      loadConfig.gpuOffloadRatio == null
        ? "max"
        : loadConfig.gpuOffloadRatio === 0
          ? "off"
          : loadConfig.gpuOffloadRatio === 1
            ? "max"
            : String(loadConfig.gpuOffloadRatio);
    args.push("--gpu", gpu);
    let cli = runLms(args, 600_000);
    // One retry after short pause (LM Studio sometimes resets mid-load).
    if (!cli.ok) {
      await sleep(2000);
      cli = runLms(args, 600_000);
    }
    if (!cli.ok) {
      return {
        ok: false,
        error: apiError,
        cliError: (cli.stderr || cli.stdout).slice(0, 400),
        loadTimeMs: Date.now() - t0,
      };
    }
  }

  let loaded = null;
  for (let i = 0; i < 180; i++) {
    try {
      const instances = await listLoadedInstances();
      const match = instances.find((x) => modelKeysMatch(x.modelKey, modelKey));
      if (instances.length === 1 && match) {
        loaded = match;
        break;
      }
      if (instances.length > 1) {
        // Transient dual-load during swap — wait a bit before failing.
        if (i < 10) {
          await sleep(1000);
          continue;
        }
        return {
          ok: false,
          error: "multiple_models_loaded",
          loaded: instances.map((x) => x.modelKey),
          loadTimeMs: Date.now() - t0,
        };
      }
    } catch {
      // API may briefly drop during model swap; keep polling.
    }
    await sleep(1000);
  }

  if (!loaded) {
    return {
      ok: false,
      error: "load_confirm_timeout",
      apiError,
      loadTimeMs: Date.now() - t0,
    };
  }

  return {
    ok: true,
    modelKey: loaded.modelKey,
    instanceId: loaded.instanceId,
    quantization: loaded.quantization,
    requestedConfig: {
      contextLength: loadConfig.contextLength ?? null,
      evalBatchSize: loadConfig.evalBatchSize ?? null,
      flashAttention: loadConfig.flashAttention ?? null,
      offloadKvCacheToGpu: loadConfig.offloadKvCacheToGpu ?? null,
      parallel: loadConfig.parallel ?? null,
    },
    echoLoadConfig: apiResult?.load_config ?? null,
    effectiveConfig: loaded.config,
    loadTimeSeconds: apiResult?.load_time_seconds ?? null,
    loadTimeMs: Date.now() - t0,
    apiErrorFallbackUsed: Boolean(apiError),
  };
}

export async function chatCompletion({
  model,
  messages,
  maxTokens = 256,
  temperature = 0.1,
  timeoutMs = 180_000,
}) {
  const body = {
    model,
    messages,
    temperature,
    max_tokens: maxTokens,
    stream: false,
    reasoning_effort: "none",
  };
  const t0 = Date.now();
  try {
    const res = await fetch(`${LM_V1}/chat/completions`, {
      method: "POST",
      headers: headers(),
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(timeoutMs),
    });
    const raw = await res.text();
    const ms = Date.now() - t0;
    if (!res.ok) {
      return {
        ok: false,
        error: `${res.status} ${raw.slice(0, 300)}`,
        content: "",
        ms,
        usage: null,
        respondedModel: null,
      };
    }
    const data = JSON.parse(raw);
    const msg = data.choices?.[0]?.message ?? {};
    const content = String(msg.content ?? "").trim();
    const usage = data.usage ?? null;
    const completionTokens = usage?.completion_tokens ?? null;
    const promptTokens = usage?.prompt_tokens ?? null;
    const genTokPerSec =
      completionTokens && ms > 0
        ? Number(((completionTokens / ms) * 1000).toFixed(2))
        : null;
    return {
      ok: content.length > 0,
      error: null,
      content,
      contentPreview: content.slice(0, 400),
      ms,
      usage,
      promptTokens,
      completionTokens,
      genTokPerSec,
      respondedModel: data.model ?? null,
      finishReason: data.choices?.[0]?.finish_reason ?? null,
    };
  } catch (e) {
    return {
      ok: false,
      error: e instanceof Error ? e.message : String(e),
      content: "",
      ms: Date.now() - t0,
      usage: null,
      respondedModel: null,
    };
  }
}
