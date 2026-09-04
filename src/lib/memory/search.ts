import { getSqlite } from "@/lib/db";
import type { Memory } from "@/lib/db/schema";
import {
  rankAndSelectMemories,
  type RankedMemory,
} from "./ranking";

export interface MemoryRetriever {
  search(query: string, limit?: number): Promise<Memory[]>;
}

export interface MemorySearchOptions {
  limit?: number;
  /** Primary query for ranking (current user + entities + prev user) */
  primaryQuery?: string;
  /** Weak assistant hint — never authoritative */
  assistantHint?: string | null;
  entityLabels?: string[];
  /** Max memories to keep after ranking (0 = none) */
  budget?: number;
  minScore?: number;
}

export interface MemorySearchResult {
  selected: Memory[];
  rankedSelected: RankedMemory[];
  rankedExcluded: RankedMemory[];
  candidatesCount: number;
}

export class TextMemoryRetriever implements MemoryRetriever {
  async search(query: string, limit = 8): Promise<Memory[]> {
    const result = await this.searchRanked({
      primaryQuery: query,
      limit: Math.max(limit * 2, 8),
      budget: limit,
    });
    return result.selected;
  }

  /**
   * FTS candidate fetch then weighted rank → select under budget.
   * rank → select → budget (not collect-all then slice blindly).
   */
  async searchRanked(options: MemorySearchOptions): Promise<MemorySearchResult> {
    const budget = options.budget ?? options.limit ?? 8;
    const candidateLimit = Math.max(budget * 3, options.limit ?? 8, 8);
    const primaryQuery = (options.primaryQuery ?? "").trim();

    if (budget <= 0) {
      return {
        selected: [],
        rankedSelected: [],
        rankedExcluded: [],
        candidatesCount: 0,
      };
    }

    const candidates = await this.fetchCandidates(
      primaryQuery || options.assistantHint || "",
      candidateLimit
    );

    const { selected, excluded } = rankAndSelectMemories({
      candidates,
      primaryQuery: primaryQuery || " ",
      assistantHint: options.assistantHint,
      entityLabels: options.entityLabels,
      budget,
      minScore: options.minScore,
    });

    return {
      selected: selected.map((r) => r.memory),
      rankedSelected: selected,
      rankedExcluded: excluded,
      candidatesCount: candidates.length,
    };
  }

  private async fetchCandidates(
    query: string,
    limit: number
  ): Promise<Memory[]> {
    const sqlite = getSqlite();
    const words = query
      .toLowerCase()
      .split(/\s+/)
      .filter((w) => w.length > 3)
      .slice(0, 8);

    if (words.length === 0) {
      // No useful FTS tokens: do NOT return top-importance globally when
      // caller wanted semantic relevance — return empty candidates.
      // Callers that need a fallback can pass a broader primaryQuery.
      return [];
    }

    const ftsQuery = words.map((w) => `"${w.replace(/"/g, "")}"`).join(" OR ");

    try {
      return sqlite
        .prepare(
          `SELECT m.id, m.content, m.category, m.importance, m.embedding,
                  m.created_at as createdAt, m.updated_at as updatedAt
           FROM memories_fts f
           JOIN memories m ON m.rowid = f.rowid
           WHERE memories_fts MATCH ?
           ORDER BY bm25(memories_fts) * m.importance
           LIMIT ?`
        )
        .all(ftsQuery, limit) as Memory[];
    } catch {
      return [];
    }
  }
}

export const memoryRetriever = new TextMemoryRetriever();

/** V2 stub interface for embedding-based retrieval */
export interface EmbeddingMemoryRetriever extends MemoryRetriever {
  kind: "embedding";
}
