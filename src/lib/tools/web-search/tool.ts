import { deepenSearchResults } from "@/lib/tools/web-search/fetch-page";
import {
  formatWebSourcesForContext,
  isSnippetInsufficient,
  searchResultsToWebSources,
} from "@/lib/context/web-provenance";
import { z } from "zod";
import type { Tool } from "../types";
import { logWebSearchDebug } from "./debug";
import { createWebSearchProvider } from "./provider-factory";
import { CompositeWebSearchError } from "./composite-provider";
import {
  isWebSearchFailureStatus,
  WebSearchError,
} from "./web-search-types";
import type { WebSearchProviderResult } from "./web-search-types";

export { isWebSearchFailureStatus, WebSearchError } from "./web-search-types";

const webSearchInputSchema = z.object({
  query: z.string().min(1).describe("Requête de recherche web"),
  temporalScope: z.string().optional(),
  referenceDate: z.string().optional(),
  freshness: z.enum(["high", "medium", "low"]).optional(),
});

export type WebSearchInput = z.infer<typeof webSearchInputSchema>;

function countUsableResults(
  results: Array<{ title: string; url: string }>
): number {
  return results.filter(
    (r) => r.title.trim().length > 0 && r.url.startsWith("http")
  ).length;
}

function toToolOutput(
  query: string,
  result: WebSearchProviderResult
): import("../types").WebSearchOutput {
  return {
    query,
    results: result.results,
    status: result.status,
    provider: result.provider,
    error: result.error,
  };
}

export const webSearchTool: Tool<
  WebSearchInput,
  import("../types").WebSearchOutput
> = {
  name: "web_search",
  description:
    "Recherche des informations actuelles sur Internet (adresses, lieux, restaurants, actualités, prix, faits externes). À utiliser dès que l'utilisateur demande de rechercher / vérifier en ligne — pas file_search.",
  inputSchema: webSearchInputSchema,
  preferredRuntime: "either",
  async execute(input, ctx) {
    const maxResults = ctx.settings.webSearchMaxResults;
    const timeoutMs = ctx.settings.webSearchTimeoutMs;

    try {
      const provider = createWebSearchProvider();
      const result = await provider.search(input.query, {
        maxResults,
        timeoutMs,
        signal: ctx.signal,
      });

      const usableResultCount = countUsableResults(result.results);

      logWebSearchDebug({
        query: input.query,
        status: result.status,
        provider: result.provider,
        httpStatus: result.diagnostics.httpStatus,
        resultCount: result.diagnostics.rawCount,
        parsedResultCount: result.diagnostics.parsedCount,
        usableResultCount,
        error: result.error,
      });

      if (isWebSearchFailureStatus(result.status)) {
        throw new WebSearchError(
          result.error ?? `Recherche Web échouée (${result.status})`,
          result.status,
          result.provider,
          result.diagnostics
        );
      }

      const pageContents = await deepenSearchResults({
        query: input.query,
        results: result.results.map((r) => ({
          title: r.title,
          url: r.url,
          snippet: r.snippet ?? "",
        })),
        maxPages: 2,
        signal: ctx.signal,
        snippetInsufficient: isSnippetInsufficient,
      });
      const output = toToolOutput(input.query, result);
      if (Object.keys(pageContents).length > 0) {
        output.pageContents = pageContents;
        output.groundedContext = formatWebSourcesForContext(
          searchResultsToWebSources(input.query, result.results, {
            provider: result.provider,
            pageContents,
          })
        );
      }
      return output;
    } catch (error) {
      if (error instanceof WebSearchError) {
        throw error;
      }

      if (error instanceof CompositeWebSearchError) {
        logWebSearchDebug({
          query: input.query,
          status: error.status,
          provider: error.lastProvider,
          resultCount: 0,
          parsedResultCount: 0,
          usableResultCount: 0,
          error: error.message,
        });
        throw new WebSearchError(
          error.message,
          error.status,
          error.lastProvider
        );
      }

      const errMsg = error instanceof Error ? error.message : String(error);
      logWebSearchDebug({
        query: input.query,
        status: "provider_error",
        provider: "unknown",
        resultCount: 0,
        parsedResultCount: 0,
        usableResultCount: 0,
        error: errMsg,
      });
      throw error;
    }
  },
};
