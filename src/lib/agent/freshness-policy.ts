import type { RouteDecision } from "@/lib/request-router/types";
import type { SearchResult } from "@/lib/tools/types";
import {
  assessSearchResultsFreshness,
  type AggregateFreshnessResult,
} from "@/lib/tools/web-search/search-result-freshness";
import type { ResearchFlowState } from "./research-flow";
import { resolveEffectiveScope } from "./temporal";

export type FreshnessStatus =
  | "not_required"
  | "required"
  | "verified"
  | "failed";

export interface FreshnessState {
  status: FreshnessStatus;
  requiresFreshWebData: boolean;
  requiresResearchFlow: boolean;
  webSearchEnabled: boolean;
  webSearchAttempted: boolean;
  usableWebResults: number;
  freshSourceCount: number;
  blockReason?: string;
}

export function createFreshnessStateFromRoute(
  route: RouteDecision,
  webSearchEnabled: boolean
): FreshnessState {
  // mode required (dont forcé par toggle Web UI) ⇒ recherche obligatoire,
  // indépendamment du label knowledge (static/current/unknown).
  const requiresFreshWebData = route.web.mode === "required";
  const requiresResearchFlow =
    route.web.searchType === "research" && route.web.mode === "required";

  if (!requiresFreshWebData) {
    return {
      status: "not_required",
      requiresFreshWebData: false,
      requiresResearchFlow,
      webSearchEnabled,
      webSearchAttempted: false,
      usableWebResults: 0,
      freshSourceCount: 0,
    };
  }

  if (!webSearchEnabled) {
    return {
      status: "failed",
      requiresFreshWebData: true,
      requiresResearchFlow,
      webSearchEnabled: false,
      webSearchAttempted: false,
      usableWebResults: 0,
      freshSourceCount: 0,
      blockReason:
        "Recherche Web désactivée — impossible de vérifier les informations actuelles.",
    };
  }

  return {
    status: "required",
    requiresFreshWebData: true,
    requiresResearchFlow,
    webSearchEnabled: true,
    webSearchAttempted: false,
    usableWebResults: 0,
    freshSourceCount: 0,
  };
}

function buildFreshnessContext(route: RouteDecision, fetchedAt = new Date()) {
  const scope = resolveEffectiveScope(route.temporal);
  return {
    fetchedAt,
    temporalScope: scope,
    referenceYear: route.temporal.referenceYear,
    currentYear: route.temporal.clock.currentYear,
  };
}

export function updateFreshnessAfterWebSearch(
  state: FreshnessState,
  params: {
    success: boolean;
    usableResultCount: number;
    sources: SearchResult[];
    route: RouteDecision;
    researchState?: ResearchFlowState;
  }
): FreshnessState {
  if (!state.requiresFreshWebData) return state;

  const usableWebResults =
    state.usableWebResults + Math.max(0, params.usableResultCount);
  const aggregate = assessSearchResultsFreshness(
    params.sources,
    buildFreshnessContext(params.route)
  );

  const next: FreshnessState = {
    ...state,
    webSearchAttempted: true,
    usableWebResults,
    freshSourceCount: Math.max(state.freshSourceCount, aggregate.freshCount),
  };

  if (!params.success) {
    return { ...next, status: "required" };
  }

  if (usableWebResults === 0) {
    return {
      ...next,
      status: "required",
      blockReason: "Recherches Web sans résultat exploitable.",
    };
  }

  if (!aggregate.sufficientForCurrentKnowledge) {
    return {
      ...next,
      status: "required",
      blockReason:
        aggregate.blockReason ??
        "Sources Web insuffisantes pour la demande actuelle.",
    };
  }

  return { ...next, status: "verified", blockReason: undefined };
}

export function markFreshnessFailed(
  state: FreshnessState,
  reason: string
): FreshnessState {
  if (!state.requiresFreshWebData) return state;
  return {
    ...state,
    status: "failed",
    blockReason: reason,
  };
}

