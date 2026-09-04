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
}): Promise<SavedMemoryItem[]> {
  if (!params.memoryEnabled || !params.intent.shouldRemember) return [];

  if (
    params.intent.memories.length === 0 ||
    params.intent.source === "fast_path"
  ) {
    return extractMemoriesAsync(params.userMessage, params.assistantMessage);
  }

  return [];
}
