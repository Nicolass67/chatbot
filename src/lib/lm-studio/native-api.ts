import { getEnv } from "@/lib/config/env";

export interface LoadedModelInstance {
  id: string;
  config?: {
    context_length?: number;
    eval_batch_size?: number;
    parallel?: number;
    flash_attention?: boolean;
  };
}

export interface NativeModelRecord {
  type: "llm" | "embedding" | string;
  key: string;
  display_name: string;
  loaded_instances?: LoadedModelInstance[];
}

export interface LoadedLlmInstance {
  modelKey: string;
  instanceId: string;
  displayName: string;
}

function nativeBaseUrl(): string {
  return getEnv()
    .LM_STUDIO_BASE_URL.replace(/\/v1\/?$/, "")
    .replace(/\/$/, "");
}

function authHeaders(): Record<string, string> {
  return {
    Authorization: `Bearer ${getEnv().LM_STUDIO_API_KEY}`,
    "Content-Type": "application/json",
  };
}

export async function fetchNativeModels(
  signal?: AbortSignal
): Promise<NativeModelRecord[]> {
  const res = await fetch(`${nativeBaseUrl()}/api/v1/models`, {
    signal: signal ?? AbortSignal.timeout(10_000),
    headers: authHeaders(),
  });
  if (!res.ok) {
    throw new Error(`LM Studio GET /api/v1/models failed: ${res.status}`);
  }
  const data = (await res.json()) as { models?: NativeModelRecord[] };
  return data.models ?? [];
}

export function getLoadedLlmInstances(
  models: NativeModelRecord[]
): LoadedLlmInstance[] {
  const instances: LoadedLlmInstance[] = [];
  for (const model of models) {
    if (model.type !== "llm") continue;
    for (const inst of model.loaded_instances ?? []) {
      instances.push({
        modelKey: model.key,
        instanceId: inst.id,
        displayName: model.display_name,
      });
    }
  }
  return instances;
}

export function findModelDisplayName(
  models: NativeModelRecord[],
  modelKey: string
): string {
  const match = models.find((m) => m.key === modelKey);
  return match?.display_name ?? modelKey.split("/").pop() ?? modelKey;
}

export async function loadNativeModel(
  modelKey: string,
  options?: { contextLength?: number; signal?: AbortSignal }
): Promise<{ instanceId: string; loadTimeSeconds?: number }> {
  const body: Record<string, unknown> = { model: modelKey };
  if (options?.contextLength) {
    body.context_length = options.contextLength;
  }

  const res = await fetch(`${nativeBaseUrl()}/api/v1/models/load`, {
    method: "POST",
    headers: authHeaders(),
    body: JSON.stringify(body),
    signal: options?.signal ?? AbortSignal.timeout(600_000),
  });

  if (!res.ok) {
    const text = await res.text();
    throw new Error(`LM Studio load failed (${res.status}): ${text}`);
  }

  const data = (await res.json()) as {
    instance_id?: string;
    load_time_seconds?: number;
    status?: string;
  };

  if (data.status && data.status !== "loaded") {
    throw new Error(`LM Studio load unexpected status: ${data.status}`);
  }

  return {
    instanceId: data.instance_id ?? modelKey,
    loadTimeSeconds: data.load_time_seconds,
  };
}

export async function unloadNativeModel(
  instanceId: string,
  signal?: AbortSignal
): Promise<void> {
  const res = await fetch(`${nativeBaseUrl()}/api/v1/models/unload`, {
    method: "POST",
    headers: authHeaders(),
    body: JSON.stringify({ instance_id: instanceId }),
    signal: signal ?? AbortSignal.timeout(120_000),
  });

  if (!res.ok) {
    const text = await res.text();
    throw new Error(`LM Studio unload failed (${res.status}): ${text}`);
  }
}

export async function verifySingleLlmLoaded(
  expectedModelKey: string,
  signal?: AbortSignal
): Promise<boolean> {
  const models = await fetchNativeModels(signal);
  const loaded = getLoadedLlmInstances(models);
  return (
    loaded.length === 1 &&
    (loaded[0].modelKey === expectedModelKey ||
      loaded[0].instanceId === expectedModelKey)
  );
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

export async function waitUntilInstanceUnloaded(
  instanceId: string,
  options?: { maxAttempts?: number; intervalMs?: number; signal?: AbortSignal }
): Promise<void> {
  const maxAttempts = options?.maxAttempts ?? 60;
  const intervalMs = options?.intervalMs ?? 500;

  for (let attempt = 0; attempt < maxAttempts; attempt++) {
    if (options?.signal?.aborted) {
      throw new Error("Aborted");
    }
    const models = await fetchNativeModels(options?.signal);
    const loaded = getLoadedLlmInstances(models);
    if (!loaded.some((i) => i.instanceId === instanceId)) return;
    await sleep(intervalMs);
  }

  throw new Error(
    `Le modèle (instance ${instanceId}) n'a pas été déchargé à temps.`
  );
}

export async function waitUntilNoLlmLoaded(
  options?: { maxAttempts?: number; intervalMs?: number; signal?: AbortSignal }
): Promise<void> {
  const maxAttempts = options?.maxAttempts ?? 60;
  const intervalMs = options?.intervalMs ?? 500;

  for (let attempt = 0; attempt < maxAttempts; attempt++) {
    if (options?.signal?.aborted) {
      throw new Error("Aborted");
    }
    const models = await fetchNativeModels(options?.signal);
    if (getLoadedLlmInstances(models).length === 0) return;
    await sleep(intervalMs);
  }

  throw new Error("Des modèles LLM sont encore chargés après déchargement.");
}
