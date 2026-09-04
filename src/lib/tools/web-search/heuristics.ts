import { routeRequestSync, routeToWebSearchIntent } from "@/lib/request-router";
import type { RouteDecision } from "@/lib/request-router/types";
import type { SearchResult } from "../types";
import { dedupeAndCapSources } from "./source-dedupe";

export interface WebSearchIntent {
  settingEnabled: boolean;
  queryUseful: boolean;
  allowed: boolean;
  autoSearch: boolean;
  searchQuery: string;
}

/**
 * @deprecated Ne plus utiliser pour décider d'un outil — le routeur LLM décide.
 * Conservé pour compat tests / signatures ; toujours false.
 */
export function shouldSkipWebSearch(_message: string): boolean {
  return false;
}

/**
 * @deprecated Ne plus utiliser pour déclencher une recherche web — le classifieur sémantique décide.
 */
export function shouldAutoWebSearch(_message: string): boolean {
  return false;
}

/** Renvoie le message tel quel : pas de strip lexical de préfixes. */
export function extractWebSearchQuery(message: string): string {
  return message.trim();
}

export function buildWebSearchQuery(params: {
  userMessage: string;
  route?: Pick<RouteDecision["web"], "searchQuery">;
  recentContext?: string;
}): string {
  const routeQuery = params.route?.searchQuery?.trim();
  if (routeQuery) return routeQuery;
  return params.userMessage.trim();
}

export function isWebSearchUsefulForQuery(
  message: string,
  options?: {
    webSearchEnabled?: boolean;
    chatMode?: "chat" | "agent";
  }
): boolean {
  const trimmed = message.trim();
  if (!trimmed) return false;

  const route = routeRequestSync({
    message: trimmed,
    webSearchEnabled: options?.webSearchEnabled ?? true,
    chatMode: options?.chatMode ?? "chat",
    imageCount: 0,
    attachmentCount: 0,
    modelId: "",
  });

  return route.web.mode !== "none";
}

export function resolveWebSearchIntent(
  message: string,
  webSearchEnabled: boolean
): WebSearchIntent {
  const route = routeRequestSync({
    message,
    webSearchEnabled,
    chatMode: "chat",
    imageCount: 0,
    attachmentCount: 0,
    modelId: "",
  });
  return routeToWebSearchIntent(route);
}

export function capSourcesForSynthesis(
  results: SearchResult[],
  max = 12
): SearchResult[] {
  return dedupeAndCapSources(results, max);
}

export function formatSearchResultsBlock(
  query: string,
  results: Array<{ title: string; url: string; snippet: string }>,
  maxSnippetLen = 200
): string {
  if (results.length === 0) {
    return `<web_search_results query="${query}">\nAucun résultat trouvé.\n</web_search_results>`;
  }
  const body = results
    .map((r, i) => {
      const snippet = (r.snippet ?? "").slice(0, maxSnippetLen).trim();
      return `[${i + 1}] ${r.title}\nURL: ${r.url}\n${snippet}`.trim();
    })
    .join("\n\n");
  return `<web_search_results query="${query}">\n${body}\n</web_search_results>`;
}
