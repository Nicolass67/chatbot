import { getSettings } from "@/lib/settings/service";
import { applyValidatedMemoryDecisions } from "./apply-decisions";
import { requestMemoryDecision } from "./decision-llm";
import { loadRelevantMemories } from "./relevant";
import type {
  MemoryPostProcessorInput,
  MemoryPostProcessorResult,
  AppliedMemoryChange,
} from "./types";
import { validateMemoryDecisions } from "./validator";

export type { MemoryPostProcessorResult, AppliedMemoryChange };

/** Empêche deux post-process concurrentes pour le même message. */
const inFlightByMessage = new Set<string>();

/**
 * Pipeline Memory Post-Processor :
 * relevant memories → LLM decision JSON → validator/policy → store.
 * Ne doit jamais throw vers l'appelant chat.
 */
export async function runMemoryPostProcessor(
  input: Omit<MemoryPostProcessorInput, "modelId" | "existingMemories"> & {
    messageId?: string;
    modelId?: string;
    existingMemories?: MemoryPostProcessorInput["existingMemories"];
  }
): Promise<MemoryPostProcessorResult> {
  const lockKey = input.messageId?.trim() || "";
  if (lockKey) {
    if (inFlightByMessage.has(lockKey)) {
      return {
        ok: true,
        changed: false,
        applied: [],
        ignoredCount: 0,
        error: "already_in_flight",
      };
    }
    inFlightByMessage.add(lockKey);
  }

  try {
    const settings = await getSettings();
    if (!settings.memoryEnabled) {
      return { ok: true, changed: false, applied: [], ignoredCount: 0 };
    }

    const modelId = (input.modelId || settings.selectedModel || "").trim();
    if (!modelId) {
      return {
        ok: false,
        changed: false,
        applied: [],
        ignoredCount: 0,
        error: "no_model",
      };
    }

    if (!input.userMessage.trim() || !input.assistantMessage.trim()) {
      return { ok: true, changed: false, applied: [], ignoredCount: 0 };
    }

    const existingMemories =
      input.existingMemories ??
      (await loadRelevantMemories({
        userMessage: input.userMessage,
        assistantMessage: input.assistantMessage,
      }));

    const payload = await requestMemoryDecision({
      userMessage: input.userMessage,
      assistantMessage: input.assistantMessage,
      recentTurns: input.recentTurns,
      existingMemories,
      modelId,
      signal: input.signal,
    });

    const validated = validateMemoryDecisions(payload, existingMemories);
    const ignoredCount = validated.filter((c) => !c.accepted).length;
    const applied = await applyValidatedMemoryDecisions(validated);

    return {
      ok: true,
      changed: applied.length > 0,
      applied,
      ignoredCount,
    };
  } catch (err) {
    return {
      ok: false,
      changed: false,
      applied: [],
      ignoredCount: 0,
      error: err instanceof Error ? err.message : "memory_post_processor_failed",
    };
  } finally {
    if (lockKey) inFlightByMessage.delete(lockKey);
  }
}

/** Convertit les changements appliqués vers le payload SSE historique. */
export function appliedChangesToSavedItems(applied: AppliedMemoryChange[]) {
  return applied
    .filter((a) => a.action === "create" || a.action === "update")
    .map((a) => ({
      id: a.id,
      content: a.content,
      category: a.category,
    }));
}

/** Exposé pour tests. */
export function __resetMemoryPostProcessorLocksForTests(): void {
  inFlightByMessage.clear();
}
