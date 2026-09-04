import { areQueriesEquivalent } from "./search-dedup";
import type { WebSearchStatus } from "@/lib/tools/types";

export interface WebSearchRecord {
  query: string;
  status: WebSearchStatus;
  usableResultCount: number;
  /** Nouvelles URLs uniques ajoutées (si fourni). */
  uniqueAdded?: number;
  /** Domaines distincts ajoutés cette recherche (si fourni). */
  uniqueDomainsAdded?: number;
  error?: string;
  deduplicated?: boolean;
}

export interface WebSearchStopDecision {
  stop: boolean;
  reason?: string;
  /** sufficient = assez de sources, failure = infra / données inexploitables */
  kind?: "sufficient" | "failure";
}

/** Budget adaptatif — ni 5 figés, ni 100+. */
export type ResearchIntensity = "simple" | "standard" | "complex";

export interface SourceBudget {
  intensity: ResearchIntensity;
  /** Seuil d’arrêt « assez de preuves ». */
  targetMin: number;
  /** Plafond dur collecte / synthèse. */
  hardMax: number;
  /** Nombre max de recherches Web distinctes. */
  maxSearches: number;
  /** maxResults par appel SearXNG. */
  perQueryMaxResults: number;
}

export function resolveSourceBudget(input: {
  searchType?: string | null;
  researchRequired?: boolean;
  webSearchMaxResults?: number;
}): SourceBudget {
  const hint = Math.max(3, Math.min(20, input.webSearchMaxResults ?? 8));
  const type = (input.searchType ?? "").toLowerCase();
  const research =
    input.researchRequired === true ||
    type === "research" ||
    type === "deep";

  if (research) {
    return {
      intensity: "complex",
      targetMin: 12,
      hardMax: Math.min(25, Math.max(18, hint * 3)),
      maxSearches: 4,
      perQueryMaxResults: Math.min(12, Math.max(8, hint)),
    };
  }

  if (type === "single" || type === "quick") {
    return {
      intensity: "simple",
      targetMin: 8,
      hardMax: Math.min(12, Math.max(8, hint * 2)),
      maxSearches: 2,
      perQueryMaxResults: Math.min(10, Math.max(6, hint)),
    };
  }

  return {
    intensity: "standard",
    targetMin: 10,
    hardMax: Math.min(20, Math.max(12, hint * 2)),
    maxSearches: 3,
    perQueryMaxResults: Math.min(10, Math.max(7, hint)),
  };
}

function isInfrastructureFailure(status: WebSearchStatus): boolean {
  return (
    status === "provider_error" ||
    status === "timeout" ||
    status === "blocked"
  );
}

/**
 * Suit les recherches Web et décide quand arrêter la boucle Agent.
 * Budget adaptatif + early-stop qualité (pas un plafond fixe à 5).
 */
export class WebSearchTracker {
  private records: WebSearchRecord[] = [];
  private consecutiveFailures = 0;
  private consecutiveEmpty = 0;
  private totalUsable = 0;
  private uniqueSourceCount = 0;
  private uniqueDomainCount = 0;
  private uniqueQueryCount = 0;
  private budget: SourceBudget;

  constructor(budget?: Partial<SourceBudget> | SourceBudget) {
    this.budget = {
      ...resolveSourceBudget({}),
      ...budget,
    };
  }

  setBudget(budget: SourceBudget): void {
    this.budget = budget;
  }

  get currentBudget(): SourceBudget {
    return this.budget;
  }

  record(entry: WebSearchRecord): void {
    if (entry.deduplicated) return;

    this.records.push(entry);
    this.uniqueQueryCount = this.countUniqueQueries();

    if (isInfrastructureFailure(entry.status)) {
      this.consecutiveFailures++;
      this.consecutiveEmpty = 0;
      return;
    }

    this.consecutiveFailures = 0;

    if (entry.status === "no_results" || entry.usableResultCount === 0) {
      this.consecutiveEmpty++;
      return;
    }

    this.consecutiveEmpty = 0;
    this.totalUsable += entry.usableResultCount;
    const added =
      typeof entry.uniqueAdded === "number"
        ? entry.uniqueAdded
        : entry.usableResultCount;
    this.uniqueSourceCount += Math.max(0, added);
    if (typeof entry.uniqueDomainsAdded === "number") {
      this.uniqueDomainCount += Math.max(0, entry.uniqueDomainsAdded);
    }
  }

  private countUniqueQueries(): number {
    const unique: string[] = [];
    for (const r of this.records) {
      if (unique.some((q) => areQueriesEquivalent(q, r.query))) continue;
      unique.push(r.query);
    }
    return unique.length;
  }

  get stats() {
    return {
      totalSearches: this.records.length,
      uniqueQueries: this.uniqueQueryCount,
      totalUsable: this.totalUsable,
      uniqueSources: this.uniqueSourceCount,
      uniqueDomains: this.uniqueDomainCount,
      consecutiveFailures: this.consecutiveFailures,
      consecutiveEmpty: this.consecutiveEmpty,
      budget: this.budget,
    };
  }

  shouldStopForResearch(): WebSearchStopDecision {
    const { targetMin, hardMax, maxSearches } = this.budget;

    if (this.consecutiveFailures >= 2) {
      const last = this.records[this.records.length - 1];
      const timedOut = last?.status === "timeout";
      return {
        stop: true,
        kind: "failure",
        reason: timedOut
          ? "Délai de recherche Web dépassé — augmentez le timeout dans Paramètres (≥ 25 s pour SearXNG) ou réessayez."
          : "SearXNG indisponible — impossible de vérifier les données actuelles.",
      };
    }

    // Preuves suffisantes + diversité minimale
    if (
      this.uniqueSourceCount >= targetMin &&
      (this.uniqueDomainCount >= 3 || this.uniqueSourceCount >= targetMin + 2)
    ) {
      return {
        stop: true,
        kind: "sufficient",
        reason: "Sources Web suffisantes et diversifiées.",
      };
    }

    // Assez de sources même sans comptage domaines
    if (this.uniqueSourceCount >= Math.min(hardMax, targetMin + 4)) {
      return {
        stop: true,
        kind: "sufficient",
        reason: "Sources Web suffisantes collectées.",
      };
    }

    // Hard cap recherches
    if (this.records.length >= maxSearches) {
      return {
        stop: true,
        kind:
          this.uniqueSourceCount > 0 || this.totalUsable > 0
            ? "sufficient"
            : "failure",
        reason:
          this.uniqueSourceCount > 0 || this.totalUsable > 0
            ? "Limite de recherches Web atteinte — synthèse avec les sources disponibles."
            : "Aucune source Web exploitable après plusieurs recherches.",
      };
    }

    // Cap dur sources
    if (this.uniqueSourceCount >= hardMax) {
      return {
        stop: true,
        kind: "sufficient",
        reason: "Plafond de sources atteint — synthèse.",
      };
    }

    if (this.uniqueQueryCount >= maxSearches && this.totalUsable === 0) {
      return {
        stop: true,
        kind: "failure",
        reason:
          "Aucune source Web exploitable après plusieurs recherches distinctes.",
      };
    }

    if (this.consecutiveEmpty >= 3 && this.totalUsable === 0) {
      return {
        stop: true,
        kind: "failure",
        reason: "Recherches Web successives sans résultat exploitable.",
      };
    }

    return { stop: false };
  }
}
