import type { FastPathResult, ObjectiveContext } from "./types";

const FAST_PATH_CONFIDENCE = 0.97;

/**
 * Fast path — uniquement cas objectivement déterministes (settings).
 * Aucune détection lexicale d'intent / outil.
 */
export function tryFastPath(objective: ObjectiveContext): FastPathResult {
  if (!objective.webSearchEnabled) {
    return {
      hit: true,
      classification: {
        knowledge: "unknown",
        web: { mode: "none", searchType: "none" },
        execution: "direct",
        vision: { required: false },
        tools: { allowToolCalling: false },
        confidence: FAST_PATH_CONFIDENCE,
        reason: "Recherche Web désactivée par l'utilisateur.",
      },
      confidence: FAST_PATH_CONFIDENCE,
      reason: "Recherche Web désactivée par l'utilisateur.",
    };
  }

  if (objective.trimmedMessage.length < 3) {
    return {
      hit: true,
      classification: {
        knowledge: "static",
        web: { mode: "none", searchType: "none" },
        execution: "direct",
        vision: { required: false },
        tools: { allowToolCalling: false },
        confidence: FAST_PATH_CONFIDENCE,
        reason: "Message trop court pour une tâche.",
      },
      confidence: FAST_PATH_CONFIDENCE,
      reason: "Message trop court pour une tâche.",
    };
  }

  return { hit: false };
}