export interface FreshnessSynthesisGate {
  allowLlmSynthesis: boolean;
  forceHonestResponse: boolean;
  status: FreshnessStatus;
  blockReason?: string;
}

export function evaluateFreshnessForSynthesis(
  state: FreshnessState,
  params: {
    route: RouteDecision;
    researchState: ResearchFlowState;
    webSearchCount: number;
    collectedSources: SearchResult[];
    fetchedAt?: Date;
  }
): FreshnessSynthesisGate {
  if (!state.requiresFreshWebData) {
    return {
      allowLlmSynthesis: true,
      forceHonestResponse: false,
      status: "not_required",
    };
  }

  if (state.status === "failed") {
    return {
      allowLlmSynthesis: false,
      forceHonestResponse: true,
      status: "failed",
      blockReason:
        state.blockReason ??
        "Impossible de vérifier les informations actuelles.",
    };
  }

  if (!state.webSearchEnabled) {
    return {
      allowLlmSynthesis: false,
      forceHonestResponse: true,
      status: "failed",
      blockReason:
        "Recherche Web désactivée — impossible de vérifier les informations actuelles.",
    };
  }

  if (params.webSearchCount === 0 || !state.webSearchAttempted) {
    return {
      allowLlmSynthesis: false,
      forceHonestResponse: true,
      status: "failed",
      blockReason:
        "Aucune recherche Web effectuée pour une demande nécessitant des données actuelles.",
    };
  }

  if (state.usableWebResults === 0 || params.collectedSources.length === 0) {
    return {
      allowLlmSynthesis: false,
      forceHonestResponse: true,
      status: "failed",
      blockReason:
        "Aucune source Web exploitable — impossible de produire une réponse fiable.",
    };
  }

  if (
    params.researchState.allSearchesFailed ||
    params.researchState.noUsableWebData
  ) {
    return {
      allowLlmSynthesis: false,
      forceHonestResponse: true,
      status: "failed",
      blockReason:
        "Les recherches Web n'ont pas fourni de sources fiables.",
    };
  }

  const aggregate: AggregateFreshnessResult = assessSearchResultsFreshness(
    params.collectedSources,
    buildFreshnessContext(params.route, params.fetchedAt ?? new Date())
  );

  if (!aggregate.sufficientForCurrentKnowledge) {
    return {
      allowLlmSynthesis: false,
      forceHonestResponse: true,
      status: "failed",
      blockReason:
        aggregate.blockReason ??
        "Sources Web insuffisantes pour confirmer les informations demandées.",
    };
  }

  if (state.status !== "verified") {
    return {
      allowLlmSynthesis: false,
      forceHonestResponse: true,
      status: "failed",
      blockReason:
        state.blockReason ??
        "Données Web actuelles non vérifiées par l'orchestrateur.",
    };
  }

  return {
    allowLlmSynthesis: true,
    forceHonestResponse: false,
    status: "verified",
  };
}

export function formatFreshnessBlock(state: FreshnessState): string {
  return [
    `Freshness status: ${state.status}`,
    `Requires fresh Web data: ${state.requiresFreshWebData}`,
    `Research flow: ${state.requiresResearchFlow}`,
    `Web search attempted: ${state.webSearchAttempted}`,
    `Usable Web results: ${state.usableWebResults}`,
    `Fresh sources: ${state.freshSourceCount}`,
    state.blockReason ? `Block reason: ${state.blockReason}` : null,
  ]
    .filter(Boolean)
    .join("\n");
}

/** @deprecated Alias — utiliser createFreshnessStateFromRoute */
export const createFreshnessState = createFreshnessStateFromRoute;

/** @deprecated Supprimé — consommer RouteDecision */
export function requiresFreshWebData(): boolean {
  throw new Error(
    "requiresFreshWebData(message) est supprimé — utiliser RouteDecision.web.mode"
  );
}
