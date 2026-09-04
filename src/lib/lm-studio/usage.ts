import type { RuntimeUsage } from "@/lib/runtime/types";

interface LmUsagePayload {
  prompt_tokens?: number;
  completion_tokens?: number;
  total_tokens?: number;
  completion_tokens_details?: { reasoning_tokens?: number };
  prompt_tokens_details?: { cached_tokens?: number };
}

interface LmStatsPayload {
  tokens_per_second?: number;
  time_to_first_token?: number;
  generation_time?: number;
}

interface LmModelInfo {
  context_length?: number;
}

export function parseLmStudioUsage(
  usage?: LmUsagePayload,
  stats?: LmStatsPayload,
  modelInfo?: LmModelInfo,
  timing?: { timeToFirstTokenMs?: number; totalGenerationMs?: number }
): RuntimeUsage | undefined {
  if (!usage && !stats) return undefined;

  const result: RuntimeUsage = { source: "lm_studio" };

  if (usage?.prompt_tokens !== undefined) result.promptTokens = usage.prompt_tokens;
  if (usage?.completion_tokens !== undefined) {
    result.completionTokens = usage.completion_tokens;
  }
  if (usage?.total_tokens !== undefined) result.totalTokens = usage.total_tokens;
  if (usage?.completion_tokens_details?.reasoning_tokens !== undefined) {
    result.reasoningTokens = usage.completion_tokens_details.reasoning_tokens;
  }
  if (usage?.prompt_tokens_details?.cached_tokens !== undefined) {
    result.cachedPromptTokens = usage.prompt_tokens_details.cached_tokens;
  }

  if (stats?.tokens_per_second !== undefined) {
    result.tokensPerSecond = stats.tokens_per_second;
  }
  if (stats?.time_to_first_token !== undefined) {
    result.timeToFirstTokenMs = Math.round(stats.time_to_first_token * 1000);
  }
  if (stats?.generation_time !== undefined) {
    result.totalGenerationMs = Math.round(stats.generation_time * 1000);
  }

  if (modelInfo?.context_length !== undefined) {
    result.contextLength = modelInfo.context_length;
  }

  if (timing?.timeToFirstTokenMs !== undefined && result.timeToFirstTokenMs === undefined) {
    result.timeToFirstTokenMs = timing.timeToFirstTokenMs;
  }
  if (timing?.totalGenerationMs !== undefined && result.totalGenerationMs === undefined) {
    result.totalGenerationMs = timing.totalGenerationMs;
  }

  if (
    result.promptTokens === undefined &&
    result.completionTokens === undefined &&
    result.tokensPerSecond === undefined
  ) {
    return undefined;
  }

  return result;
}

export function mergeRuntimeUsage(
  base: RuntimeUsage | undefined,
  extra: RuntimeUsage | undefined
): RuntimeUsage | undefined {
  if (!base && !extra) return undefined;
  return { source: "lm_studio", ...base, ...extra };
}
