import type { OrchestratorEvent } from "@/lib/agent/events";
import type { SavedMemoryItem } from "./saved-memory";

export function emitMemorySaved(
  onEvent: (event: OrchestratorEvent) => void,
  messageId: string,
  memories: SavedMemoryItem[]
): void {
  if (memories.length === 0) return;
  onEvent({ type: "memory_saved", messageId, memories });
}
