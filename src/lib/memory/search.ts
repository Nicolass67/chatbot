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

  /** Fallback: souvenirs stables les plus importants (identité, préférences). */
  private async fetchTopImportance(limit: number): Promise<Memory[]> {
    const sqlite = getSqlite();
    try {
      return sqlite
        .prepare(
          `SELECT id, content, category, importance, embedding,
                  created_at as createdAt, updated_at as updatedAt
           FROM memories
           ORDER BY importance DESC, updated_at DESC
           LIMIT ?`
        )
        .all(limit) as Memory[];
    } catch {
      return [];
    }
  }

  private async fetchCandidates(
    query: string,
    limit: number
  ): Promise<Memory[]> {
    const sqlite = getSqlite();
    const words = query
      .toLowerCase()
      .split(/\s+/)
      .map((w) => w.replace(/[^\p{L}\p{N}]/gu, ""))
      .filter((w) => w.length > 2)
      .slice(0, 8);

    if (words.length === 0) {
      // Pas de tokens FTS utiles: injecter quand même les souvenirs stables.
      return this.fetchTopImportance(limit);
    }

    const ftsQuery = words.map((w) => `"${w.replace(/"/g, "")}"`).join(" OR ");

    try {
      const matched = sqlite
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

      if (matched.length > 0) return matched;
      // FTS vide mais budget actif → ne pas laisser la mémoire inutilisée.
      return this.fetchTopImportance(limit);
    } catch {
      return this.fetchTopImportance(limit);
    }
  }
}

export const memoryRetriever = new TextMemoryRetriever();

/** V2 stub interface for embedding-based retrieval */
export interface EmbeddingMemoryRetriever extends MemoryRetriever {
  kind: "embedding";
}
