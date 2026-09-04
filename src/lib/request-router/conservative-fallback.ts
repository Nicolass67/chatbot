import type { ObjectiveContext, SemanticClassification } from "./types";

const FALLBACK_CONFIDENCE = 0.55;
const HIGH_CONFIDENCE = 0.9;

function temporalScopeNeedsWeb(
  scope: ObjectiveContext["temporal"]["scope"]
): boolean {
  return scope === "current" || scope === "recent" || scope === "future";
}

/**
 * Fallback quand le classifieur LLM est indisponible.
 * Aucune détection d'outil par mots-clés : uniquement settings, longueur, et portée temporelle déjà analysée.
 */
export function conservativeFallback(
  objective: ObjectiveContext
): SemanticClassification {
  if (!objective.webSearchEnabled) {
    return {
      knowledge: "unknown",
      web: { mode: "none", searchType: "none" },
      execution: "direct",
      vision: { required: false },
      tools: { allowToolCalling: false },
      confidence: HIGH_CONFIDENCE,
      reason: "Recherche Web désactivée.",
    };
  }

  if (objective.trimmedMessage.length < 3) {
    return {
      knowledge: "static",
      web: { mode: "none", searchType: "none" },
      execution: "direct",
      vision: { required: false },
      tools: { allowToolCalling: false },
      confidence: HIGH_CONFIDENCE,
      reason: "Message trop court.",
    };
  }

  if (objective.temporal.scope === "historical") {
    return {
      knowledge: "static",
      web: { mode: "none", searchType: "none" },
      execution: "direct",
      vision: { required: false },
      tools: { allowToolCalling: false },
      confidence: HIGH_CONFIDENCE,
      reason: "Demande historique explicite.",
    };
  }

  if (temporalScopeNeedsWeb(objective.temporal.scope)) {
    return {
      knowledge: "current",
      web: { mode: "required", searchType: "single" },
      execution: "tool",
      vision: { required: false },
      tools: { allowToolCalling: true },
      confidence: FALLBACK_CONFIDENCE,
      reason: "Demande sensible au temps — recherche Web requise.",
    };
  }

  // Sans LLM : ne pas inventer d'outil via lexique — réponse directe.
  return {
    knowledge: "static",
    web: { mode: "none", searchType: "none" },
    execution: "direct",
    vision: { required: false },
    tools: { allowToolCalling: false },
    confidence: 0.78,
    reason: "Classifieur indisponible — aucun outil déclenché par défaut.",
  };
}
