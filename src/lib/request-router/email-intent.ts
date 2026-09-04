import type { EmailIntent, RouteDecision } from "./types";

export {
  EMAIL_INTENT_TOOL_MAP,
  emailIntentToTools,
} from "./email-intent-tools";

import { emailIntentToTools } from "./email-intent-tools";

export function resolveEmailRouteBlock(params: {
  emailEnabled: boolean;
  emailConnected: boolean;
  intent: EmailIntent;
  searchQuery?: string;
  reason?: string;
}): RouteDecision["email"] {
  const { emailEnabled, emailConnected, intent, searchQuery } = params;
  const suggestedTools = emailEnabled ? emailIntentToTools(intent) : [];
  const wouldBeUseful = emailEnabled && intent !== "none";

  return {
    enabled: emailEnabled && emailConnected,
    wouldBeUseful,
    intent,
    suggestedTools,
    searchQuery: searchQuery?.trim() || undefined,
    reason:
      params.reason ??
      (intent === "none"
        ? "Pas de tâche email détectée."
        : `Intent email sémantique: ${intent}.`),
  };
}

export const EMPTY_EMAIL_ROUTE: RouteDecision["email"] = {
  enabled: false,
  wouldBeUseful: false,
  intent: "none",
  suggestedTools: [],
  reason: "Pas de tâche email détectée.",
};

export const EMPTY_FILES_ROUTE: RouteDecision["files"] = {
  enabled: false,
  wouldBeUseful: false,
  intent: "none",
  suggestedTools: [],
  reason: "Pas de tâche fichiers.",
};

export function resolveEmailIntent(
  classification: import("./types").SemanticClassification
): EmailIntent {
  return classification.email?.intent ?? "none";
}
