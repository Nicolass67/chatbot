import type { SearchResult } from "@/lib/tools/types";

/** Normalise une requête Web pour comparaison et déduplication. */
export function normalizeSearchQuery(query: string): string {
  return query
    .toLowerCase()
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[^\w\s]/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function tokenSet(query: string): Set<string> {
  return new Set(
    normalizeSearchQuery(query)
      .split(" ")
      .filter((w) => w.length > 1)
  );
}

/** Deux requêtes sont considérées équivalentes si identiques ou très similaires. */
export function areQueriesEquivalent(a: string, b: string): boolean {
  const na = normalizeSearchQuery(a);
  const nb = normalizeSearchQuery(b);
  if (na === nb) return true;
  if (!na || !nb) return false;

  const wordsA = tokenSet(a);
  const wordsB = tokenSet(b);
  if (wordsA.size === 0 || wordsB.size === 0) return false;

  const intersection = [...wordsA].filter((w) => wordsB.has(w)).length;
  const union = new Set([...wordsA, ...wordsB]).size;
  return union > 0 && intersection / union >= 0.8;
}

export interface CachedSearchEntry {
  query: string;
  normalized: string;
  resultSummary: string;
  sourceCount: number;
  sources: SearchResult[];
  output: unknown;
  executedAt: string;
}

export class SearchQueryCache {
  private entries: CachedSearchEntry[] = [];

  findEquivalent(query: string): CachedSearchEntry | null {
    for (const entry of this.entries) {
      if (areQueriesEquivalent(query, entry.query)) return entry;
    }
    return null;
  }

  store(
    query: string,
    resultSummary: string,
    sourceCount: number,
    sources: SearchResult[],
    output: unknown
  ): void {
    this.entries.push({
      query,
      normalized: normalizeSearchQuery(query),
      resultSummary,
      sourceCount,
      sources,
      output,
      executedAt: new Date().toISOString(),
    });
  }

  get executedQueries(): string[] {
    return this.entries.map((e) => e.query);
  }

  get size(): number {
    return this.entries.length;
  }
}
