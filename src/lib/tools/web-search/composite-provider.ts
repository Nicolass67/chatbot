import type {
  WebSearchOptions,
  WebSearchProvider,
  WebSearchProviderResult,
  WebSearchStatus,
} from "./web-search-types";
import { isWebSearchFailureStatus } from "./web-search-types";

function hasUsableResults(result: WebSearchProviderResult): boolean {
  return result.status === "success" && result.results.length > 0;
}

function describeOutcome(result: WebSearchProviderResult): string {
  if (result.status === "no_results") {
    return `${result.provider}: aucune source trouvée`;
  }
  return `${result.provider}: ${result.status}${result.error ? ` (${result.error})` : ""}`;
}

export class CompositeWebSearchProvider implements WebSearchProvider {
  readonly name = "auto";

  constructor(private readonly providers: WebSearchProvider[]) {
    if (providers.length === 0) {
      throw new Error("Aucun moteur de recherche Web configuré");
    }
  }

  async search(
    query: string,
    options: WebSearchOptions
  ): Promise<WebSearchProviderResult> {
    const settled = await Promise.all(
      this.providers.map(async (provider) => {
        try {
          const result = await provider.search(query, options);
          return { provider: provider.name, result, error: null as string | null };
        } catch (error) {
          return {
            provider: provider.name,
            result: null as WebSearchProviderResult | null,
            error: error instanceof Error ? error.message : String(error),
          };
        }
      })
    );

    const notes: string[] = [];
    let lastResult: WebSearchProviderResult | null = null;

    for (const provider of this.providers) {
      const entry = settled.find((s) => s.provider === provider.name);
      if (!entry) continue;

      if (entry.error) {
        notes.push(`${provider.name}: ${entry.error}`);
        continue;
      }

      if (!entry.result) continue;

      lastResult = entry.result;
      if (hasUsableResults(entry.result)) {
        return entry.result;
      }

      notes.push(describeOutcome(entry.result));

      if (isWebSearchFailureStatus(entry.result.status)) {
        continue;
      }
    }

    if (lastResult && lastResult.status === "no_results") {
      return lastResult;
    }

    const status: WebSearchStatus = lastResult?.status ?? "provider_error";
    throw new CompositeWebSearchError(notes, status, lastResult?.provider ?? "auto");
  }
}

export class CompositeWebSearchError extends Error {
  constructor(
    public readonly attempts: string[],
    public readonly status: WebSearchStatus,
    public readonly lastProvider: string
  ) {
    super(
      `Recherche Web indisponible — ${attempts.join(" | ")}. ` +
        "Vérifiez que SearXNG est démarré (docker compose -f docker-compose.searxng.yml up -d) " +
        "ou configurez BRAVE_SEARCH_API_KEY en secours."
    );
    this.name = "CompositeWebSearchError";
  }
}
