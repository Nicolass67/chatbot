/**
 * Extraction LLM question-focused — PAS un résumé de page.
 */

import { nanoid } from "nanoid";
import { withLmStudioGate } from "./llm-gate";
import {
  EXTRACTION_PROMPT_VERSION,
  buildExtractCacheKey,
  hashContent,
  readExtractCache,
  writeExtractCache,
} from "./extract-cache";
import type { LocalAIRuntime } from "@/lib/runtime/types";
import type {
  EvidenceConfidence,
  WebEvidencePipelineInput,
} from "./types";

export const PAGE_EVIDENCE_EXTRACTION_PROMPT_VERSION = EXTRACTION_PROMPT_VERSION;

export const PAGE_EVIDENCE_EXTRACTION_SYSTEM = `Tu es un extracteur de preuves Web, PAS un assistant de réponse.

Mission unique : à partir de LA question utilisateur et DU texte d'UNE source,
extraire uniquement les informations factuelles pertinentes pour permettre à
un autre modèle de répondre correctement.

INTERDIT :
- résumer la page en prose ;
- répondre à l'utilisateur ;
- inventer, compléter, deviner ou extrapoler ;
- transformer une estimation en valeur certaine ;
- attribuer une info absente de cette source ;
- garder marketing, introductions, histoire hors sujet, répétitions.

OBLIGATOIRE :
- faits condensés (noms, valeurs, unités, prix, devises, dates, perfs, limites, classements, conditions, nuances, contradictions internes) ;
- si une info cherchée est absente : ne rien inventer (listes vides) ;
- sortie JSON strict uniquement.

Format JSON :
{
  "relevantFacts": ["fait ultra-court", ...],
  "importantValues": ["Nom: 129 €", ...],
  "caveats": ["nuance / limite factuelle", ...],
  "contradictions": ["écart interne à la page", ...],
  "items": [
    {
      "claim": "affirmation courte",
      "value": "valeur si présente",
      "evidence": "extrait court verbatim justifiant",
      "confidence": "high" | "medium" | "low",
      "caveat": "optionnel"
    }
  ]
}

Cible : très compact (idéalement < 300 tokens utiles). FAITS > PROSE.`;


export const PAGE_EVIDENCE_JSON_SCHEMA = {
  name: "page_evidence_extraction",
  strict: true,
  schema: {
    type: "object",
    additionalProperties: false,
    properties: {
      relevantFacts: { type: "array", items: { type: "string" } },
      importantValues: { type: "array", items: { type: "string" } },
      caveats: { type: "array", items: { type: "string" } },
      contradictions: { type: "array", items: { type: "string" } },
      items: {
        type: "array",
        items: {
          type: "object",
          additionalProperties: false,
          properties: {
            claim: { type: "string" },
            value: { type: "string" },
            evidence: { type: "string" },
            confidence: { type: "string", enum: ["high", "medium", "low"] },
            caveat: { type: "string" },
          },
          required: ["claim", "evidence"],
        },
      },
    },
    required: ["relevantFacts", "importantValues", "caveats", "contradictions", "items"],
  },
} as const;

export type LlmPageExtraction = {
  relevantFacts: string[];
  importantValues: string[];
  caveats: string[];
  contradictions: string[];
  items: Array<{
    claim: string;
    value?: string;
    evidence: string;
    confidence?: EvidenceConfidence;
    caveat?: string;
  }>;
};

export function buildPageEvidenceExtractionUserPrompt(params: {
  question: string;
  needSummaries: string[];
  title: string;
  url: string;
  content: string;
}): string {
  const needs =
    params.needSummaries.length > 0
      ? params.needSummaries.map((n, i) => `${i + 1}. ${n}`).join("\n")
      : "(non listés — déduire de la question)";

  return `QUESTION UTILISATEUR :
${params.question}

BESOINS INFORMATIONNELS À COUVRIR SI PRÉSENTS DANS CETTE SOURCE :
${needs}

SOURCE :
title: ${params.title}
url: ${params.url}

TEXTE DE LA SOURCE (analyser pour la question — ignorer le hors-sujet) :
---
${params.content}
---

Extrais uniquement les preuves pertinentes pour la question. JSON strict.`;
}

export function parsePageEvidenceExtractionJson(
  raw: string
): LlmPageExtraction | null {
  const text = (raw ?? "").trim();
  if (!text) return null;
  const unfenced = text
    .replace(/^```(?:json)?\s*/i, "")
    .replace(/\s*```$/i, "")
    .trim();
  const start = unfenced.indexOf("{");
  const end = unfenced.lastIndexOf("}");
  if (start < 0 || end <= start) return null;
  try {
    const parsed = JSON.parse(unfenced.slice(start, end + 1)) as Partial<
      LlmPageExtraction
    >;
    const items = Array.isArray(parsed.items)
      ? parsed.items
          .filter(
            (it) =>
              it &&
              typeof it.claim === "string" &&
              it.claim.trim() &&
              typeof it.evidence === "string" &&
              it.evidence.trim()
          )
          .map((it) => ({
            claim: String(it.claim).trim().slice(0, 280),
            value:
              typeof it.value === "string" && it.value.trim()
                ? it.value.trim().slice(0, 120)
                : undefined,
            evidence: String(it.evidence).trim().slice(0, 320),
            confidence: normalizeConfidence(it.confidence),
            caveat:
              typeof it.caveat === "string" && it.caveat.trim()
                ? it.caveat.trim().slice(0, 200)
                : undefined,
          }))
          .slice(0, 10)
      : [];

    return {
      relevantFacts: asStringList(parsed.relevantFacts, 12, 200),
      importantValues: asStringList(parsed.importantValues, 12, 120),
      caveats: asStringList(parsed.caveats, 6, 180),
      contradictions: asStringList(parsed.contradictions, 6, 180),
      items,
    };
  } catch {
    return null;
  }
}

