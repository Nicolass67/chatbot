import { getRuntimeClock, type RuntimeClock } from "@/lib/runtime/clock";
import {
  assessSearchResultsFreshness,
  formatFreshnessNotesForSynthesis as formatGenericFreshnessNotes,
} from "@/lib/tools/web-search/search-result-freshness";
import type { SearchResult } from "@/lib/tools/types";

export const temporalScopeSchema = [
  "current",
  "recent",
  "historical",
  "future",
  "unspecified",
] as const;

export type TemporalScope = (typeof temporalScopeSchema)[number];

export interface TemporalContext {
  clock: RuntimeClock;
  scope: TemporalScope;
  referenceYear: number | null;
  userIntent: string;
  isTimeSensitive: boolean;
  userMentionedYears: number[];
}

export interface WebSearchTemporalInput {
  query: string;
  temporalScope?: TemporalScope;
  referenceDate?: string;
}

export interface QueryValidationResult {
  valid: boolean;
  query: string;
  corrected: boolean;
  reason?: string;
}

const CURRENT_INDICATORS = [
  /\bactuellement\b/i,
  /\bactuel(le|s)?\b/i,
  /\baujourd['']hui\b/i,
  /\ben ce moment\b/i,
  /\bmaintenant\b/i,
  /\bcette ann[eé]e\b/i,
  /\bce mois-ci\b/i,
  /\bcette semaine\b/i,
];

const RECENT_INDICATORS = [
  /\bderni[eè]r(e|es|s)\b/i,
  /\br[eé]cemment\b/i,
  /\bderniers?\s+mois\b/i,
  /\bderni[eè]res?\s+semaines?\b/i,
  /\bderni[eè]res?\s+donn[eé]es\b/i,
  /\bderni[eè]rs?\s+r[eé]sultats\b/i,
];

const FUTURE_INDICATORS = [
  /\bdemain\b/i,
  /\btomorrow\b/i,
  /\bl['']ann[eé]e prochaine\b/i,
  /\bprochaine ann[eé]e\b/i,
  /\bdans le futur\b/i,
  /\bprochainement\b/i,
];

export function extractYears(text: string): number[] {
  const matches = text.match(/\b(19|20)\d{2}\b/g);
  if (!matches) return [];
  return [...new Set(matches.map(Number))].sort();
}

/** Analyse temporelle structurelle — sans vocabulaire métier. */
export function analyzeTemporalContext(
  userGoal: string,
  clock: RuntimeClock = getRuntimeClock()
): TemporalContext {
  const userMentionedYears = extractYears(userGoal);

  if (FUTURE_INDICATORS.some((p) => p.test(userGoal))) {
    return {
      clock,
      scope: "future",
      referenceYear: clock.currentYear + 1,
      userIntent: "Informations futures",
      isTimeSensitive: true,
      userMentionedYears,
    };
  }

  if (userMentionedYears.length > 0) {
    const explicitHistorical =
      /\b(en|de|pour|during|depuis|vers)\s+(19|20)\d{2}\b/i.test(userGoal) ||
      /\b(19|20)\d{2}\s*[?]/.test(userGoal) ||
      userMentionedYears.some((y) => y < clock.currentYear - 1);

    if (explicitHistorical || userMentionedYears.every((y) => y < clock.currentYear)) {
      const refYear = userMentionedYears[userMentionedYears.length - 1];
      return {
        clock,
        scope: "historical",
        referenceYear: refYear,
        userIntent: `Informations pour l'année ${refYear}`,
        isTimeSensitive: false,
        userMentionedYears,
      };
    }
  }

  if (RECENT_INDICATORS.some((p) => p.test(userGoal))) {
    return {
      clock,
      scope: "recent",
      referenceYear: null,
      userIntent: "Informations récentes",
      isTimeSensitive: true,
      userMentionedYears,
    };
  }

  if (CURRENT_INDICATORS.some((p) => p.test(userGoal))) {
    return {
      clock,
      scope: "current",
      referenceYear: null,
      userIntent: "Informations actuelles",
      isTimeSensitive: true,
      userMentionedYears,
    };
  }

  return {
    clock,
    scope: "unspecified",
    referenceYear: null,
    userIntent: "Portée temporelle non spécifiée",
    isTimeSensitive: false,
    userMentionedYears,
  };
}

export function resolveEffectiveScope(ctx: TemporalContext): TemporalScope {
  if (ctx.scope !== "unspecified") return ctx.scope;
  return "unspecified";
}

function stripHistoricalYears(query: string, yearsToRemove: number[]): string {
  let result = query;
  for (const year of yearsToRemove) {
    result = result.replace(new RegExp(`\\b${year}\\b`, "g"), " ");
  }
  return result.replace(/\s+/g, " ").trim();
}

