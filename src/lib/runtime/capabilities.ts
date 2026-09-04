import type { ModelCapabilities, ModelCapabilitiesInfo } from "@/lib/runtime/types";
import { lmStudioGetModels } from "@/lib/lm-studio/client";
import {
  getReasoningCapabilities,
  lmStudioGetNativeModels,
  type ReasoningCapabilities,
} from "@/lib/runtime/reasoning";

const VISION_KEYWORDS = [
  "vision",
  "vl",
  "visual",
  "multimodal",
  "llava",
  "qwen2-vl",
  "qwen-vl",
  "gemma-3",
  "pixtral",
  "moondream",
  "minicpm-v",
];

const REASONING_KEYWORDS = [
  "reason",
  "think",
  "r1",
  "o1",
  "o3",
  "deepseek-r1",
  "qwq",
];

function heuristicCapabilities(modelId: string): ModelCapabilities {
  const lower = modelId.toLowerCase();
  const vision = VISION_KEYWORDS.some((k) => lower.includes(k));
  const reasoning =
    REASONING_KEYWORDS.some((k) => lower.includes(k)) ||
    /qwen3/i.test(lower);
  return {
    text: true,
    vision,
    toolCalling: true,
    reasoning,
  };
}

async function attachReasoningInfo(
  modelId: string,
  base: ModelCapabilitiesInfo
): Promise<ModelCapabilitiesInfo> {
  let reasoning: ReasoningCapabilities;
  try {
    reasoning = await getReasoningCapabilities(modelId);
  } catch {
    reasoning = {
      modelId,
      supported: false,
      kind: "none",
      modes: [],
      defaultModeId: null,
      transmissionMethod: null,
      source: "unknown",
    };
  }

  return {
    ...base,
    capabilities: {
      ...base.capabilities,
      reasoning: reasoning.supported,
    },
    reasoning,
  };
}

export function getCapabilitiesFromModelId(modelId: string): ModelCapabilitiesInfo {
  return {
    modelId,
    capabilities: heuristicCapabilities(modelId),
    source: "heuristic",
  };
}

export async function getActiveModelCapabilities(
  modelId: string
): Promise<ModelCapabilitiesInfo> {
  if (!modelId) {
    return {
      modelId: "",
      capabilities: {
        text: false,
        vision: false,
        toolCalling: false,
        reasoning: false,
      },
      source: "unknown",
      reasoning: {
        modelId: "",
        supported: false,
        kind: "none",
        modes: [],
        defaultModeId: null,
        transmissionMethod: null,
        source: "unknown",
      },
    };
  }

  const heuristics = heuristicCapabilities(modelId);

  try {
    const [openAiModels, nativeModels] = await Promise.all([
      lmStudioGetModels(),
      lmStudioGetNativeModels().catch(() => []),
    ]);
    const found = openAiModels.find((m) => m.id === modelId);
    const native = nativeModels.find(
      (m) => m.key === modelId || m.key === modelId.split("@")[0]
    );

    const capabilities: ModelCapabilities = {
      text: true,
      vision: heuristics.vision || (native?.capabilities?.vision ?? false),
      toolCalling:
        native?.capabilities?.trained_for_tool_use ?? heuristics.toolCalling,
      reasoning: heuristics.reasoning,
    };

    const base: ModelCapabilitiesInfo = {
      modelId,
      capabilities,
      source: native ? "lm_studio_api" : found ? "model_meta" : "heuristic",
    };
    return attachReasoningInfo(modelId, base);
  } catch {
    return attachReasoningInfo(
      modelId,
      getCapabilitiesFromModelId(modelId)
    );
  }
}

export function assertVisionSupported(
  caps: ModelCapabilities,
  imageCount: number
): string | null {
  if (imageCount === 0) return null;
  if (!caps.vision) {
    return "Le modèle actif ne supporte pas la vision. Retirez les images ou choisissez un modèle multimodal.";
  }
  return null;
}

export function assertToolCallingSupported(
  caps: ModelCapabilities,
  toolsRequested: boolean
): string | null {
  if (!toolsRequested) return null;
  if (!caps.toolCalling) {
    return "Le modèle actif ne supporte pas le tool calling.";
  }
  return null;
}

export function contentToPlainText(
  content: string | import("@/lib/runtime/types").MessageContentPart[] | null
): string {
  if (!content) return "";
  if (typeof content === "string") return content;
  return content
    .filter((p) => p.type === "text" && p.text)
    .map((p) => p.text!)
    .join("\n");
}
