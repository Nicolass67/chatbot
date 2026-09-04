import type { RouteDecision } from "@/lib/request-router/types";
import type { SearchResult } from "@/lib/tools/types";
import { resolveEffectiveScope } from "./temporal";
import type { TemporalContext } from "./temporal";

export interface ResearchFlowState {
  required: boolean;
  userGoal: string;
  researchObjective?: string;
  initialSearchDone: boolean;
  webSearchFailures: number;
  webSearchSuccesses: number;
  totalUsableResults: number;
  allSearchesFailed: boolean;
  noUsableWebData: boolean;
}

export interface SynthesisValidationResult {
  canProceed: boolean;
  currentDataVerified: boolean;
  forceHonestResponse: boolean;
  blockReason?: string;
}

export function createResearchFlowStateFromRoute(
  route: RouteDecision,
  userGoal: string
): ResearchFlowState {
  const required =
    route.web.searchType === "research" && route.web.mode === "required";

  return {
    required,
    userGoal,
    researchObjective: route.research.objective,
    initialSearchDone: false,
    webSearchFailures: 0,
    webSearchSuccesses: 0,
    totalUsableResults: 0,
    allSearchesFailed: false,
    noUsableWebData: false,
  };
}

export function markInitialResearchSearchDone(
  state: ResearchFlowState
): ResearchFlowState {
  return { ...state, initialSearchDone: true };
}

export function recordWebSearchOutcome(
  state: ResearchFlowState,
  success: boolean,
  usableResultCount = 0
): ResearchFlowState {
  const failures = state.webSearchFailures + (success ? 0 : 1);
  const successes = state.webSearchSuccesses + (success ? 1 : 0);
  const total = failures + successes;
  const totalUsableResults = state.totalUsableResults + usableResultCount;
  return {
    ...state,
    webSearchFailures: failures,
    webSearchSuccesses: successes,
    totalUsableResults,
    allSearchesFailed: total > 0 && successes === 0,
    noUsableWebData: total >= 2 && totalUsableResults === 0,
  };
}

export function validateBeforeSynthesis(
  state: ResearchFlowState,
  webSearchCount: number
): SynthesisValidationResult {
  if (!state.required) {
    return {
      canProceed: true,
      currentDataVerified: webSearchCount > 0,
      forceHonestResponse: false,
    };
  }

  if (state.allSearchesFailed || state.noUsableWebData) {
    return {
      canProceed: true,
      currentDataVerified: false,
      forceHonestResponse: true,
    };
  }

  if (webSearchCount === 0) {
    return {
      canProceed: false,
      currentDataVerified: false,
      forceHonestResponse: false,
      blockReason:
        "Recherche approfondie requise — effectue au moins une recherche Web avant de finaliser.",
    };
  }

  return {
    canProceed: true,
    currentDataVerified: state.webSearchSuccesses > 0,
    forceHonestResponse: false,
  };
}

export function formatResearchBlockForDecider(
  state: ResearchFlowState
): string {
  if (!state.required) return "";

  const lines = [
    "=== RECHERCHE APPROFONDIE (OBLIGATOIRE) ===",
    `Recherche initiale : ${state.initialSearchDone ? "effectuée" : "EN ATTENTE"}`,
  ];

  if (state.researchObjective) {
    lines.push(`Objectif de recherche : ${state.researchObjective}`);
  }

  if (state.allSearchesFailed || state.noUsableWebData) {
    lines.push(
      "ATTENTION : les recherches Web n'ont fourni aucune source exploitable. Ne pas inventer de faits."
    );
  }

  lines.push(
    "Règles :",
    "- Appuie-toi uniquement sur les sources Web collectées",
    "- Ne relance pas une requête déjà effectuée (voir observations)",
    "- Indique clairement les limites si une donnée n'est pas vérifiable"
  );

  return lines.join("\n");
}

export function formatResearchContextForSynthesis(
  state: ResearchFlowState
): string {
  if (!state.required) return "";
  const parts = ["Contexte de recherche approfondie :"];
  if (state.researchObjective) {
    parts.push(`- Objectif : ${state.researchObjective}`);
  }
  parts.push(
    "- Synthétise uniquement à partir des sources Web listées ci-dessous.",
    "- Signale explicitement toute donnée non vérifiable."
  );
  return parts.join("\n");
}

