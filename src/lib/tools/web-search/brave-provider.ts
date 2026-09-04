import { normalizeWebHits } from "./normalize";
import type {
  WebSearchOptions,
  WebSearchProvider,
  WebSearchProviderResult,
} from "./web-search-types";
import { classifyFetchError } from "./web-search-types";

interface BraveWebResult {
  title?: string;
  url?: string;
  description?: string;
  page_age?: string;
}

interface BraveSearchResponse {
  web?: { results?: BraveWebResult[] };
}

export class BraveSearchProvider implements WebSearchProvider {
  readonly name = "brave";

  constructor(private readonly apiKey: string) {}

  async search(
    query: string,
    options: WebSearchOptions
  ): Promise<WebSearchProviderResult> {
    const timeoutController = new AbortController();
    const timeoutId = setTimeout(
      () => timeoutController.abort(),
      options.timeoutMs
    );
    const onAbort = () => timeoutController.abort();
    options.signal.addEventListener("abort", onAbort);

    try {
      const url = new URL("https://api.search.brave.com/res/v1/web/search");
      url.searchParams.set("q", query);
      url.searchParams.set("count", String(options.maxResults));
      url.searchParams.set("search_lang", "fr");
      url.searchParams.set("country", "FR");

      const response = await fetch(url, {
        headers: {
          Accept: "application/json",
          "Accept-Encoding": "gzip",
          "X-Subscription-Token": this.apiKey,
        },
        signal: timeoutController.signal,
      });

      if (!response.ok) {
        return {
          status: "provider_error",
          provider: this.name,
          results: [],
          error: `Brave Search API HTTP ${response.status}`,
          diagnostics: {
            httpStatus: response.status,
            rawCount: 0,
            parsedCount: 0,
            provider: this.name,
          },
        };
      }

      const data = (await response.json()) as BraveSearchResponse;
      const raw = data.web?.results ?? [];
      const results = normalizeWebHits(
        raw.map((r) => ({
          title: r.title,
          url: r.url,
          snippet: r.description,
          source: "brave",
          publishedAt: r.page_age,
        })),
        options.maxResults
      );

      return {
        status: results.length > 0 ? "success" : "no_results",
        provider: this.name,
        results,
        diagnostics: {
          httpStatus: response.status,
          rawCount: raw.length,
          parsedCount: results.length,
          provider: this.name,
        },
      };
    } catch (error) {
      return classifyFetchError(error, this.name);
    } finally {
      clearTimeout(timeoutId);
      options.signal.removeEventListener("abort", onAbort);
    }
  }
}
