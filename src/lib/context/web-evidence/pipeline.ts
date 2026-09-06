/**
 * Pipeline Web Evidence V4 — search → select → fetch → extract → consolidate →
 * coverage → deepen itératif (expand SERP puis follow-up) → synthesis context.
 */
import { searchResultsToWebSources } from "@/lib/context/web-provenance";
import type { SearchResult } from "@/lib/tools/types";
import { fetchWebPageText } from "@/lib/tools/web-search/fetch-page";
import { mapWithConcurrency } from "./concurrency";
import { consolidateEvidence } from "./consolidate";
import { evaluateCoverage } from "./coverage";
import {
  analyzeSourceForQuestion,
  DEFAULT_PAGE_ANALYSIS_CHARS,
} from "./extract";
import {
  buildFinalWebApplicationContext,
  formatEvidenceContextBlock,
  formatResidualSourcesBlock,
} from "./format";
import { deriveInformationNeeds } from "./information-needs";
import { formatEvidencePacketsBlock } from "./packets";
import { selectSourcesForAnalysis } from "./select-sources";
import type {
  EvidencePacket,
  SourceAnalysisResult,
  WebEvidenceItem,
  WebEvidencePipelineInput,
  WebEvidencePipelineResult,
  WebEvidenceTraceStep,
  WebEvidencePipelineMetrics,
} from "./types";

const DEFAULT_EXTRACTION_CONCURRENCY = 2;
const DEFAULT_MAX_FOLLOW_UP_PASSES = 3;
const DEFAULT_MAX_CANDIDATES = 30;
const DEFAULT_MAX_ANALYZE = 10;
/** Plafond dur toutes passes confondues (batch initial + expansions + follow-ups). */
const DEFAULT_MAX_TOTAL_ANALYZE = 28;
/** Pages à analyser par vague d'extension SERP. */
const EXPAND_BATCH_SIZE = 6;
/** Arrêt si aucune nouvelle preuve après N vagues. */
const MAX_STAGNANT_PASSES = 2;

