import type {
  ConsolidatedEvidenceGroup,
  CoverageReport,
  InformationNeed,
  WebEvidenceItem,
} from "./types";
import { groundSearchQueryWithContext } from "@/lib/context/conversation-continuity";

/**
 * Coverage V4 — ne satisfait plus need_primary au moindre signal medium.
 * Matching générique par tokens de description / entités / contraintes.
 */
export function evaluateCoverage(params: {
  needs: InformationNeed[];
  evidence: WebEvidenceItem[];
  consolidated: ConsolidatedEvidenceGroup[];
  question: string;
  /** Requête SERP déjà ancrée (préférée pour les follow-ups). */
  searchQuery?: string;
  priorUserMessages?: string[];
  priorAssistantExcerpts?: string[];
}): CoverageReport {
  const evidenceBlob = params.evidence
    .map((e) => `${e.claim} ${e.value ?? ""} ${e.evidence}`)
    .join("\n")
    .toLowerCase();

  const topicBlob = [
    params.searchQuery ?? "",
    ...(params.priorAssistantExcerpts ?? []),
  ]
    .join("\n")
    .toLowerCase();

  const needs = params.needs.map((n) => {
    const status = assessNeed(n, params.evidence, evidenceBlob, topicBlob);
    return { ...n, status };
  });

  const satisfiedNeedIds = needs
    .filter((n) => n.status === "satisfied" || n.status === "partial")
    .filter((n) => n.status === "satisfied")
    .map((n) => n.id);

  const missingNeedIds = needs
    .filter(
      (n) =>
        (n.status === "open" || n.status === "partial") &&
        (n.priority === "critical" || n.priority === "high")
    )
    .map((n) => n.id);

  const contradictions = params.consolidated.filter(
    (g) => g.agreement === "diverge"
  );

  const criticalOpen = needs.some(
    (n) => n.priority === "critical" && n.status === "open"
  );
  const highOpen = missingNeedIds.length > 0;
  const sufficient =
    !criticalOpen &&
    !highOpen &&
    params.evidence.length > 0 &&
    needs.some((n) => n.id === "need_primary" && n.status === "satisfied");

  const followUpQueries = sufficient
    ? []
    : buildFollowUpQueries(
        params.question,
        needs,
        missingNeedIds,
        params.evidence,
        {
          searchQuery: params.searchQuery,
          priorUserMessages: params.priorUserMessages,
          priorAssistantExcerpts: params.priorAssistantExcerpts,
        }
      );

  return {
    needs,
    satisfiedNeedIds,
    missingNeedIds,
    contradictions,
    sufficient,
    followUpQueries,
    reason: sufficient
      ? "Couverture suffisante des besoins critiques."
      : missingNeedIds.length > 0
        ? `Besoins non couverts: ${missingNeedIds.join(", ")}`
        : params.evidence.length === 0
          ? "Aucune preuve exploitable extraite."
          : "Couverture partielle — follow-up recommandé.",
  };
}

function assessNeed(
  need: InformationNeed,
  evidence: WebEvidenceItem[],
  evidenceBlob: string,
  topicBlob = ""
): InformationNeed["status"] {
  const direct = evidence.filter((e) => e.needId === need.id);
  const tokens = tokenize(need.description);
  const overlap = tokens.filter((t) => evidenceBlob.includes(t)).length;
  const numericNeed = /\d/.test(need.description);
  const hasNumericEvidence = evidence.some(
    (e) => /\d/.test(e.value ?? "") || /\d/.test(e.evidence)
  );

  if (need.id === "need_resolve_reference") {
    // Preuve hors-sujet (ex. Tesla pour des GPU) ≠ référence résolue.
    const topicTokens = tokenize(topicBlob).filter((t) => t.length >= 4);
    if (topicTokens.length === 0) {
      return evidence.length > 0 ? "satisfied" : "open";
    }
    const hit = topicTokens.some((t) => evidenceBlob.includes(t));
    return hit ? "satisfied" : evidence.length > 0 ? "partial" : "open";
  }

  if (need.id === "need_primary") {
    const strong = evidence.filter(
      (e) => e.confidence === "high" || e.confidence === "medium"
    );
    const diverseSources = new Set(strong.map((e) => e.sourceId)).size;
    if (strong.length >= 3 && diverseSources >= 2) return "satisfied";
    if (strong.length >= 2) return "partial";
    if (strong.length >= 1) return "partial";
    return "open";
  }

  if (need.id === "need_constraints") {
    if (numericNeed && hasNumericEvidence && overlap >= 1) return "satisfied";
    if (hasNumericEvidence) return "partial";
    return "open";
  }

  if (need.id === "need_entities" || need.id === "need_compare" || need.id === "need_recommendation") {
    if (overlap >= Math.min(3, Math.max(1, tokens.length))) return "satisfied";
    if (overlap >= 1 || direct.length > 0) return "partial";
    return "open";
  }

  if (direct.length >= 2) return "satisfied";
  if (direct.length === 1 || overlap >= 2) return "partial";
  if (overlap >= 1) return "partial";
  return "open";
}

function buildFollowUpQueries(
  question: string,
  needs: InformationNeed[],
  missingNeedIds: string[],
  evidence: WebEvidenceItem[],
  options?: {
    searchQuery?: string;
    priorUserMessages?: string[];
    priorAssistantExcerpts?: string[];
  }
): string[] {
  const baseRaw = (options?.searchQuery?.trim() || question).trim();
  const base = groundSearchQueryWithContext({
    query: baseRaw,
    recentUserMessages: options?.priorUserMessages ?? [],
    recentAssistantExcerpts: options?.priorAssistantExcerpts ?? [],
  });
  const missing = needs.filter((n) => missingNeedIds.includes(n.id));
  const queries: string[] = [];
  for (const need of missing.slice(0, 3)) {
    const focus = need.description.replace(/^[^:]+:\s*/, "").slice(0, 100);
    queries.push(`${base} — ${focus}`.slice(0, 180));
  }
  if (queries.length === 0 && evidence.length === 0) {
    queries.push(base.slice(0, 180));
  }
  return [...new Set(queries.map((s) => s.trim()).filter(Boolean))].slice(0, 3);
}

function tokenize(text: string): string[] {
  return text
    .toLowerCase()
    .normalize("NFD")
    .replace(/\p{M}/gu, "")
    .split(/[^a-z0-9]+/i)
    .filter((t) => t.length >= 4)
    .slice(0, 16);
}
