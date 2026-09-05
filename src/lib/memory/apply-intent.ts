import { extractMemoriesAsync, insertMemoryIfValid } from "./extract";
import type { MemoryIntentDecision } from "./intent-classifier";
import { extractPersonalFactCandidates } from "./personal-facts";
import type { SavedMemoryItem } from "./saved-memory";

export async function applyImmediateMemories(
  intent: MemoryIntentDecision
): Promise<SavedMemoryItem[]> {
  const saved: SavedMemoryItem[] = [];
  for (const mem of intent.memories) {
    const inserted = await insertMemoryIfValid(mem);
    if (inserted) saved.push(inserted);
  }
  return saved;
}

export async function applyMemoryAfterResponse(params: {
  intent: MemoryIntentDecision;
  userMessage: string;
  assistantMessage: string;
  memoryEnabled: boolean;
  /** Souvenirs déjà persistés au premier passage (classifier). */
  alreadySavedCount?: number;
}): Promise<SavedMemoryItem[]> {
  if (!params.memoryEnabled) return [];

  const already = params.alreadySavedCount ?? 0;
  const saved: SavedMemoryItem[] = [];

  // Filet déterministe: faits perso évidents même si le 1er passage a déjà sauvé autre chose.
  const personalFacts = extractPersonalFactCandidates(params.userMessage);
  for (const mem of personalFacts) {
    const inserted = await insertMemoryIfValid(mem);
    if (inserted) saved.push(inserted);
  }

  // Premier passage a déjà persisté → pas de second appel LLM.
  if (already > 0) return saved;

  // Second temps: extract LLM sur le tour complet.
  if (
    params.intent.shouldRemember ||
    params.intent.source === "none" ||
    params.intent.source === "llm_classifier" ||
    params.intent.source === "fast_path"
  ) {
    const extracted = await extractMemoriesAsync(
      params.userMessage,
      params.assistantMessage
    );
    saved.push(...extracted);
  }

  return saved;
}
