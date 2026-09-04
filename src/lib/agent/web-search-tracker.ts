import { areQueriesEquivalent } from "./search-dedup";
import type { WebSearchStatus } from "@/lib/tools/types";

export interface WebSearchRecord {
  query: string;
  status: WebSearchStatus;
  usableResultCount: number;
  error?: string;
  deduplicated?: boolean;
}

export interface WebSearchStopDecision {
  stop: boolean;
  reason?: string;
  /** sufficient = assez de sources, failure = infra / données inexploitables */
  kind?: "sufficient" | "failure";
}

function isInfrastructureFailure(status: WebSearchStatus): boolean {
  return (
    status === "provider_error" ||
    status === "timeout" ||
    status === "blocked"
  );
}

/** Suit les recherches Web et décide quand arrêter la boucle Agent. */
export class WebSearchTracker {
  private records: WebSearchRecord[] = [];
  private consecutiveFailures = 0;
  private consecutiveEmpty = 0;
  private totalUsable = 0;
  private uniqueQueryCount = 0;

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
      consecutiveFailures: this.consecutiveFailures,
      consecutiveEmpty: this.consecutiveEmpty,
    };
  }

  shouldStopForResearch(): WebSearchStopDecision {
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

    if (this.totalUsable >= 25) {
      return {
        stop: true,
        kind: "sufficient",
        reason: "Sources Web suffisantes collectées.",
      };
    }

    if (this.uniqueQueryCount >= 4 && this.totalUsable >= 15) {
      return {
        stop: true,
        kind: "sufficient",
        reason: "Sources Web suffisantes après plusieurs recherches.",
      };
    }

    if (this.uniqueQueryCount >= 3 && this.totalUsable === 0) {
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
        reason:
          "Recherches Web successives sans résultat exploitable.",
      };
    }

    return { stop: false };
  }
}