export async function runWebEvidencePipeline(
  input: WebEvidencePipelineInput
): Promise<WebEvidencePipelineResult> {
  const trace: WebEvidenceTraceStep[] = [];
  const pageContents: Record<string, string> = { ...input.pageContents };
  const pipelineStarted = Date.now();
  const metrics: WebEvidencePipelineMetrics = {
    totalWallMs: 0,
    searchMs: input.searchDurationMs ?? 0,
    fetchMs: 0,
    extractionMs: 0,
    consolidationMs: 0,
    coverageMs: 0,
    followUpMs: 0,
    synthesisMs: 0,
    candidateCount: 0,
    selectedCount: 0,
    fetchedCount: 0,
    analyzedCount: 0,
    chunkCount: 0,
    llmExtractionCount: 0,
    llmExtractionSuccess: 0,
    llmExtractionFailed: 0,
    cacheHits: 0,
    cacheMisses: 0,
    followUpCount: 0,
    extractionConcurrency: 0,
    llmCalls: [],
  };
  const extractionConcurrency =
    Math.max(1, Math.min(3, input.extractionConcurrency ?? DEFAULT_EXTRACTION_CONCURRENCY));
  const maxFollowUpPasses =
    input.maxFollowUpPasses ?? DEFAULT_MAX_FOLLOW_UP_PASSES;
  const maxAnalyzePages = input.maxAnalyzePages ?? DEFAULT_MAX_ANALYZE;
  const maxCandidateSources =
    input.maxCandidateSources ?? DEFAULT_MAX_CANDIDATES;
  const maxTotalAnalyzePages = Math.max(
    maxAnalyzePages,
    input.maxTotalAnalyzePages ?? DEFAULT_MAX_TOTAL_ANALYZE
  );
  const maxPageChars =
    input.maxPageCharsForAnalysis ?? DEFAULT_PAGE_ANALYSIS_CHARS;

  const needs = deriveInformationNeeds(
    input.userQuestion,
    input.conversationPriorUserMessages ?? []
  );

  let allSources = dedupeSources(input.sources);
  let researchPasses = 1;
  let previousCoverageReason = "";
  let stagnantPasses = 0;
  let skipSerpExpand = false;

  trace.push({
    stage: "search_results",
    inputSummary: input.searchQuery,
    outputSummary: `${allSources.length} sources SERP`,
    kept: allSources.map((s) => s.url),
    dropped: [],
    reason: "Résultats de recherche initiaux",
    meta: { candidateCount: allSources.length },
  });

  let selection = selectSourcesForAnalysis({
    query: input.searchQuery || input.userQuestion,
    sources: allSources.map((s) => ({
      sourceId: s.sourceId,
      url: s.url,
      title: s.title,
      snippet: s.snippet,
      domain: s.domain,
      pageContent: s.pageContent ?? pageContents[s.url],
    })),
    maxCandidates: maxCandidateSources,
    maxFetch: maxAnalyzePages,
  });

  trace.push({
    stage: "source_selection",
    inputSummary: `${allSources.length} sources`,
    outputSummary: `${selection.toAnalyze.length} à analyser / ${selection.toFetch.length} à fetch`,
    kept: selection.decisions.filter((d) => d.selected).map((d) => d.url),
    dropped: selection.decisions.filter((d) => !d.selected).map((d) => d.url),
    reason: "Pertinence, diversité de domaines, budget d'analyse",
  });

  const fetchStarted = Date.now();
  const fetched = await fetchMissingPages(
    selection.toFetch.map((s) => ({
      url: s.url,
      title: s.title,
      domain: s.domain,
    })),
    pageContents,
    maxPageChars,
    input.onSourceProgress
  );

  trace.push({
    stage: "fetch",
    inputSummary: `${selection.toFetch.length} demandées`,
    outputSummary: `${fetched.ok.length} OK / ${fetched.failed.length} échecs`,
    kept: fetched.ok,
    dropped: fetched.failed,
    reason: "Fetch pages — un échec n'arrête pas le pipeline",
    meta: { fetchMs: Date.now() - fetchStarted },
  });
  metrics.fetchMs += Date.now() - fetchStarted;
  metrics.fetchedCount += fetched.ok.length;

  // seed pageContents from sources (évite fetch réseau inutile)
  for (const s of selection.toAnalyze) {
    const existing = s.pageContent?.trim();
    if (existing && existing.length >= 12 && !pageContents[s.url]) {
      pageContents[s.url] = existing;
    }
  }

  let analyses = await analyzePages({
    targets: selection.toAnalyze.slice(0, maxAnalyzePages).map((s) => ({
      sourceId: s.sourceId,
      url: s.url,
      title: s.title,
      snippet: s.snippet,
      domain: s.domain,
      pageContent: s.pageContent,
    })),
    pageContents,
    question: input.userQuestion,
    needs,
    maxPageChars,
    concurrency: extractionConcurrency,
    analyzeSource: input.analyzeSource,
    onSourceProgress: input.onSourceProgress,
  });

  let evidence = analyses.flatMap((a) => a.extracted);
  let packets = collectPackets(analyses);
  pushAnalysisTraces(trace, analyses, evidence);

  let consolidated = consolidateEvidence(evidence);
  trace.push({
    stage: "consolidation",
    inputSummary: `${evidence.length} preuves`,
    outputSummary: `${consolidated.length} groupes`,
    kept: consolidated.map((g) => g.key),
    dropped: [],
    reason: "Déduplication sans écraser les contradictions",
  });

  const divergences = consolidated.filter((g) => g.agreement === "diverge");
  if (divergences.length > 0) {
    trace.push({
      stage: "contradiction_check",
      inputSummary: `${consolidated.length} groupes`,
      outputSummary: `${divergences.length} divergences`,
      kept: divergences.map((g) => `${g.claim}: ${g.values.join(" | ")}`),
      dropped: [],
      reason: "Valeurs divergentes conservées avec provenance",
    });
  }

  let coverage = evaluateCoverage({
    needs,
    evidence,
    consolidated,
    question: input.userQuestion,
    searchQuery: input.searchQuery,
    priorUserMessages: input.conversationPriorUserMessages ?? [],
  });
  coverage = await enrichFollowUpQueries(coverage, input, evidence);

  trace.push({
    stage: "coverage_check",
    inputSummary: `${needs.length} besoins`,
    outputSummary: coverage.reason,
    kept: coverage.satisfiedNeedIds,
    dropped: coverage.missingNeedIds,
    reason: coverage.sufficient ? "OK" : "suivi recommandé",
    meta: { followUpQueries: coverage.followUpQueries },
  });

  // Recherche itérative: expanser le SERP déjà connu, puis nouveau search si besoin.
  // Stop: couverture OK, budget épuisé, stagnation, ou plus de leviers.
  while (!coverage.sufficient) {
    const remainingBudget = maxTotalAnalyzePages - analyses.length;
    if (remainingBudget <= 0) {
      trace.push({
        stage: "coverage_check",
        inputSummary: `${analyses.length}/${maxTotalAnalyzePages} pages`,
        outputSummary: "Budget d'analyse atteint",
        kept: coverage.satisfiedNeedIds,
        dropped: coverage.missingNeedIds,
        reason: "Arrêt: plafond total de pages analysées",
      });
      break;
    }

    const analyzedUrls = new Set(analyses.map((a) => a.url));
    const remainingSources = allSources.filter((s) => !analyzedUrls.has(s.url));

    // 1) Préférer analyser d'autres candidats SERP déjà découverts.
    if (
      !skipSerpExpand &&
      remainingSources.length > 0 &&
      stagnantPasses < MAX_STAGNANT_PASSES
    ) {
      const batchSize = Math.min(
        EXPAND_BATCH_SIZE,
        remainingBudget,
        remainingSources.length
      );
      const expandSelection = selectSourcesForAnalysis({
        query: input.searchQuery || input.userQuestion,
        sources: remainingSources.map((s) => ({
          sourceId: s.sourceId,
          url: s.url,
          title: s.title,
          snippet: s.snippet,
          domain: s.domain,
          pageContent: s.pageContent ?? pageContents[s.url],
        })),
        maxCandidates: Math.min(remainingSources.length, maxCandidateSources),
        maxFetch: batchSize,
      });

      if (expandSelection.toAnalyze.length > 0) {
        const evidenceBefore = evidence.length;
        const fetchStartedExpand = Date.now();
        await fetchMissingPages(
          expandSelection.toFetch.map((s) => ({
            url: s.url,
            title: s.title,
            domain: s.domain,
          })),
          pageContents,
          maxPageChars,
          input.onSourceProgress
        );
        metrics.fetchMs += Date.now() - fetchStartedExpand;

        const expandAnalyses = await analyzePages({
          targets: expandSelection.toAnalyze.slice(0, batchSize).map((s) => ({
            sourceId: s.sourceId,
            url: s.url,
            title: s.title,
            snippet: s.snippet,
            domain: s.domain,
            pageContent: s.pageContent,
          })),
          pageContents,
          question: input.userQuestion,
          needs,
          maxPageChars,
          concurrency: extractionConcurrency,
          analyzeSource: input.analyzeSource,
          onSourceProgress: input.onSourceProgress,
        });

        analyses = [...analyses, ...expandAnalyses];
        evidence = analyses.flatMap((a) => a.extracted);
        packets = collectPackets(analyses);
        pushAnalysisTraces(
          trace,
          expandAnalyses,
          expandAnalyses.flatMap((a) => a.extracted)
        );

        consolidated = consolidateEvidence(evidence);
        coverage = evaluateCoverage({
          needs,
          evidence,
          consolidated,
          question: input.userQuestion,
          searchQuery: input.searchQuery,
          priorUserMessages: input.conversationPriorUserMessages ?? [],
        });
        coverage = await enrichFollowUpQueries(coverage, input, evidence);

        const evidenceGrew = evidence.length > evidenceBefore;
        const reasonChanged = coverage.reason !== previousCoverageReason;
        previousCoverageReason = coverage.reason;

        trace.push({
          stage: "coverage_check",
          inputSummary: `expand +${expandAnalyses.length} (reste SERP ${
            remainingSources.length - expandAnalyses.length
          })`,
          outputSummary: coverage.reason,
          kept: coverage.satisfiedNeedIds,
          dropped: coverage.missingNeedIds,
          reason: coverage.sufficient
            ? "Couverture OK après extension SERP"
            : "Couverture encore partielle — poursuite",
          meta: {
            analyzedTotal: analyses.length,
            maxTotalAnalyzePages,
            evidenceDelta: evidence.length - evidenceBefore,
          },
        });

        if (coverage.sufficient) break;

        if (evidenceGrew || reasonChanged) {
          stagnantPasses = 0;
          continue;
        }

        stagnantPasses += 1;
        // Extension SERP stagnante: tenter encore un lot si budget, sinon follow-up.
        if (stagnantPasses < MAX_STAGNANT_PASSES) {
          continue;
        }
        trace.push({
          stage: "coverage_check",
          inputSummary: `stagnant×${stagnantPasses}`,
          outputSummary: "Extension SERP stagnante — bascule follow-up",
          kept: coverage.satisfiedNeedIds,
          dropped: coverage.missingNeedIds,
          reason: "Pas de nouvelles preuves utiles sur le SERP courant",
        });
        skipSerpExpand = true;
        stagnantPasses = 0;
      }
    }

    // 2) Plus de candidats SERP utiles → recherche complémentaire.
    if (
      coverage.followUpQueries.length === 0 ||
      researchPasses > maxFollowUpPasses ||
      !input.runFollowUpSearch
    ) {
      break;
    }

    const query = coverage.followUpQueries[0]!;
    researchPasses += 1;
    metrics.followUpCount += 1;
    const evidenceBeforeFollow = evidence.length;
    const followStarted = Date.now();
    try {
      const follow = await input.runFollowUpSearch(query);
      metrics.followUpMs += Date.now() - followStarted;
      if (follow.pageContents) Object.assign(pageContents, follow.pageContents);

      const known = new Set(allSources.map((s) => s.url));
      const newSources = dedupeSources(follow.sources).filter(
        (s) => !known.has(s.url)
      );
      allSources = [...allSources, ...newSources];
      // Nouvelles URLs follow-up → réactiver l'expansion SERP sur ce lot.
      skipSerpExpand = false;

      trace.push({
        stage: "follow_up_search",
        inputSummary: query,
        outputSummary: `${newSources.length} nouvelles sources (pass ${researchPasses})`,
        kept: newSources.map((s) => s.url),
        dropped: [],
        reason: `Besoins manquants: ${
          coverage.missingNeedIds.join(", ") || "couverture insuffisante"
        }`,
        meta: { pass: researchPasses, query },
      });

      if (newSources.length === 0) {
        stagnantPasses += 1;
        if (stagnantPasses >= MAX_STAGNANT_PASSES) break;
        continue;
      }

      const followBudget = Math.min(
        EXPAND_BATCH_SIZE,
        remainingBudget,
        newSources.length
      );
      const followSelection = selectSourcesForAnalysis({
        query,
        sources: newSources.map((s) => ({
          sourceId: s.sourceId,
          url: s.url,
          title: s.title,
          snippet: s.snippet,
          domain: s.domain,
          pageContent: s.pageContent ?? pageContents[s.url],
        })),
        maxCandidates: Math.min(maxCandidateSources, newSources.length),
        maxFetch: followBudget,
      });

      await fetchMissingPages(
        followSelection.toFetch.map((s) => ({
          url: s.url,
          title: s.title,
          domain: s.domain,
        })),
        pageContents,
        maxPageChars,
        input.onSourceProgress
      );

      const followAnalyses = await analyzePages({
        targets: followSelection.toAnalyze.slice(0, followBudget).map((s) => ({
          sourceId: s.sourceId,
          url: s.url,
          title: s.title,
          snippet: s.snippet,
          domain: s.domain,
          pageContent: s.pageContent,
        })),
        pageContents,
        question: input.userQuestion,
        needs,
        maxPageChars,
        concurrency: extractionConcurrency,
        analyzeSource: input.analyzeSource,
        onSourceProgress: input.onSourceProgress,
      });

      analyses = [...analyses, ...followAnalyses];
      evidence = analyses.flatMap((a) => a.extracted);
      packets = collectPackets(analyses);
      pushAnalysisTraces(
        trace,
        followAnalyses,
        followAnalyses.flatMap((a) => a.extracted)
      );

      consolidated = consolidateEvidence(evidence);
      coverage = evaluateCoverage({
        needs,
        evidence,
        consolidated,
        question: input.userQuestion,
        searchQuery: input.searchQuery,
        priorUserMessages: input.conversationPriorUserMessages ?? [],
      });
      coverage = await enrichFollowUpQueries(coverage, input, evidence);

      trace.push({
        stage: "coverage_check",
        inputSummary: `pass ${researchPasses}`,
        outputSummary: coverage.reason,
        kept: coverage.satisfiedNeedIds,
        dropped: coverage.missingNeedIds,
        reason: coverage.sufficient
          ? "Couverture OK après follow-up"
          : "Couverture encore partielle — poursuite",
      });

      if (
        evidence.length <= evidenceBeforeFollow ||
        coverage.reason === previousCoverageReason
      ) {
        stagnantPasses += 1;
      } else {
        stagnantPasses = 0;
      }
      previousCoverageReason = coverage.reason;

      if (stagnantPasses >= MAX_STAGNANT_PASSES && !coverage.sufficient) {
        trace.push({
          stage: "coverage_check",
          inputSummary: `stagnant×${stagnantPasses}`,
          outputSummary: "Progression stagnante — arrêt follow-up",
          kept: coverage.satisfiedNeedIds,
          dropped: coverage.missingNeedIds,
          reason: "Pas de nouvelles preuves utiles",
        });
        break;
      }
    } catch (err) {
      metrics.followUpMs += Date.now() - followStarted;
      trace.push({
        stage: "follow_up_search",
        inputSummary: query,
        outputSummary: "échec — conservation des preuves existantes",
        kept: evidence.map((e) => e.id),
        dropped: [],
        reason: err instanceof Error ? err.message : String(err),
      });
      break;
    }
  }

  const evidenceContextBlock =
    packets.length > 0
      ? appendCoverageAndContradictions(
          formatEvidencePacketsBlock(packets, {
            maxPackets: Math.max(8, maxAnalyzePages + 2),
            maxChars: 9_000,
          }),
          coverage,
          consolidated
        )
      : formatEvidenceContextBlock({
          evidence,
          consolidated,
          coverage,
        });

  const residualSources = selection.toAnalyze.filter(
    (s) => !analyses.some((a) => a.url === s.url && a.relevant)
  );
  const residualSearchResults: SearchResult[] = residualSources
    .slice(0, 2)
    .map((s) => ({
      title: s.title,
      url: s.url,
      snippet: s.snippet,
      domain: s.domain ?? "",
    }));
  const residualRecords = searchResultsToWebSources(
    input.searchQuery || input.userQuestion,
    residualSearchResults,
    { pageContents }
  );
  const residualSourcesBlock = formatResidualSourcesBlock(residualRecords, {
    maxSources: 2,
    maxPageChars: 350,
  });

  const finalApplicationContext = buildFinalWebApplicationContext({
    evidenceBlock: evidenceContextBlock,
    residualBlock: residualSourcesBlock,
    maxChars: 10_000,
  });

  trace.push({
    stage: "final_application_context",
    inputSummary: `packets=${packets.length} evidence=${evidence.length}`,
    outputSummary: `${finalApplicationContext.length} chars`,
    kept: ["web_evidence"],
    dropped: selection.decisions.filter((d) => !d.selected).map((d) => d.url),
    reason: "Preuves condensées prioritaires — texte brut secondaire",
    meta: {
      packetCount: packets.length,
      evidenceCount: evidence.length,
      contextChars: finalApplicationContext.length,
      researchPasses,
      extractionConcurrency,
    },
  });

  return {
    needs: coverage.needs,
    selection: selection.decisions,
    analyses,
    evidence,
    packets,
    consolidated,
    coverage,
    evidenceContextBlock,
    residualSourcesBlock,
    finalApplicationContext,
    trace,
    researchPasses,
    metrics: { ...metrics, totalWallMs: Date.now() - pipelineStarted, extractionConcurrency },
  };
}

