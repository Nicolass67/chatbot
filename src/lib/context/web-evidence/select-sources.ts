import { isSnippetInsufficient } from "@/lib/context/web-provenance";
import type { SourceSelectionDecision } from "./types";

export type SelectableSource = {
  sourceId: string;
  url: string;
  title: string;
  snippet: string;
  domain?: string;
  pageContent?: string;
};

/**
 * Ranking V4 — pertinence, anti-doublon, diversité domaine, densité info, fraîcheur.
 * Pas de whitelist de sites.
 */
export function selectSourcesForAnalysis(params: {
  query: string;
  sources: SelectableSource[];
  maxCandidates?: number;
  maxFetch?: number;
}): {
  decisions: SourceSelectionDecision[];
  toAnalyze: SelectableSource[];
  toFetch: SelectableSource[];
} {
  const maxCandidates = params.maxCandidates ?? 20;
  const maxFetch = params.maxFetch ?? 10;
  const qTokens = tokenize(params.query);

  const scored = params.sources.map((s) => {
    const hay = normalize(`${s.title} ${s.snippet} ${s.url} ${s.domain ?? ""}`);
    const overlap = qTokens.filter((t) => hay.includes(t)).length;
    const hasDigits = /\d/.test(s.snippet) || /\d/.test(s.title);
    const thin = isSnippetInsufficient(s.snippet, params.query);
    const hasPage = Boolean(s.pageContent && s.pageContent.length > 80);
    const density = infoDensity(s.snippet, s.pageContent);
    const freshness = freshnessBoost(s.snippet, s.title, s.url);
    let score =
      overlap * 4 +
      (hasDigits ? 2 : 0) +
      (hasPage ? 1 : 0) +
      density +
      freshness;
    if (thin && !hasPage) score -= 1;
    return { source: s, score, thin, overlap, hay };
  });

  scored.sort(
    (a, b) => b.score - a.score || a.source.url.localeCompare(b.source.url)
  );

  // Pénalité quasi-doublons (titre/snippet très similaires)
  for (let i = 0; i < scored.length; i++) {
    for (let j = 0; j < i; j++) {
      if (jaccard(scored[i]!.hay, scored[j]!.hay) >= 0.72) {
        scored[i]!.score -= 3;
      }
    }
  }
  scored.sort(
    (a, b) => b.score - a.score || a.source.url.localeCompare(b.source.url)
  );

  const domainCounts = new Map<string, number>();
  const selected: typeof scored = [];
  for (const row of scored) {
    if (selected.length >= maxCandidates) break;
    const domain = (row.source.domain || hostOf(row.source.url)).toLowerCase().replace(/^www\./, "");
    const domainCount = domainCounts.get(domain) ?? 0;
    // Diversité: max 2 par domaine sauf score très élevé
    if (domainCount >= 2 && row.score < 8) continue;
    if (domainCount >= 3) continue;
    domainCounts.set(domain, domainCount + 1);
    selected.push(row);
  }

  const fetchBudget = Math.min(maxFetch, selected.length);
  const selectedIds = new Set(selected.map((r) => r.source.sourceId));

  const decisions: SourceSelectionDecision[] = params.sources.map((s) => {
    const hit = selected.find((r) => r.source.sourceId === s.sourceId);
    if (!hit || !selectedIds.has(s.sourceId)) {
      return {
        sourceId: s.sourceId,
        url: s.url,
        title: s.title,
        selected: false,
        score: scored.find((r) => r.source.sourceId === s.sourceId)?.score ?? 0,
        reason: "Hors budget / score insuffisant / doublon",
        fetch: false,
      };
    }
    const rank = selected.indexOf(hit);
    const doFetch = rank < fetchBudget;
    return {
      sourceId: s.sourceId,
      url: s.url,
      title: s.title,
      selected: true,
      score: hit.score,
      reason: doFetch
        ? "Sélectionnée pour analyse (pertinence + diversité + densité)"
        : "Sélectionnée mais hors budget fetch",
      fetch: doFetch,
    };
  });

  const toAnalyze = selected.slice(0, fetchBudget).map((r) => r.source);
  const toFetch = toAnalyze.filter(
    (s) => !s.pageContent || s.pageContent.length < 40
  );

  return { decisions, toAnalyze, toFetch };
}

function infoDensity(snippet: string, page?: string): number {
  const sample = (page && page.length > 80 ? page.slice(0, 1500) : snippet) ?? "";
  const nums = (sample.match(/\d+(?:[.,]\d+)?/g) ?? []).length;
  const units = (
    sample.match(/(?:€|\$|%|\b(?:eur|usd|w|kw|ghz|go|gb|fps|ms|db|m³|m3)\b)/gi) ?? []
  ).length;
  return Math.min(4, Math.floor(nums / 2) + Math.min(2, units));
}

function freshnessBoost(snippet: string, title: string, url: string): number {
  const hay = `${title} ${snippet} ${url}`;
  if (/20(2[4-9]|3\d)/.test(hay)) return 2;
  if (/\b(aujourd|hier|new|récent|recent|updated|mis à jour)\b/i.test(hay)) return 1;
  return 0;
}

function jaccard(a: string, b: string): number {
  const ta = new Set(tokenize(a));
  const tb = new Set(tokenize(b));
  if (ta.size === 0 || tb.size === 0) return 0;
  let inter = 0;
  for (const t of ta) if (tb.has(t)) inter++;
  return inter / (ta.size + tb.size - inter);
}

function hostOf(url: string): string {
  try {
    return new URL(url).hostname;
  } catch {
    return url;
  }
}

function normalize(text: string): string {
  return text
    .toLowerCase()
    .normalize("NFD")
    .replace(/\p{M}/gu, "");
}

function tokenize(text: string): string[] {
  return normalize(text)
    .split(/[^a-z0-9]+/i)
    .filter((t) => t.length >= 3)
    .slice(0, 24);
}
