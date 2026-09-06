/**
 * Cache d'extraction page — clé url+contentHash+question+promptVersion+modelId.
 * Une erreur de cache ne bloque jamais l'extraction.
 */

import { createHash } from "crypto";

export const EXTRACTION_PROMPT_VERSION = "we-v4-extract-1";

export type ExtractCacheRow = {
  claim: string;
  value?: string;
  evidence: string;
  confidence?: "high" | "medium" | "low";
  caveat?: string;
};

export type ExtractCacheEntry = {
  rows: ExtractCacheRow[];
  storedAt: number;
};

export type ExtractCacheStats = {
  hits: number;
  misses: number;
  invalidations: number;
  writes: number;
  errors: number;
};

const store = new Map<string, ExtractCacheEntry>();
const stats: ExtractCacheStats = {
  hits: 0,
  misses: 0,
  invalidations: 0,
  writes: 0,
  errors: 0,
};

const MAX_ENTRIES = 200;
const TTL_MS = 1000 * 60 * 60 * 6;

export function normalizeQuestionForCache(q: string): string {
  return q
    .toLowerCase()
    .normalize("NFD")
    .replace(/\p{M}/gu, "")
    .replace(/[^a-z0-9]+/gi, " ")
    .trim()
    .replace(/\s+/g, " ")
    .slice(0, 400);
}

export function hashContent(content: string): string {
  return createHash("sha1").update(content).digest("hex").slice(0, 16);
}

export function buildExtractCacheKey(params: {
  url: string;
  contentHash: string;
  question: string;
  promptVersion?: string;
  modelId: string;
}): string {
  return [
    params.url.trim(),
    params.contentHash,
    normalizeQuestionForCache(params.question),
    params.promptVersion ?? EXTRACTION_PROMPT_VERSION,
    params.modelId.trim(),
  ].join("|");
}

export function getExtractCacheStats(): ExtractCacheStats {
  return { ...stats };
}

export function resetExtractCacheForTests(): void {
  store.clear();
  stats.hits = 0;
  stats.misses = 0;
  stats.invalidations = 0;
  stats.writes = 0;
  stats.errors = 0;
}

export function readExtractCache(key: string): ExtractCacheEntry | null {
  try {
    const hit = store.get(key);
    if (!hit) {
      stats.misses += 1;
      return null;
    }
    if (Date.now() - hit.storedAt > TTL_MS) {
      store.delete(key);
      stats.invalidations += 1;
      stats.misses += 1;
      return null;
    }
    stats.hits += 1;
    return hit;
  } catch {
    stats.errors += 1;
    return null;
  }
}

export function writeExtractCache(key: string, entry: ExtractCacheEntry): void {
  try {
    if (store.size >= MAX_ENTRIES) {
      const first = store.keys().next().value;
      if (first) {
        store.delete(first);
        stats.invalidations += 1;
      }
    }
    store.set(key, entry);
    stats.writes += 1;
  } catch {
    stats.errors += 1;
  }
}
