import { nanoid } from "nanoid";
import { buildObjectiveContext } from "@/lib/request-router/objective-context";
import type { ObjectiveContext, RequestContext } from "@/lib/request-router/types";
import {
  buildMemoryClassifierSystemPrompt,
  buildMemoryClassifierUserPrompt,
  parseMemoryIntentClassification,
  type MemoryIntentDecision,
} from "./intent-classifier";
import {
  extractPersonalFactCandidates,
  mergePersonalFacts,
} from "./personal-facts";

export const MEMORY_CLASSIFIER_TIMEOUT_MS = 8_000;
export const MEMORY_CLASSIFIER_MAX_TOKENS = 320;
export const MEMORY_CLASSIFIER_ACCEPT_CONFIDENCE = 0.55;

export function shouldUseMemoryClassifier(ctx: RequestContext): boolean {
  if (process.env.MEMORY_DISABLE_LLM_CLASSIFIER === "1") return false;
  return Boolean(ctx.runtime && ctx.modelId);
}

function disabledDecision(latencyMs: number): MemoryIntentDecision {
  return {
    shouldRemember: false,
    memories: [],
    confidence: 1,
    source: "disabled",
    reason: "Mémoire désactivée",
    latencyMs,
  };
}

function noneDecision(reason: string, latencyMs: number): MemoryIntentDecision {
  return {
    shouldRemember: false,
    memories: [],
    confidence: 0.85,
    source: "none",
    reason,
    latencyMs,
  };
}

function personalFactsDecision(
  memories: MemoryIntentDecision["memories"],
  latencyMs: number
): MemoryIntentDecision {
  return {
    shouldRemember: true,
    memories,
    confidence: 0.92,
    source: "fast_path",
    reason: "Fait personnel / événement de vie détecté",
    latencyMs,
  };
}

export async function classifyMemoryIntent(
  ctx: RequestContext,
  objective?: ObjectiveContext,
  options?: { memoryEnabled?: boolean }
): Promise<MemoryIntentDecision> {
  const started = Date.now();
  const memoryEnabled = options?.memoryEnabled ?? true;

  if (!memoryEnabled) {
    return disabledDecision(Date.now() - started);
  }

  const obj = objective ?? buildObjectiveContext(ctx);
  const personalFacts = extractPersonalFactCandidates(obj.trimmedMessage);

  if (!shouldUseMemoryClassifier(ctx) || !ctx.runtime) {
    if (personalFacts.length > 0) {
      return personalFactsDecision(personalFacts, Date.now() - started);
    }
    return noneDecision("Classifier mémoire indisponible", Date.now() - started);
  }

  try {
    const signal = ctx.signal ?? AbortSignal.timeout(MEMORY_CLASSIFIER_TIMEOUT_MS);
    const response = await ctx.runtime.chat({
      requestId: nanoid(),
      model: ctx.modelId,
      messages: [
        { role: "system", content: buildMemoryClassifierSystemPrompt() },
        { role: "user", content: buildMemoryClassifierUserPrompt(obj) },
      ],
      temperature: 0,
      maxTokens: MEMORY_CLASSIFIER_MAX_TOKENS,
      signal,
      reasoningEffort: "none",
    });

    if (!response.content?.trim()) {
      if (personalFacts.length > 0) {
        return personalFactsDecision(personalFacts, Date.now() - started);
      }
      return noneDecision("Classifier mémoire: réponse vide", Date.now() - started);
    }

    const parsed = parseMemoryIntentClassification(response.content);
    const accepted =
      parsed.shouldRemember &&
      parsed.confidence >= MEMORY_CLASSIFIER_ACCEPT_CONFIDENCE &&
      parsed.memories.length > 0;

    if (accepted) {
      const memories = mergePersonalFacts(parsed.memories, personalFacts);
      return {
        shouldRemember: true,
        memories: memories as MemoryIntentDecision["memories"],
        confidence: parsed.confidence,
        source: "llm_classifier",
        reason: parsed.reason,
        latencyMs: Date.now() - started,
      };
    }

    if (personalFacts.length > 0) {
      return personalFactsDecision(personalFacts, Date.now() - started);
    }

    return noneDecision(parsed.reason, Date.now() - started);
  } catch {
    if (personalFacts.length > 0) {
      return personalFactsDecision(personalFacts, Date.now() - started);
    }
    return noneDecision("Classifier mémoire indisponible", Date.now() - started);
  }
}
