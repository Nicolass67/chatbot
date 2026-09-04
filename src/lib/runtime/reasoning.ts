import { getEnv } from "@/lib/config/env";
import {
  REASONING_MODE_LABELS,
  type LmStudioReasoningOption,
  type ReasoningCapabilities,
  type ReasoningModeKind,
  type ReasoningModeOption,
} from "@/lib/runtime/reasoning-types";

export type {
  LmStudioReasoningOption,
  ReasoningCapabilities,
  ReasoningCapabilitiesInfo,
  ReasoningModeKind,
  ReasoningModeOption,
} from "@/lib/runtime/reasoning-types";
export {
  REASONING_MODE_LABELS,
  getReasoningLabel,
  getReasoningModeLabel,
  resolveReasoningEffort,
  resolveReasoningMode,
} from "@/lib/runtime/reasoning-types";

const capabilitiesCache = new Map<string, ReasoningCapabilities>();

const NON_CHAT_MODEL_PATTERNS = [/embed/i, /embedding/i, /nomic-embed/i];

export interface LmStudioNativeModel {
  type: string;
  key: string;
  display_name: string;
  capabilities?: {
    vision?: boolean;
    trained_for_tool_use?: boolean;
    reasoning?: {
      allowed_options: LmStudioReasoningOption[];
      default: LmStudioReasoningOption;
    };
  };
}

function lmStudioNativeBaseUrl(): string {
  const env = getEnv();
  return env.LM_STUDIO_BASE_URL.replace(/\/v1\/?$/, "").replace(/\/$/, "");
}

export async function lmStudioGetNativeModels(
  signal?: AbortSignal
): Promise<LmStudioNativeModel[]> {
  const res = await fetch(`${lmStudioNativeBaseUrl()}/api/v1/models`, {
    signal: signal ?? AbortSignal.timeout(5000),
    headers: {
      Authorization: `Bearer ${getEnv().LM_STUDIO_API_KEY}`,
    },
  });
  if (!res.ok) {
    throw new Error(`LM Studio native models error: ${res.status}`);
  }
  const data = (await res.json()) as { models?: LmStudioNativeModel[] };
  return data.models ?? [];
}

function inferKind(options: LmStudioReasoningOption[]): ReasoningModeKind {
  const effort = options.filter((o) => o === "low" || o === "medium" || o === "high");
  if (effort.length > 0 && options.length > 2) return "effort_levels";
  if (options.includes("off") || options.includes("on")) return "off_on";
  return "none";
}

function buildModes(options: LmStudioReasoningOption[]): ReasoningModeOption[] {
  return options.map((id) => ({
    id,
    label: REASONING_MODE_LABELS[id] ?? id,
  }));
}

export function buildReasoningCapabilitiesFromNative(
  modelId: string,
  native: LmStudioNativeModel | undefined
): ReasoningCapabilities {
  if (!native?.capabilities?.reasoning?.allowed_options?.length) {
    return {
      modelId,
      supported: false,
      kind: "none",
      modes: [],
      defaultModeId: null,
      transmissionMethod: null,
      source: "unknown",
      limitations:
        "LM Studio n'expose pas de configuration reasoning pour ce modèle (/api/v1/models).",
    };
  }

  const { allowed_options, default: defaultOption } = native.capabilities.reasoning;
  const kind = inferKind(allowed_options);

  return {
    modelId,
    supported: true,
    kind,
    modes: buildModes(allowed_options),
    defaultModeId: defaultOption,
    transmissionMethod: "reasoning_effort",
    source: "lm_studio_api",
    limitations:
      kind === "off_on"
        ? "Thinking ON/OFF détecté via LM Studio. off → reasoning_effort:none ; on → défaut modèle."
        : "Niveaux détectés via LM Studio /api/v1/models (allowed_options).",
  };
}

export function isLikelyNonChatModel(modelId: string): boolean {
  return NON_CHAT_MODEL_PATTERNS.some((p) => p.test(modelId));
}

/**
 * Reads reasoning capabilities from LM Studio REST API (`GET /api/v1/models`).
 * Does not probe arbitrary reasoning_effort values — uses published allowed_options only.
 */
export async function getReasoningCapabilities(
  modelId: string,
  options?: { signal?: AbortSignal; force?: boolean }
): Promise<ReasoningCapabilities> {
  if (!modelId) {
    return {
      modelId: "",
      supported: false,
      kind: "none",
      modes: [],
      defaultModeId: null,
      transmissionMethod: null,
      source: "unknown",
    };
  }

  if (!options?.force && capabilitiesCache.has(modelId)) {
    return capabilitiesCache.get(modelId)!;
  }

  if (isLikelyNonChatModel(modelId)) {
    const info: ReasoningCapabilities = {
      modelId,
      supported: false,
      kind: "none",
      modes: [],
      defaultModeId: null,
      transmissionMethod: null,
      source: "unknown",
      limitations: "Modèle non conversationnel.",
    };
    capabilitiesCache.set(modelId, info);
    return info;
  }

  try {
    const models = await lmStudioGetNativeModels(options?.signal);
    const native = models.find((m) => m.key === modelId || m.key === modelId.split("@")[0]);
    const info = buildReasoningCapabilitiesFromNative(modelId, native);
    capabilitiesCache.set(modelId, info);
    return info;
  } catch {
    const info: ReasoningCapabilities = {
      modelId,
      supported: false,
      kind: "none",
      modes: [],
      defaultModeId: null,
      transmissionMethod: null,
      source: "unknown",
      limitations:
        "Impossible de lire /api/v1/models — capacité reasoning non détectée.",
    };
    capabilitiesCache.set(modelId, info);
    return info;
  }
}

/** @deprecated Use getReasoningCapabilities */
export const probeReasoningCapabilities = getReasoningCapabilities;

export function clearReasoningCapabilitiesCache(modelId?: string): void {
  if (modelId) capabilitiesCache.delete(modelId);
  else capabilitiesCache.clear();
}

/** @deprecated */
export const clearReasoningProbeCache = clearReasoningCapabilitiesCache;

export function buildReasoningRequestFields(
  modeId: string | null | undefined
): Record<string, string> {
  // Ne pas envoyer reasoning_effort pour "off" — certains moteurs LM Studio
  // (ex. Gemma peg-native) échouent si le champ est présent avec "none".
  if (!modeId || modeId === "off" || modeId === "none") {
    return {};
  }

  if (modeId === "on") return {};

  if (modeId === "minimal") return { reasoning_effort: "low" };
  if (modeId === "xhigh") return { reasoning_effort: "high" };

  if (["low", "medium", "high"].includes(modeId)) {
    return { reasoning_effort: modeId };
  }

  return {};
}
