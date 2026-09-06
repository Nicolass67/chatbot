import type {
  EvidenceConfidence,
  InformationNeed,
  SourceAnalysisResult,
  WebEvidenceItem,
} from "./types";
import { mapWithConcurrency } from "./concurrency";
import { buildEvidencePacket } from "./packets";

/** Budget d'analyse élevé — pas de troncature aveugle courte. */
export const DEFAULT_PAGE_ANALYSIS_CHARS = 24_000;
const CHUNK_SIZE = 18_000;
const CHUNK_OVERLAP = 300;

export async function analyzeSourceForQuestion(params: {
  question: string;
  needs: InformationNeed[];
  source: {
    sourceId: string;
    url: string;
    title: string;
    content: string;
  };
  maxPageChars?: number;
  chunkConcurrency?: number;
  onChunkStats?: (stats: { chunkCount: number }) => void;
  analyzeSource?: (args: {
    question: string;
    needSummaries: string[];
    source: {
      sourceId: string;
      url: string;
      title: string;
      content: string;
    };
  }) => Promise<
    Array<{
      claim: string;
      value?: string;
      evidence: string;
      confidence?: EvidenceConfidence;
      caveat?: string;
    }>
  >;
}): Promise<SourceAnalysisResult> {
  const rawChars = params.source.content.length;
  const budget = params.maxPageChars ?? DEFAULT_PAGE_ANALYSIS_CHARS;
  const prepared = preparePageContentForAnalysis(params.source.content, budget);
  const analyzedChars = prepared.length;

  let extractionStatus: NonNullable<SourceAnalysisResult["extractionStatus"]> =
    "empty";
  let extractedRaw: Array<{
    claim: string;
    value?: string;
    evidence: string;
    confidence?: EvidenceConfidence;
    caveat?: string;
  }> = [];
  const caveats: string[] = [];
  const contradictions: string[] = [];

  if (params.analyzeSource) {
    try {
      const chunks = chunkPageContent(prepared, CHUNK_SIZE, CHUNK_OVERLAP);
      params.onChunkStats?.({ chunkCount: chunks.length });
      const seen = new Set<string>();
      const concurrency = Math.max(1, Math.min(params.chunkConcurrency ?? 1, 3));
      const parts = await mapWithConcurrency(chunks, concurrency, async (chunk) =>
        params.analyzeSource!({
          question: params.question,
          needSummaries: params.needs.map((n) => n.description),
          source: { ...params.source, content: chunk },
        })
      );
      for (const part of parts) {
        for (const row of part) {
          const key = `${row.claim}|${row.value ?? ""}`.toLowerCase();
          if (seen.has(key)) continue;
          seen.add(key);
          extractedRaw.push(row);
          if (row.caveat) caveats.push(row.caveat);
          if (/^contradiction:/i.test(row.claim)) {
            contradictions.push(row.evidence || row.claim);
          }
        }
      }
      extractionStatus = extractedRaw.length > 0 ? "ok" : "empty";
    } catch {
      extractedRaw = heuristicExtract(
        params.question,
        prepared,
        params.source.title
      );
      extractionStatus = extractedRaw.length > 0 ? "ok" : "extract_failed";
    }
  } else {
    extractedRaw = heuristicExtract(
      params.question,
      prepared,
      params.source.title
    );
    extractionStatus = extractedRaw.length > 0 ? "ok" : "empty";
  }

  const retrievedAt = new Date().toISOString();
  const extracted: WebEvidenceItem[] = extractedRaw
    .filter((e) => e.claim.trim() && e.evidence.trim())
    .slice(0, 12)
    .map((e, i) => ({
      id: `${params.source.sourceId}_ev_${i + 1}`,
      claim: e.claim.trim().slice(0, 400),
      value: e.value?.trim().slice(0, 200),
      sourceId: params.source.sourceId,
      url: params.source.url,
      title: params.source.title,
      evidence: e.evidence.trim().slice(0, 500),
      retrievedAt,
      confidence: e.confidence ?? inferConfidence(e),
      needId: matchNeedId(`${e.claim} ${e.value ?? ""}`, params.needs),
    }));

  const analysis: SourceAnalysisResult = {
    sourceId: params.source.sourceId,
    url: params.source.url,
    title: params.source.title,
    relevant: extracted.length > 0,
    notes:
      extracted.length === 0
        ? "Aucun fait pertinent extrait pour la question dans cette source"
        : undefined,
    extracted,
    analyzedChars,
    rawChars,
    extractionStatus,
  };

  analysis.packet = buildEvidencePacket({
    analysis,
    extractionStatus,
    caveats,
    contradictions,
    relevantFacts: extracted.map((e) => e.claim),
    importantValues: extracted
      .map((e) => e.value)
      .filter((v): v is string => Boolean(v)),
  });

  return analysis;
}

export function preparePageContentForAnalysis(
  text: string,
  budget: number
): string {
  const t = text.replace(/\s+/g, " ").trim();
  if (t.length <= budget) return t;
  return windowPageContent(t, budget);
}

