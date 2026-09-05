import { extractMemoriesAsync, insertMemoryIfValid } from "./extract";
import type { MemoryIntentDecision } from "./intent-classifier";
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

  // Premier passage a déjà persisté → pas de second appel LLM.
  if (already > 0) return [];

  // Second temps: l'IA décide à nouveau (extract) si le classifier a dit oui
  // sans items exploitables, a échoué à l'insert, ou a manqué un fait.
  // On lance aussi quand shouldRemember=false pour laisser l'extract juger
  // le tour complet (user + réponse) — sans heuristique lexicale.
  if (
    params.intent.shouldRemember ||
    params.intent.source === "none" ||
    params.intent.source === "llm_classifier" ||
    params.intent.source === "fast_path"
  ) {
    return extractMemoriesAsync(params.userMessage, params.assistantMessage);
  }

  return [];
}
