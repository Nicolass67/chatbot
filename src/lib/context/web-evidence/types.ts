/**
 * Preuves Web structurées — extraction orientée question (pas pages brutes).
 */

export type EvidenceConfidence = "high" | "medium" | "low";

export type InformationNeed = {
  id: string;
  /** Description générique (pas de catégorie métier figée). */
  description: string;
  priority: "critical" | "high" | "medium" | "low";
  status: "open" | "partial" | "satisfied" | "unsatisfiable";
};

export type WebEvidenceItem = {
  id: string;
  claim: string;
  value?: string;
  sourceId: string;
  url: string;
  title: string;
  /** Extrait verbatim / quasi-verbatim justifiant la claim. */
  evidence: string;
  retrievedAt: string;
  publicationDate?: string;
  confidence: EvidenceConfidence;
  needId?: string;
};

/**
 * Paquet compact par source pour la synthèse (V3).
 * Priorité : faits condensés + provenance — jamais un résumé de page.
 */
export type EvidencePacket = {
  sourceId: string;
  url: string;
  title: string;
  retrievedAt: string;
  publicationDate?: string;
  relevantFacts: string[];
  importantValues: string[];
  caveats: string[];
  contradictions: string[];
  /** Bloc ultra-compact (~150–300 tokens). */
  compactEvidence: string;
  extractionStatus:
    | "ok"
    | "empty"
    | "fetch_failed"
    | "extract_failed"
    | "skipped";
  items: WebEvidenceItem[];
};

export type SourceSelectionDecision = {
  sourceId: string;
  url: string;
  title: string;
  selected: boolean;
  score: number;
  reason: string;
  fetch: boolean;
};

export type SourceAnalysisResult = {
  sourceId: string;
  url: string;
  title: string;
  relevant: boolean;
  notes?: string;
  extracted: WebEvidenceItem[];
  analyzedChars: number;
  rawChars: number;
  packet?: EvidencePacket;
  extractionStatus?: EvidencePacket["extractionStatus"];
};

export type EvidenceAgreement = "agree" | "diverge" | "single" | "duplicate";

export type ConsolidatedEvidenceGroup = {
  key: string;
  claim: string;
  items: WebEvidenceItem[];
  agreement: EvidenceAgreement;
  values: string[];
};

export type CoverageReport = {
  needs: InformationNeed[];
  satisfiedNeedIds: string[];
  missingNeedIds: string[];
  contradictions: ConsolidatedEvidenceGroup[];
  sufficient: boolean;
  followUpQueries: string[];
  reason: string;
};

export type FollowUpSearchResult = {
  query: string;
  sources: Array<{
    sourceId: string;
    url: string;
    title: string;
    snippet: string;
    domain?: string;
    pageContent?: string;
  }>;
  pageContents?: Record<string, string>;
};

export type WebEvidencePipelineInput = {
  userQuestion: string;
  searchQuery: string;
  sources: Array<{
    sourceId: string;
    url: string;
    title: string;
    snippet: string;
    domain?: string;
    pageContent?: string;
  }>;
  pageContents: Record<string, string>;
  /** Budget du premier batch (puis expansions par lots). Défaut 10. */
  maxAnalyzePages?: number;
  maxCandidateSources?: number;
  /**
   * Plafond total de pages analysées (batch + expansions SERP + follow-ups).
   * Défaut ~28. La recherche s'arrête dès que la couverture est suffisante.
   */
  maxTotalAnalyzePages?: number;
  /** Défaut 2 (V4). Borné 1–3. LM Studio Max Concurrent Predictions doit être >= N. */
  extractionConcurrency?: number;
  /** Identifiant modèle pour cache d'extraction. */
  modelId?: string;
  /** Durée search amont (ms) pour observabilité. */
  searchDurationMs?: number;
  /** 0–4 recherches complémentaires (après épuisement des candidats SERP). */
  maxFollowUpPasses?: number;
  maxPageCharsForAnalysis?: number;
  conversationPriorUserMessages?: string[];
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
  proposeFollowUpQueries?: (args: {
    question: string;
    missingNeeds: InformationNeed[];
    existingEvidence: WebEvidenceItem[];
  }) => Promise<string[]>;
  runFollowUpSearch?: (query: string) => Promise<FollowUpSearchResult>;
  /** Fired as each page is fetched or analyzed (SSE source_progress). */
  onSourceProgress?: (info: {
    phase: "fetching" | "analyzing" | "done";
    url: string;
    title?: string;
    domain?: string;
    index: number;
    total: number;
  }) => void;
};

export type WebEvidencePipelineResult = {
  needs: InformationNeed[];
  selection: SourceSelectionDecision[];
  analyses: SourceAnalysisResult[];
  evidence: WebEvidenceItem[];
  packets: EvidencePacket[];
  consolidated: ConsolidatedEvidenceGroup[];
  coverage: CoverageReport;
  evidenceContextBlock: string;
  residualSourcesBlock: string;
  finalApplicationContext: string;
  trace: WebEvidenceTraceStep[];
  researchPasses: number;
  metrics: WebEvidencePipelineMetrics;
};

export type WebEvidenceLlmCallMetric = {
  stage: string;
  sourceId?: string;
  url?: string;
  durationMs: number;
  inputTokens?: number;
  outputTokens?: number;
  reasoningTokens?: number;
  status: "ok" | "error" | "cache_hit" | "fallback";
};

export type WebEvidencePipelineMetrics = {
  totalWallMs: number;
  searchMs: number;
  fetchMs: number;
  extractionMs: number;
  consolidationMs: number;
  coverageMs: number;
  followUpMs: number;
  synthesisMs: number;
  candidateCount: number;
  selectedCount: number;
  fetchedCount: number;
  analyzedCount: number;
  chunkCount: number;
  llmExtractionCount: number;
  llmExtractionSuccess: number;
  llmExtractionFailed: number;
  cacheHits: number;
  cacheMisses: number;
  followUpCount: number;
  extractionConcurrency: number;
  llmCalls: WebEvidenceLlmCallMetric[];
};


export type WebEvidenceTraceStep = {
  stage:
    | "search_results"
    | "source_selection"
    | "fetch"
    | "source_analysis"
    | "extracted_evidence"
    | "consolidation"
    | "coverage_check"
    | "follow_up_search"
    | "contradiction_check"
    | "final_application_context"
    | "metrics";
  inputSummary: string;
  outputSummary: string;
  kept: string[];
  dropped: string[];
  reason: string;
  meta?: Record<string, unknown>;
};