export function windowPageContent(text: string, budget: number): string {
  const t = text.replace(/\s+/g, " ").trim();
  if (t.length <= budget) return t;
  const part = Math.floor(budget / 3);
  const head = t.slice(0, part);
  const midStart = Math.max(0, Math.floor(t.length / 2) - Math.floor(part / 2));
  const mid = t.slice(midStart, midStart + part);
  const tail = t.slice(-part);
  return `${head}\n…\n${mid}\n…\n${tail}`;
}

export function chunkPageContent(
  text: string,
  chunkSize: number,
  overlap: number
): string[] {
  const t = text.replace(/\s+/g, " ").trim();
  if (t.length <= chunkSize) return [t];
  const chunks: string[] = [];
  let start = 0;
  while (start < t.length) {
    const end = Math.min(t.length, start + chunkSize);
    chunks.push(t.slice(start, end));
    if (end >= t.length) break;
    start = Math.max(end - overlap, start + 1);
  }
  return chunks.slice(0, 3);
}

export function heuristicExtract(
  question: string,
  content: string,
  title: string
): Array<{
  claim: string;
  value?: string;
  evidence: string;
  confidence?: EvidenceConfidence;
}> {
  const qTokens = tokenize(question);
  const sentences = splitContentUnits(content);

  const scored = sentences.map((s) => {
    const low = normalizeText(s);
    const overlap = qTokens.filter((t) => low.includes(t)).length;
    const hasNumber = /\d/.test(s);
    const hasUnit =
      /(?:€|\$)|(?:\b(?:eur|euros?|usd|%|w|kw|mhz|ghz|go|mo|gb|mb|fps|ms|kg|g|db|m³|m3)\b)/i.test(
        s
      );
    const stemOverlap = qTokens.filter((t) => {
      if (t.length < 5) return false;
      return low
        .split(/[^a-z0-9]+/)
        .some(
          (w) =>
            w.length >= 5 &&
            (w.startsWith(t.slice(0, 5)) || t.startsWith(w.slice(0, 5)))
        );
    }).length;
    const lexical = Math.max(overlap, stemOverlap);
    if (lexical === 0 && !hasNumber) {
      return { s, score: 0, overlap: 0, hasNumber: false };
    }
    const score = lexical * 4 + (hasNumber ? 2 : 0) + (hasUnit ? 2 : 0);
    return { s, score, overlap, hasNumber };
  });

  scored.sort((a, b) => b.score - a.score);

  const out: Array<{
    claim: string;
    value?: string;
    evidence: string;
    confidence?: EvidenceConfidence;
  }> = [];

  for (const row of scored) {
    if (row.score < 3 || out.length >= 8) break;
    out.push({
      claim: `${title ? `${title} — ` : ""}${row.s.slice(0, 180)}`,
      value: extractSalientValue(row.s),
      evidence: row.s,
      confidence: row.overlap >= 2 && row.hasNumber ? "high" : "medium",
    });
  }

  return out;
}

function splitContentUnits(content: string): string[] {
  const raw = content
    .split(/(?<=[.!?•;\n])\s+/)
    .map((s) => s.trim())
    .filter(Boolean);
  const units: string[] = [];
  for (const part of raw) {
    if (part.length <= 420) {
      if (part.length >= 20) units.push(part);
      continue;
    }
    for (let i = 0; i < part.length; i += 280) {
      const chunk = part.slice(i, i + 320).trim();
      if (chunk.length >= 20) units.push(chunk);
    }
  }
  return units;
}

function extractSalientValue(sentence: string): string | undefined {
  const m = sentence.match(
    /(\d+(?:[.,]\d+)?(?:\s?\d{3})*)\s*(€|eur|euros?|\$|usd|%|W|kW|MHz|GHz|Go|Mo|GB|MB|fps|ms|dB|m³|m3)?/i
  );
  if (!m) return undefined;
  return `${m[1]}${m[2] ? ` ${m[2]}` : ""}`.trim();
}

function inferConfidence(e: {
  value?: string;
  evidence: string;
}): EvidenceConfidence {
  if (
    e.value &&
    /\d/.test(e.value) &&
    e.evidence.includes(e.value.split(/\s+/)[0]!)
  ) {
    return "high";
  }
  return "medium";
}

function matchNeedId(
  text: string,
  needs: InformationNeed[]
): string | undefined {
  const low = text.toLowerCase();
  let best: { id: string; score: number } | undefined;
  for (const n of needs) {
    const tokens = tokenize(n.description);
    const score = tokens.filter((t) => low.includes(t)).length;
    if (!best || score > best.score) best = { id: n.id, score };
  }
  return best && best.score > 0 ? best.id : needs[0]?.id;
}

function normalizeText(text: string): string {
  return text
    .toLowerCase()
    .normalize("NFD")
    .replace(/\p{M}/gu, "");
}

function tokenize(text: string): string[] {
  return normalizeText(text)
    .split(/[^a-z0-9]+/i)
    .filter((t) => t.length >= 4)
    .slice(0, 16);
}
