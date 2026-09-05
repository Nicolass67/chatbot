/**
 * Point d'entrée mémoire post-réponse.
 * Remplace les chemins pré-stream (classifier + applyImmediate).
 */

import {
  runMemoryPostProcessor,
  appliedChangesToSavedItems,
} from "./post-processor";
import type { SavedMemoryItem } from "./saved-memory";

export type MemoryAfterResponseParams = {
  userMessage: string;
  assistantMessage: string;
  memoryEnabled: boolean;
  messageId?: string;
  modelId?: string;
  recentTurns?: Array<{ role: "user" | "assistant"; content: string }>;
  signal?: AbortSignal;
};

/**
 * Lance le Memory Post-Processor (LLM décision → validator → store).
 * Ne throw jamais : échec → [].
 */
export async function applyMemoryAfterResponse(
  params: MemoryAfterResponseParams
): Promise<SavedMemoryItem[]> {
  if (!params.memoryEnabled) return [];
  if (!params.userMessage.trim() || !params.assistantMessage.trim()) return [];

  const result = await runMemoryPostProcessor({
    messageId: params.messageId,
    userMessage: params.userMessage,
    assistantMessage: params.assistantMessage,
    modelId: params.modelId,
    recentTurns: params.recentTurns,
    signal: params.signal,
  });

  if (!result.ok || !result.changed) return [];
  return appliedChangesToSavedItems(result.applied);
}

/**
 * @deprecated Plus utilisé en pré-stream — conservé pour compat imports.
 */
export async function applyImmediateMemories(): Promise<SavedMemoryItem[]> {
  return [];
}