/** Corrections techniques de requête — sans enrichissement métier. */
export function validateWebSearchQuery(
  rawQuery: string,
  userGoal: string,
  temporal: TemporalContext
): QueryValidationResult {
  const query = rawQuery.trim();
  const queryYears = extractYears(query);
  const userYears = extractYears(userGoal);
  const effectiveScope = resolveEffectiveScope(temporal);
  const { currentYear } = temporal.clock;

  if (effectiveScope === "historical" && temporal.referenceYear) {
    const allowedYears = new Set([temporal.referenceYear, ...userYears]);
    const invalidYears = queryYears.filter((y) => !allowedYears.has(y));
    if (invalidYears.length > 0) {
      const corrected = stripHistoricalYears(query, invalidYears);
      return {
        valid: false,
        query: corrected || query,
        corrected: true,
        reason: `Année(s) ${invalidYears.join(", ")} incohérente(s) avec la portée historique ${temporal.referenceYear}`,
      };
    }
    return { valid: true, query, corrected: false };
  }

  if (effectiveScope === "current" || effectiveScope === "recent") {
    const suspiciousYears = queryYears.filter(
      (y) => y < currentYear && !userYears.includes(y)
    );
    if (suspiciousYears.length > 0) {
      const corrected = stripHistoricalYears(query, suspiciousYears);
      return {
        valid: false,
        query: corrected,
        corrected: true,
        reason: `Année(s) historique(s) ${suspiciousYears.join(", ")} retirée(s) pour une demande actuelle`,
      };
    }
  }

  if (effectiveScope === "future") {
    const pastYears = queryYears.filter((y) => y <= currentYear && !userYears.includes(y));
    if (pastYears.length > 0) {
      const corrected = stripHistoricalYears(query, pastYears);
      return {
        valid: false,
        query: corrected,
        corrected: true,
        reason: `Année(s) passée(s) ${pastYears.join(", ")} retirée(s) pour une demande future`,
      };
    }
  }

  return { valid: true, query, corrected: false };
}

export function buildWebSearchTemporalInput(
  rawQuery: string,
  userGoal: string,
  temporal: TemporalContext
): WebSearchTemporalInput {
  const validation = validateWebSearchQuery(rawQuery, userGoal, temporal);
  const effectiveScope = resolveEffectiveScope(temporal);

  logTemporalSearchDebug({
    userGoal,
    temporalScope: effectiveScope,
    generatedQuery: rawQuery,
    finalQuery: validation.query,
    corrected: validation.corrected,
    reason: validation.reason,
    clock: temporal.clock,
    userIntent: temporal.userIntent,
  });

  return {
    query: validation.query,
    temporalScope: effectiveScope,
    referenceDate: temporal.clock.currentDate,
  };
}

export function formatTemporalContextBlock(temporal: TemporalContext): string {
  const effectiveScope = resolveEffectiveScope(temporal);
  return [
    `Current date: ${temporal.clock.currentDate}`,
    `Current year: ${temporal.clock.currentYear}`,
    `Date actuelle : ${temporal.clock.currentDate} (${temporal.clock.timezone})`,
    `Portée temporelle : ${effectiveScope}`,
    `Intention utilisateur : ${temporal.userIntent}`,
    temporal.referenceYear
      ? `Année de référence : ${temporal.referenceYear}`
      : null,
    temporal.userMentionedYears.length > 0
      ? `Années mentionnées par l'utilisateur : ${temporal.userMentionedYears.join(", ")}`
      : "Aucune année explicitement demandée par l'utilisateur",
    temporal.isTimeSensitive
      ? "Demande sensible au temps : privilégier des sources récentes et vérifier dates de publication/mise à jour."
      : null,
  ]
    .filter(Boolean)
    .join("\n");
}

export function logTemporalSearchDebug(info: {
  userGoal: string;
  temporalScope: TemporalScope;
  userIntent: string;
  generatedQuery: string;
  finalQuery: string;
  corrected: boolean;
  reason?: string;
  clock: RuntimeClock;
}): void {
  if (process.env.NODE_ENV === "production") return;
  console.log(
    [
      "[Agent Temporal]",
      `Current date: ${info.clock.currentDate}`,
      `Temporal scope: ${info.temporalScope}`,
      `User intent: ${info.userIntent}`,
      `Generated search query: ${info.generatedQuery}`,
      info.corrected
        ? `Corrected search query: ${info.finalQuery}${info.reason ? ` (${info.reason})` : ""}`
        : `Final search query: ${info.finalQuery}`,
    ].join("\n")
  );
}

/** @deprecated Utiliser assessSearchResultsFreshness depuis search-result-freshness.ts */
export type FreshnessLevel = "high" | "medium" | "low";

/** @deprecated */
export interface SourceFreshnessNote {
  url: string;
  title: string;
  detectedYears: number[];
  freshness: FreshnessLevel;
  warning?: string;
}

export function assessSourceFreshness(
  results: SearchResult[],
  temporal: TemporalContext
): SourceFreshnessNote[] {
  const aggregate = assessSearchResultsFreshness(results, {
    fetchedAt: new Date(),
    temporalScope: resolveEffectiveScope(temporal),
    referenceYear: temporal.referenceYear,
    currentYear: temporal.clock.currentYear,
  });

  return aggregate.assessments.map((a) => ({
    url: a.url,
    title: a.title,
    detectedYears: extractYears(`${a.title} ${a.reason}`),
    freshness:
      a.status === "fresh" ? "high" : a.status === "stale" ? "low" : "medium",
    warning: a.status === "stale" ? a.reason : undefined,
  }));
}

/** @deprecated Préférer formatFreshnessNotesForSynthesis depuis search-result-freshness */
export function formatFreshnessNotesForSynthesis(
  notes: SourceFreshnessNote[]
): string {
  if (notes.length === 0) return "";
  const mapped = notes.map((n) => ({
    url: n.url,
    title: n.title,
    status:
      n.freshness === "high"
        ? ("fresh" as const)
        : n.freshness === "low"
          ? ("stale" as const)
          : ("unknown" as const),
    confidence: 0.5,
    reason: n.warning ?? "Fraîcheur indéterminée",
    signals: [],
  }));
  return formatGenericFreshnessNotes(mapped);
}