function dedupeSources(
  sources: WebEvidencePipelineInput["sources"]
): WebEvidencePipelineInput["sources"] {
  const seen = new Set<string>();
  const out: WebEvidencePipelineInput["sources"] = [];
  for (const s of sources) {
    const key = s.url.trim();
    if (!key || seen.has(key)) continue;
    seen.add(key);
    out.push(s);
  }
  return out;
}

function collectPackets(analyses: SourceAnalysisResult[]): EvidencePacket[] {
  return analyses
    .map((a) => a.packet)
    .filter((p): p is EvidencePacket => Boolean(p));
}

async function fetchMissingPages(
  targets: Array<{ url: string; title?: string; domain?: string }>,
  pageContents: Record<string, string>,
  maxChars: number,
  onProgress?: WebEvidencePipelineInput["onSourceProgress"]
): Promise<{ ok: string[]; failed: string[] }> {
  const ok: string[] = [];
  const failed: string[] = [];
  const total = targets.length;
  for (let i = 0; i < targets.length; i++) {
    const target = targets[i]!;
    const url = target.url;
    if (pageContents[url] && pageContents[url]!.trim().length >= 12) {
      ok.push(url);
      continue;
    }
    onProgress?.({
      phase: "fetching",
      url,
      title: target.title,
      domain: target.domain ?? domainFromUrl(url),
      index: i + 1,
      total,
    });
    try {
      const page = await fetchWebPageText(url, { maxChars });
      if (page.ok && page.text) {
        pageContents[url] = page.text;
        ok.push(url);
      } else {
        failed.push(url);
      }
    } catch {
      failed.push(url);
    }
  }
  return { ok, failed };
}

