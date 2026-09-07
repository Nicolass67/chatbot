/**
 * Follow-up conversationnel → intention Web résolue jusqu'au routeur/tools.
 * Pas de hardcode métier (prix/CPU…) : canal Web + anaphore uniquement.
 *
 * Garde-fou : « rechercher / recherches » sans marqueur fichier local ≠ file_search.
 * Canal UI (toolChannel) = source de vérité : ne jamais forcer web↔files↔email
 * contre le canal explicitement choisi dans le composer.
 */

import {
  groundSearchQueryWithContext,
  isFollowUpTurn,
} from "@/lib/context/conversation-continuity";
import type { ToolChannel } from "@/lib/agent/tool-channel";
import type { RouteDecision } from "@/lib/request-router/types";

/** Inclut conjugaisons FR courantes : recherches, cherches, etc. */
const WEB_CHANNEL_RE =
  /\b(internet|web|en\s+ligne|online|google|recherches?|recherche(?:r|z)?|cherches?|cherche(?:r|z)?|search|vérifie(?:r|z)?|verifie(?:r|z)?|lookup|trouv(?:e|ez|er)\s+(?:moi\s+)?(?:sur|via))\b/i;

const EXTERNAL_VERIFY_RE =
  /\b(actualis(?:e|er|ez)|à\s+jour|au\s+jour\s+d['']hui|maintenant|live|temps\s+réel)\b/i;

/** Indices explicites de documents / FS locaux — seuls motifs pour files.intent. */
const LOCAL_FILES_RE =
  /\b(fichier|fichiers|dossier|dossiers|pdf|document|documents|facture|factures|contrat|contrats|pi[eè]ce\s+jointe|pi[eè]ces\s+jointes|chemin\s+local|sur\s+(?:mon|le)\s+(?:disque|pc|ordinateur)|dans\s+mes\s+fichiers|téléchargements?|downloads?|pathguard)\b/i;

export function hasWebChannelIntent(message: string): boolean {
  const t = message.trim();
  if (!t) return false;
  return WEB_CHANNEL_RE.test(t) || EXTERNAL_VERIFY_RE.test(t);
}

export function hasExplicitLocalFilesIntent(message: string): boolean {
  return LOCAL_FILES_RE.test(message.trim());
}

/**
 * Si l'utilisateur demande clairement le Web / une info externe et ne parle pas
 * de fichiers locaux, retire files.* pour éviter file_search à la place de web_search.
 * No-op si le canal UI files/email est forcé.
 */
export function clearMisroutedFilesIntent(
  route: RouteDecision,
  userMessage: string,
  toolChannel?: ToolChannel
): RouteDecision {
  if (toolChannel === "files" || toolChannel === "email") return route;
  if (!route.web.enabled) return route;
  if (route.files.intent === "none") return route;
  if (hasExplicitLocalFilesIntent(userMessage)) return route;

  const preferWeb =
    hasWebChannelIntent(userMessage) ||
    route.web.mode === "required" ||
    route.web.mode === "optional";

  if (!preferWeb) return route;

  return {
    ...route,
    files: {
      ...route.files,
      wouldBeUseful: false,
      intent: "none",
      suggestedTools: [],
      searchQuery: undefined,
      reason: `${route.files.reason} | files retiré (canal web / pas de marqueur local)`,
    },
    tools: {
      ...route.tools,
      candidates: route.tools.candidates.filter((c) => !c.startsWith("file_")),
    },
  };
}

/**
 * Réécrit file_search → web_search quand le message est clairement une recherche externe.
 * INTERDIT si toolChannel = files|email (canal UI = source de vérité).
 */
export function rewriteMisroutedFileSearchCalls<
  T extends { tool: string; input: Record<string, unknown> },
>(calls: T[], userMessage: string, toolChannel?: ToolChannel): T[] {
  if (toolChannel === "files" || toolChannel === "email") return calls;
  if (!hasWebChannelIntent(userMessage)) return calls;
  if (hasExplicitLocalFilesIntent(userMessage)) return calls;

  return calls.map((call) => {
    if (call.tool !== "file_search" && call.tool !== "file_list") {
      return call;
    }
    const query =
      typeof call.input.query === "string" && call.input.query.trim()
        ? call.input.query.trim()
        : userMessage.trim().slice(0, 200);
    return {
      ...call,
      tool: "web_search",
      input: { query },
    };
  });
}