function asStringList(value: unknown, max: number, maxLen: number): string[] {
  if (!Array.isArray(value)) return [];
  return value
    .filter((x): x is string => typeof x === "string" && x.trim().length > 0)
    .map((x) => x.trim().slice(0, maxLen))
    .slice(0, max);
}

function normalizeConfidence(
  value: unknown
): EvidenceConfidence | undefined {
  if (value === "high" || value === "medium" || value === "low") return value;
  return undefined;
}

/** Hook analyzeSource → runtime local (content || reasoningContent). */
export function createLlmPageEvidenceAnalyzer(params: {
  runtime: LocalAIRuntime;
  model: string;
  signal?: AbortSignal;
  temperature?: number;
  maxTokens?: number;
  useStructuredOutput?: boolean;
  onLlmCall?: (metric: {
    durationMs: number;
    inputTokens?: number;
    outputTokens?: number;
    reasoningTokens?: number;
    status: "ok" | "error" | "cache_hit" | "fallback";
    url?: string;
    sourceId?: string;
  }) => void;
}): NonNullable<WebEvidencePipelineInput["analyzeSource"]> {
  const maxTokens = params.maxTokens ?? 450;
  const temperature = params.temperature ?? 0.1;
  const useStructured = params.useStructuredOutput !== false;

  return async ({ question, needSummaries, source }) => {
    const contentHash = hashContent(source.content);
    const cacheKey = buildExtractCacheKey({
      url: source.url,
      contentHash,
      question,
      promptVersion: EXTRACTION_PROMPT_VERSION,
      modelId: params.model,
    });

    const cached = readExtractCache(cacheKey);
    if (cached) {
      params.onLlmCall?.({
        durationMs: 0,
        status: "cache_hit",
        url: source.url,
        sourceId: source.sourceId,
      });
      return cached.rows.map((r) => ({
        claim: r.claim,
        value: r.value,
        evidence: r.evidence,
        confidence: r.confidence,
        caveat: r.caveat,
      }));
    }

    const messages = [
      { role: "system" as const, content: PAGE_EVIDENCE_EXTRACTION_SYSTEM },
      {
        role: "user" as const,
        content: buildPageEvidenceExtractionUserPrompt({
          question,
          needSummaries,
          title: source.title,
          url: source.url,
          content: source.content,
        }),
      },
    ];

    const runOnce = async (withSchema: boolean) => {
      const started = Date.now();
      try {
        const response = await withLmStudioGate(() =>
          params.runtime.chat({
            requestId: nanoid(),
            model: params.model,
            temperature,
            maxTokens,
            signal: params.signal,
            reasoningEffort: "none",
            messages,
            ...(withSchema
              ? {
                  responseFormat: {
                    type: "json_schema" as const,
                    json_schema: PAGE_EVIDENCE_JSON_SCHEMA,
                  },
                }
              : {}),
          })
        );
        const raw = `${response.content ?? ""}\n${
          response.reasoningContent ?? ""
        }`.trim();
        const parsed = parsePageEvidenceExtractionJson(raw);
        if (!parsed) throw new Error("extraction JSON invalide");
        params.onLlmCall?.({
          durationMs: Date.now() - started,
          inputTokens: response.usage?.promptTokens,
          outputTokens: response.usage?.completionTokens,
          reasoningTokens: response.usage?.reasoningTokens,
          status: withSchema ? "ok" : "fallback",
          url: source.url,
          sourceId: source.sourceId,
        });
        return parsed;
      } catch (err) {
        params.onLlmCall?.({
          durationMs: Date.now() - started,
          status: "error",
          url: source.url,
          sourceId: source.sourceId,
        });
        throw err;
      }
    };

    let parsed;
    if (useStructured) {
      try {
        parsed = await runOnce(true);
      } catch {
        parsed = await runOnce(false);
      }
    } else {
      parsed = await runOnce(false);
    }

    const rows: Array<{
      claim: string;
      value?: string;
      evidence: string;
      confidence?: EvidenceConfidence;
      caveat?: string;
    }> = [];

    if (parsed.items.length === 0 && parsed.importantValues.length > 0) {
      for (const v of parsed.importantValues.slice(0, 8)) {
        rows.push({ claim: v, value: v, evidence: v, confidence: "medium" });
      }
    } else {
      for (const it of parsed.items) {
        rows.push({
          claim: it.claim,
          value: it.value,
          evidence: it.evidence,
          confidence: it.confidence,
          caveat: it.caveat,
        });
      }
      for (const v of parsed.importantValues.slice(0, 6)) {
        if (rows.some((r) => r.value === v || r.claim === v)) continue;
        rows.push({ claim: v, value: v, evidence: v, confidence: "medium" });
      }
      for (const f of parsed.relevantFacts.slice(0, 6)) {
        if (rows.some((r) => r.claim === f)) continue;
        rows.push({ claim: f, evidence: f, confidence: "medium" });
      }
    }
    for (const c of parsed.caveats.slice(0, 4)) {
      rows.push({ claim: c, evidence: c, confidence: "low", caveat: c });
    }
    for (const c of parsed.contradictions.slice(0, 4)) {
      rows.push({
        claim: `contradiction: ${c}`,
        evidence: c,
        confidence: "medium",
        caveat: c,
      });
    }

    const limited = rows.slice(0, 14);
    writeExtractCache(cacheKey, {
      rows: limited.map((r) => ({
        claim: r.claim,
        value: r.value,
        evidence: r.evidence,
        confidence: r.confidence,
        caveat: r.caveat,
      })),
      storedAt: Date.now(),
    });
    return limited;
  };
}