async function analyzePages(params: {
  targets: WebEvidencePipelineInput["sources"];
  pageContents: Record<string, string>;
  question: string;
  needs: WebEvidencePipelineResult["needs"];
  maxPageChars: number;
  concurrency: number;
  analyzeSource: WebEvidencePipelineInput["analyzeSource"];
  onSourceProgress?: WebEvidencePipelineInput["onSourceProgress"];
}): Promise<SourceAnalysisResult[]> {
  const total = params.targets.length;
  return mapWithConcurrency(params.targets, params.concurrency, async (src, index) => {
    params.onSourceProgress?.({
      phase: "analyzing",
      url: src.url,
      title: src.title,
      domain: src.domain ?? domainFromUrl(src.url),
      index: index + 1,
      total,
    });
    const content =
      params.pageContents[src.url] ?? src.pageContent ?? src.snippet ?? "";
    if (content.trim().length < 12) {
      return {
        sourceId: src.sourceId,
        url: src.url,
        title: src.title,
        relevant: false,
        notes: "Contenu page indisponible ou trop court",
        extracted: [] as WebEvidenceItem[],
        analyzedChars: 0,
        rawChars: content.length,
        extractionStatus: "fetch_failed" as const,
      };
    }

    return analyzeSourceForQuestion({
      question: params.question,
      needs: params.needs,
      source: {
        sourceId: src.sourceId,
        url: src.url,
        title: src.title,
        content,
      },
      maxPageChars: params.maxPageChars,
      analyzeSource: params.analyzeSource,
    });
  });
}

