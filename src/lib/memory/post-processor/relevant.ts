import type { ExistingMemorySnippet } from "./types";
import { memoryRetriever } from "../search";

const MAX_SNIPPETS = 8;
const MAX_CONTENT_CHARS = 280;

/**
 * Charge un sous-ensemble de souvenirs pertinents pour la décision LLM.
 * Ne renvoie jamais toute la base.
 */
export async function loadRelevantMemories(params: {
  userMessage: string;
  assistantMessage: string;
  limit?: number;
}): Promise<ExistingMemorySnippet[]> {
  const limit = params.limit ?? MAX_SNIPPETS;
  const query = `${params.userMessage}\n${params.assistantMessage}`.trim();
  if (!query) return [];

  try {
    const rows = await memoryRetriever.search(query, limit);
    return rows.slice(0, limit).map((m) => ({
      id: m.id,
      content: m.content.slice(0, MAX_CONTENT_CHARS),
      category: m.category,
      importance: typeof m.importance === "number" ? m.importance : 0.5,
    }));
  } catch {
    return [];
  }
}
