import type { SearchResult } from "../types";
import { canonicalizeUrl } from "./source-dedupe";

export function extractDomain(url: string): string {
  try {
    return new URL(url).hostname.replace(/^www\./, "");
  } catch {
    return url;
  }
}

export { canonicalizeUrl };

export interface RawWebHit {
  title?: string;
  url?: string;
  snippet?: string;
  source?: string;
  publishedAt?: string;
}

export function normalizeWebHit(hit: RawWebHit): SearchResult | null {
  const title = hit.title?.trim();
  const url = hit.url?.trim();
  if (!title || !url || !url.startsWith("http")) return null;

  return {
    title,
    url,
    domain: extractDomain(url),
    snippet: hit.snippet?.trim() ?? "",
    source: hit.source,
    publishedAt: hit.publishedAt,
  };
}

export function normalizeWebHits(
  hits: RawWebHit[],
  maxResults: number
): SearchResult[] {
  const results: SearchResult[] = [];
  const seen = new Set<string>();

  for (const hit of hits) {
    const normalized = normalizeWebHit(hit);
    if (!normalized) continue;
    const key = canonicalizeUrl(normalized.url);
    if (seen.has(key)) continue;
    seen.add(key);
    results.push(normalized);
    if (results.length >= maxResults) break;
  }

  return results;
}
