import { desc, eq } from "drizzle-orm";
import type { OrchestratorEvent } from "@/lib/agent/events";
import { getDb } from "@/lib/db";
import { messages } from "@/lib/db/schema";
import { contentToPlainText } from "@/lib/runtime/capabilities";
import type { AppSettings } from "@/lib/settings/service";
import { applyMemoryAfterResponse } from "../apply-intent";
import { emitMemorySaved } from "../emit-saved";

const MAX_RECENT_TURNS = 4;
const MAX_TURN_CHARS = 500;
/** Garde le SSE ouvert après `done` le temps d’émettre `memory_saved` (chip UI). */
const MEMORY_SSE_BUDGET_MS = 25_000;

/**
 * Charge un contexte conversationnel borné pour le Memory Post-Processor.
 * N'envoie jamais tout l'historique.
 */
export async function loadRecentTurnsForMemory(
  conversationId: string,
  excludeMessageId?: string
): Promise<Array<{ role: "user" | "assistant"; content: string }>> {
  try {
    const db = getDb();
    const rows = await db.query.messages.findMany({
      where: eq(messages.conversationId, conversationId),
      orderBy: [desc(messages.createdAt)],
      limit: MAX_RECENT_TURNS + 2,
    });

    return rows
      .filter(
        (m) =>
          (m.role === "user" || m.role === "assistant") &&
          m.id !== excludeMessageId
      )
      .reverse()
      .slice(-MAX_RECENT_TURNS)
      .map((m) => ({
        role: m.role as "user" | "assistant",
        content: contentToPlainText(m.content).slice(0, MAX_TURN_CHARS),
      }))
      .filter((t) => t.content.trim().length > 0);
  } catch {
    return [];
  }
}

export type MemoryPostProcessParams = {
  settings: Pick<AppSettings, "memoryEnabled" | "selectedModel">;
  conversationId: string;
  messageId: string;
  userMessage: string;
  assistantMessage: string;
  onEvent: (event: OrchestratorEvent) => void;
  signal?: AbortSignal;
};

/**
 * Exécute le Memory Post-Processor et émet `memory_saved` si mutations.
 * Ne throw jamais.
 */
export async function runMemoryPostProcess(
  params: MemoryPostProcessParams
): Promise<void> {
  if (!params.settings.memoryEnabled) return;
  if (!params.userMessage.trim() || !params.assistantMessage.trim()) return;

  try {
    if (params.signal?.aborted) return;

    const recentTurns = await loadRecentTurnsForMemory(
      params.conversationId,
      params.messageId
    );

    const saved = await applyMemoryAfterResponse({
      messageId: params.messageId,
      userMessage: params.userMessage,
      assistantMessage: params.assistantMessage,
      memoryEnabled: params.settings.memoryEnabled,
      modelId: params.settings.selectedModel,
      recentTurns,
      signal: params.signal,
    });

    emitMemorySaved(params.onEvent, params.messageId, saved);
  } catch {
    // Échec mémoire : la réponse principale reste valide.
  }
}

/**
 * Après `done` : attend le post-processeur (budget borné) pour que
 * `memory_saved` parte encore sur le même SSE avant closeStream.
 * Ne retarde pas la génération — seulement la fermeture du stream.
 */
export async function awaitMemoryPostProcessAfterDone(
  params: MemoryPostProcessParams
): Promise<void> {
  await Promise.race([
    runMemoryPostProcess(params),
    new Promise<void>((resolve) => {
      setTimeout(resolve, MEMORY_SSE_BUDGET_MS);
    }),
  ]);
}

/**
 * Fire-and-forget (hors chemin SSE). Préférer `awaitMemoryPostProcessAfterDone`
 * dans orchestrator/loop pour l’indicateur chat.
 */
export function scheduleMemoryPostProcess(params: MemoryPostProcessParams): void {
  void runMemoryPostProcess(params);
}