export function buildHonestFailureResponse(
  temporal: TemporalContext,
  options?: { detail?: string; webSearchSucceeded?: boolean }
): string {
  const scope = resolveEffectiveScope(temporal);
  const intro = options?.webSearchSucceeded
    ? "Les recherches Web ont trouvé des sources, mais la synthèse n'a pas pu être produire de manière fiable."
    : "J'ai tenté de rechercher des informations à jour sur le Web, mais les recherches n'ont pas abouti ou n'ont pas fourni de sources fiables.";

  const lines = [
    "## Impossible de confirmer les informations demandées",
    "",
    intro,
    "",
    "Je **ne peux pas** répondre de façon fiable à partir de ma mémoire interne seule, car elle pourrait être obsolète.",
    "",
    `Portée temporelle : **${scope}** (${temporal.clock.currentDate}).`,
  ];

  if (options?.detail) {
    lines.push("", `**Détail technique :** ${options.detail}`);
  }

  if (!options?.webSearchSucceeded) {
    lines.push(
      "",
      "**Que faire :**",
      "- Démarrez **SearXNG** localement : `docker compose -f docker-compose.searxng.yml up -d`",
      "- Vérifiez l'API JSON : `curl \"http://localhost:8080/search?q=test&format=json\"`",
      "- Optionnel : configurez `BRAVE_SEARCH_API_KEY` pour le mode `WEB_SEARCH_PROVIDER=auto`",
      "- Réessayez dans quelques instants",
      "- Consultez directement les sources pertinentes pour votre sujet"
    );
  } else {
    lines.push(
      "",
      "**Que faire :**",
      "- Vérifiez que LM Studio est démarré et que le modèle répond",
      "- Consultez les sources listées ci-dessous",
      "- Reformulez ou précisez votre demande si nécessaire"
    );
  }

  return lines.join("\n");
}

export function buildSourceBasedFallbackResponse(
  temporal: TemporalContext,
  sources: SearchResult[],
  options?: { llmDetail?: string }
): string {
  const scope = resolveEffectiveScope(temporal);
  const topSources = sources.slice(0, 8);

  const lines = [
    "## Synthèse partielle — sources Web uniquement",
    "",
    "Les recherches Web ont trouvé des sources, mais le modèle n'a pas produit de synthèse finale.",
    "Voici les sources consultées — sans extrapolation au-delà de leur contenu.",
    "",
    `Portée : **${scope}** (${temporal.clock.currentDate})`,
  ];

  if (topSources.length > 0) {
    lines.push("", "### Sources consultées", "");
    for (const [i, s] of topSources.entries()) {
      const snippet = (s.snippet ?? "").slice(0, 200).trim();
      lines.push(`${i + 1}. [${s.title}](${s.url})`);
      if (snippet) lines.push(`   ${snippet}`);
    }
  }

  if (options?.llmDetail) {
    lines.push("", `*Détail technique : ${options.llmDetail}*`);
  }

  return lines.join("\n");
}

export function logAgentHeader(scope: string): void {
  if (process.env.NODE_ENV === "production") return;
  console.log(`[AGENT]\nTemporal scope: ${scope.toUpperCase()}`);
}

export function logResearchQuery(query: string): void {
  if (process.env.NODE_ENV === "production") return;
  console.log(`[RESEARCH]\nQuery: ${query}`);
}

export function logFinalSummary(info: {
  sourcesUsed: number;
  currentDataVerified: boolean;
  webSearchCount: number;
}): void {
  if (process.env.NODE_ENV === "production") return;
  console.log(
    [
      "[FINAL]",
      `Sources used: ${info.sourcesUsed}`,
      `Web searches: ${info.webSearchCount}`,
      `Data verified: ${info.currentDataVerified}`,
    ].join("\n")
  );
}

export function logSearchDedup(originalQuery: string, cachedQuery: string): void {
  if (process.env.NODE_ENV === "production") return;
  console.log(
    `[SEARCH DEDUP]\nSkipped redundant query: "${originalQuery}"\nReusing: "${cachedQuery}"`
  );
}