export function resolveConversationalWebRoute(params: {
  route: RouteDecision;
  userMessage: string;
  priorUserMessages: string[];
  /** Derniers tours assistant (entités déjà citées pour ancrer les follow-ups). */
  recentAssistantExcerpts?: string[];
  priorWebUsed?: boolean;
  /** Canal composer UI — source de vérité ; ne pas reclasser Chat/Mail/Files. */
  toolChannel?: ToolChannel;
  /** Signal LLM optionnel (même modèle) : follow-up sémantique ambigu. */
  llmFollowUp?: boolean;
}): RouteDecision {
  const channel = params.toolChannel;

  // Canal UI files/email : ne jamais forcer le Web ni retirer files/email.
  if (channel === "files" || channel === "email") {
    return params.route;
  }

  const priors = params.priorUserMessages.map((m) => m.trim()).filter(Boolean);
  const assistantExcerpts = (params.recentAssistantExcerpts ?? [])
    .map((m) => m.trim())
    .filter(Boolean);
  let route = clearMisroutedFilesIntent(params.route, params.userMessage, channel);

  if (priors.length === 0 && assistantExcerpts.length === 0) {
    if (
      route.web.enabled &&
      hasWebChannelIntent(params.userMessage) &&
      !hasExplicitLocalFilesIntent(params.userMessage) &&
      route.web.mode === "none"
    ) {
      const query =
        route.web.searchQuery?.trim() || params.userMessage.trim();
      return {
        ...route,
        web: {
          ...route.web,
          mode: "required",
          mandatory: true,
          wouldBeUseful: true,
          searchType:
            route.web.searchType === "none" ? "single" : route.web.searchType,
          searchQuery: query,
          reason: `${route.web.reason} | canal web explicite`,
        },
        tools: {
          ...route.tools,
          allowToolCalling: true,
          candidates: [
            ...new Set([...route.tools.candidates, "web_search"]),
          ],
        },
      };
    }
    return route;
  }

  const followUp =
    isFollowUpTurn(params.userMessage, true) || params.llmFollowUp === true;
  const webIntent = hasWebChannelIntent(params.userMessage);
  const forceWeb =
    route.web.enabled &&
    followUp &&
    (webIntent ||
      (params.priorWebUsed === true &&
        isEllipticalFollowUp(params.userMessage)));

  if (!forceWeb) {
    if (!route.web.searchQuery) return route;
    return {
      ...route,
      web: {
        ...route.web,
        searchQuery: groundSearchQueryWithContext({
          query: route.web.searchQuery,
          recentUserMessages: priors,
          recentAssistantExcerpts: assistantExcerpts,
        }),
      },
    };
  }

  const base = route.web.searchQuery?.trim() || params.userMessage.trim();
  const grounded = groundSearchQueryWithContext({
    query: base,
    recentUserMessages: priors,
    recentAssistantExcerpts: assistantExcerpts,
    force: true,
  });

  const searchType =
    route.web.searchType === "none" ? "single" : route.web.searchType;

  route = {
    ...route,
    web: {
      ...route.web,
      mode: "required",
      mandatory: true,
      wouldBeUseful: true,
      searchType,
      searchQuery: grounded,
      reason: `${route.web.reason} | follow-up web ancré`,
    },
    tools: {
      ...route.tools,
      allowToolCalling: true,
      candidates: [
        ...new Set(
          [...route.tools.candidates, "web_search"].filter(
            (c) => !c.startsWith("file_")
          )
        ),
      ],
    },
  };

  return clearMisroutedFilesIntent(route, params.userMessage, channel);
}

function isEllipticalFollowUp(message: string): boolean {
  const words = message.trim().split(/\s+/).filter(Boolean);
  if (words.length <= 8) return true;
  if (
    /\b(ça|cela|ceux|celles|il|elle|lui|eux|elles|leur|leurs|en|y|idem|pareil|ceux[- ]là|mentionné|mentionnée|avant|précédemment|qu['’]il|qu['’]elle)\b/i.test(
      message
    )
  ) {
    return true;
  }
  return (
    /\b(entre\s+\d+|\d+\s*(€|euros?)|budget|prix|co[uû]te)\b/i.test(message) &&
    words.length <= 18
  );
}