function domainFromUrl(url: string): string | undefined {
  try {
    return new URL(url).hostname.replace(/^www\./, "");
  } catch {
    return undefined;
  }
}

function pushAnalysisTraces(
  trace: WebEvidenceTraceStep[],
  analyses: SourceAnalysisResult[],
  evidence: WebEvidenceItem[]
): void {
  trace.push({
    stage: "source_analysis",
    inputSummary: `${analyses.length} pages`,
    outputSummary: `${evidence.length} preuves / ${
      analyses.filter((a) => a.extractionStatus === "ok").length
    } extractions OK`,
    kept: analyses.filter((a) => a.relevant).map((a) => a.url),
    dropped: analyses.filter((a) => !a.relevant).map((a) => a.url),
    reason: "Extraction indépendante orientée question (pas résumé de page)",
    meta: {
      failed: analyses.filter((a) => a.extractionStatus === "extract_failed")
        .length,
      fetchFailed: analyses.filter((a) => a.extractionStatus === "fetch_failed")
        .length,
    },
  });

  trace.push({
    stage: "extracted_evidence",
    inputSummary: `${evidence.length} items`,
    outputSummary: evidence
      .slice(0, 6)
      .map((e) => e.value || e.claim)
      .join(" | ")
      .slice(0, 400),
    kept: evidence.map((e) => e.id),
    dropped: [],
    reason: "Preuves avec provenance sourceId/url",
  });
}

