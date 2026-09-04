/** Public reasoning options exposed by LM Studio `/api/v1/models`. */
export type LmStudioReasoningOption = "off" | "on" | "low" | "medium" | "high";

export type ReasoningModeKind = "off_on" | "effort_levels" | "none";

export interface ReasoningModeOption {
  id: string;
  label: string;
}

export interface ReasoningCapabilities {
  modelId: string;
  supported: boolean;
  kind: ReasoningModeKind;
  modes: ReasoningModeOption[];
  defaultModeId: string | null;
  transmissionMethod: "reasoning_effort" | null;
  source: "lm_studio_api" | "unknown";
  limitations?: string;
}

/** @deprecated Use ReasoningCapabilities */
export type ReasoningCapabilitiesInfo = ReasoningCapabilities;

export const REASONING_MODE_LABELS: Record<string, string> = {
  off: "Désactivé",
  on: "Thinking",
  low: "Faible",
  medium: "Moyen",
  high: "Élevé",
};

export function getReasoningModeLabel(id: string): string {
  return REASONING_MODE_LABELS[id] ?? id;
}

/** Normalise les anciennes valeurs (none, medium, …) vers le défaut app off/on. */
export function normalizeAppDefaultReasoningMode(
  value: string | null | undefined
): string {
  if (!value || value.trim() === "") return "off";
  if (value === "none") return "off";
  if (["minimal", "low", "medium", "high", "xhigh"].includes(value)) {
    return "on";
  }
  if (value === "off" || value === "on") return value;
  return "on";
}

export function resolveReasoningMode(
  requested: string | null | undefined,
  caps: ReasoningCapabilities
): string | null {
  if (!caps.supported || caps.modes.length === 0) return null;

  const ids = caps.modes.map((m) => m.id);

  const legacyToMode = (value: string): string | null => {
    if (ids.includes(value)) return value;
    switch (value) {
      case "none":
        return ids.includes("off") ? "off" : null;
      case "minimal":
      case "low":
        if (caps.kind === "effort_levels" && ids.includes("low")) return "low";
        return ids.includes("on") ? "on" : null;
      case "medium":
        if (caps.kind === "effort_levels" && ids.includes("medium")) return "medium";
        return ids.includes("on") ? "on" : null;
      case "high":
      case "xhigh":
        if (caps.kind === "effort_levels" && ids.includes("high")) return "high";
        return ids.includes("on") ? "on" : null;
      default:
        return null;
    }
  };

  if (requested) {
    const resolved = legacyToMode(requested);
    if (resolved) return resolved;
  }

  if (ids.includes("off")) {
    return "off";
  }

  if (caps.defaultModeId && ids.includes(caps.defaultModeId)) {
    return caps.defaultModeId;
  }

  return ids[0] ?? null;
}

/** @deprecated Use resolveReasoningMode */
export const resolveReasoningEffort = resolveReasoningMode;

/** @deprecated Use getReasoningModeLabel */
export const getReasoningLabel = getReasoningModeLabel;
