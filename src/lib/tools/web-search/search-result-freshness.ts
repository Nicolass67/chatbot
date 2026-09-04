import type { SearchResult } from "@/lib/tools/types";
import type { TemporalScope } from "@/lib/agent/temporal";
import { extractYears } from "@/lib/agent/temporal";

export type FreshnessStatus = "fresh" | "stale" | "unknown";

export interface FreshnessAssessment {
  status: FreshnessStatus;
  confidence: number;
  reason: string;
  signals: string[];
}

export interface FreshnessEvaluationContext {
  fetchedAt: Date;
  temporalScope: TemporalScope;
  referenceYear?: number | null;
  currentYear: number;
}

const MS_PER_DAY = 86_400_000;

function parsePublishedDate(value: string | undefined): Date | null {
  if (!value?.trim()) return null;
  const parsed = Date.parse(value);
  if (Number.isNaN(parsed)) return null;
  return new Date(parsed);
}

function daysBetween(later: Date, earlier: Date): number {
  return Math.floor((later.getTime() - earlier.getTime()) / MS_PER_DAY);
}

export function assessResultFreshness(
  result: SearchResult,
  context: FreshnessEvaluationContext
): FreshnessAssessment {
  const signals: string[] = [];
  const publishedAt = parsePublishedDate(result.publishedAt);

  if (publishedAt) {
    const ageDays = daysBetween(context.fetchedAt, publishedAt);
    signals.push(`publishedAt=${publishedAt.toISOString().slice(0, 10)}`);

    if (context.temporalScope === "historical" && context.referenceYear) {
      const pubYear = publishedAt.getFullYear();
      if (pubYear === context.referenceYear) {
        return {
          status: "fresh",
          confidence: 0.9,
          reason: "Date de publication alignée avec la période historique demandée.",
          signals,
        };
      }
      if (Math.abs(pubYear - context.referenceYear) > 1) {
        return {
          status: "stale",
          confidence: 0.85,
          reason: `Publication (${pubYear}) éloignée de la période demandée (${context.referenceYear}).`,
          signals,
        };
      }
      return {
        status: "unknown",
        confidence: 0.5,
        reason: "Date de publication partiellement alignée avec la période demandée.",
        signals,
      };
    }

    if (context.temporalScope === "future") {
      if (publishedAt > context.fetchedAt) {
        return {
          status: "fresh",
          confidence: 0.75,
          reason: "Publication postérieure à la date de récupération (contenu prospectif).",
          signals,
        };
      }
      return {
        status: "unknown",
        confidence: 0.45,
        reason: "Publication antérieure à une demande orientée futur.",
        signals,
      };
    }

    if (ageDays <= 7) {
      return {
        status: "fresh",
        confidence: 0.92,
        reason: "Publication très récente (≤ 7 jours).",
        signals,
      };
    }
    if (ageDays <= 30) {
      return {
        status: "fresh",
        confidence: 0.8,
        reason: "Publication récente (≤ 30 jours).",
        signals,
      };
    }
    if (ageDays <= 180) {
      return {
        status: "unknown",
        confidence: 0.55,
        reason: "Publication datée mais pas récente.",
        signals,
      };
    }
    return {
      status: "stale",
      confidence: 0.8,
      reason: "Publication datée de plus de six mois.",
      signals,
    };
  }

  const text = `${result.title} ${result.snippet}`;
  const detectedYears = extractYears(text);

  if (context.temporalScope === "historical" && context.referenceYear) {
    if (detectedYears.includes(context.referenceYear)) {
      signals.push(`year=${context.referenceYear}`);
      return {
        status: "fresh",
        confidence: 0.7,
        reason: "Année demandée mentionnée dans le résultat.",
        signals,
      };
    }
    if (detectedYears.some((y) => y < context.referenceYear! - 1)) {
      return {
        status: "stale",
        confidence: 0.75,
        reason: "Année mentionnée antérieure à la période demandée.",
        signals: [...signals, `years=${detectedYears.join(",")}`],
      };
    }
  }

  if (
    (context.temporalScope === "current" || context.temporalScope === "recent") &&
    detectedYears.some((y) => y < context.currentYear - 1)
  ) {
    return {
      status: "stale",
      confidence: 0.7,
      reason: "Le résultat mentionne une année clairement antérieure.",
      signals: [...signals, `years=${detectedYears.join(",")}`],
    };
  }

  return {
    status: "unknown",
    confidence: 0.45,
    reason: "Aucune date de publication fiable — fraîcheur indéterminée.",
    signals,
  };
}

export interface AggregateFreshnessResult {
  freshCount: number;
  staleCount: number;
  unknownCount: number;
  assessments: Array<FreshnessAssessment & { url: string; title: string }>;
  sufficientForCurrentKnowledge: boolean;
  blockReason?: string;
}

export function assessSearchResultsFreshness(
  results: SearchResult[],
  context: FreshnessEvaluationContext
): AggregateFreshnessResult {
  const assessments = results.map((r) => ({
    url: r.url,
    title: r.title,
    ...assessResultFreshness(r, context),
  }));

  const freshCount = assessments.filter((a) => a.status === "fresh").length;
  const staleCount = assessments.filter((a) => a.status === "stale").length;
  const unknownCount = assessments.filter((a) => a.status === "unknown").length;

  if (results.length === 0) {
    return {
      freshCount: 0,
      staleCount: 0,
      unknownCount: 0,
      assessments,
      sufficientForCurrentKnowledge: false,
      blockReason: "Aucune source Web disponible.",
    };
  }

  if (context.temporalScope === "historical") {
    return {
      freshCount,
      staleCount,
      unknownCount,
      assessments,
      sufficientForCurrentKnowledge: freshCount > 0 || unknownCount > 0,
      blockReason:
        freshCount > 0 || unknownCount > 0
          ? undefined
          : "Aucune source alignée avec la période historique demandée.",
    };
  }

  if (context.temporalScope === "current" || context.temporalScope === "recent") {
    if (staleCount > 0 && freshCount === 0 && unknownCount === 0) {
      return {
        freshCount,
        staleCount,
        unknownCount,
        assessments,
        sufficientForCurrentKnowledge: false,
        blockReason:
          "Les sources Web disponibles semblent datées pour une demande d'information actuelle.",
      };
    }
    return {
      freshCount,
      staleCount,
      unknownCount,
      assessments,
      sufficientForCurrentKnowledge: true,
    };
  }

  return {
    freshCount,
    staleCount,
    unknownCount,
    assessments,
    sufficientForCurrentKnowledge: true,
  };
}

export function formatFreshnessNotesForSynthesis(
  assessments: AggregateFreshnessResult["assessments"]
): string {
  const flagged = assessments.filter(
    (a) => a.status === "stale" || (a.status === "unknown" && a.confidence < 0.5)
  );
  if (flagged.length === 0) return "";
  return [
    "Attention — certaines sources ont une fraîcheur incertaine ou faible :",
    ...flagged.map((a) => `- ${a.title}: ${a.reason}`),
    "Croise les sources et indique les incertitudes si nécessaire.",
  ].join("\n");
}