function appendCoverageAndContradictions(
  packetsBlock: string,
  coverage: WebEvidencePipelineResult["coverage"],
  consolidated: WebEvidencePipelineResult["consolidated"]
): string {
  const extra: string[] = [];
  extra.push(`coverage_sufficient: ${coverage.sufficient}`);
  extra.push(`coverage_reason: ${coverage.reason}`);
  if (coverage.missingNeedIds.length > 0) {
    extra.push(
      `missing_needs_internal: ${coverage.missingNeedIds.join(", ")}`
    );
    extra.push(
      "negative_claim_policy: manques = raisonnement interne. Mention utilisateur seulement si critique. Sinon « non trouvé dans les preuves extraites » — pas d'absence mondiale."
    );
  }
  const divergences = consolidated.filter((g) => g.agreement === "diverge");
  if (divergences.length > 0) {
    extra.push("<contradictions>");
    extra.push(
      "Intégrer brièvement (ex. fourchette) ; exposé long seulement si le verdict/classement change."
    );
    for (const g of divergences.slice(0, 8)) {
      extra.push(
        `- ${g.claim} | values=${JSON.stringify(g.values)} | sources=${g.items
          .map((i) => `${i.sourceId}:${i.value ?? i.claim}`)
          .join("; ")}`
      );
    }
    extra.push("</contradictions>");
  }
  if (!packetsBlock.includes("</web_evidence>")) {
    return `${packetsBlock}\n${extra.join("\n")}`;
  }
  return packetsBlock.replace(
    "</web_evidence>",
    `${extra.join("\n")}\n</web_evidence>`
  );
}

async function enrichFollowUpQueries(
  coverage: WebEvidencePipelineResult["coverage"],
  input: WebEvidencePipelineInput,
  evidence: WebEvidenceItem[]
): Promise<WebEvidencePipelineResult["coverage"]> {
  if (
    coverage.sufficient ||
    !input.proposeFollowUpQueries ||
    coverage.missingNeedIds.length === 0
  ) {
    return coverage;
  }
  try {
    const extra = await input.proposeFollowUpQueries({
      question: input.userQuestion,
      missingNeeds: coverage.needs.filter((n) =>
        coverage.missingNeedIds.includes(n.id)
      ),
      existingEvidence: evidence,
    });
    return {
      ...coverage,
      followUpQueries: [
        ...new Set([...coverage.followUpQueries, ...extra]),
      ].slice(0, 4),
    };
  } catch {
    return coverage;
  }
}
