import { normalizeWebHits } from "./normalize";
import type {
  WebSearchOptions,
  WebSearchProvider,
  WebSearchProviderResult,
} from "./web-search-types";
import { classifyFetchError } from "./web-search-types";

interface SearxJsonResult {
  title?: string;
  url?: string;
  content?: string;
  engine?: string;
  engines?: string[];
  publishedDate?: string;
  pubdate?: string;
}

interface SearxJsonResponse {
  results?: SearxJsonResult[];
  unresponsive_engines?: Array<[string, string]>;
}

function describeUnresponsiveEngines(
  engines: Array<[string, string]> | undefined
): string | null {
  if (!engines || engines.length === 0) return null;
  const summary = engines
    .slice(0, 4)
    .map(([name, reason]) => `${name}: ${reason}`)
    .join("; ");
  return `Moteurs SearXNG suspendus — ${summary}`;
}

export class SearxngProvider implements WebSearchProvider {
  readonly name = "searxng";

  constructor(private readonly baseUrl: string) {}

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
      const base = this.baseUrl.replace(/\/$/, "");
      const url = new URL(`${base}/search`);
      url.searchParams.set("q", query);
      url.searchParams.set("format", "json");
      url.searchParams.set("language", "fr-FR");

      const response = await fetch(url, {
        method: "GET",
        headers: { Accept: "application/json" },
        signal: timeoutController.signal,
      });

      if (response.status === 403) {
        return {
          status: "provider_error",
          provider: this.name,
          results: [],
          error:
            "SearXNG a refusé le format JSON (activez search.formats: [html, json] dans settings.yml)",
          diagnostics: {
            httpStatus: response.status,
            rawCount: 0,
            parsedCount: 0,
            provider: this.name,
          },
        };
      }

      if (!response.ok) {
        return {
          status: "provider_error",
          provider: this.name,
          results: [],
          error: `SearXNG HTTP ${response.status}`,
          diagnostics: {
            httpStatus: response.status,
            rawCount: 0,
            parsedCount: 0,
            provider: this.name,
          },
        };
      }

      const contentType = response.headers.get("content-type") ?? "";
      if (!contentType.includes("application/json")) {
        return {
          status: "provider_error",
          provider: this.name,
          results: [],
          error:
            "SearXNG n'a pas renvoyé de JSON — vérifiez que l'instance est démarrée et accessible",
          diagnostics: {
            httpStatus: response.status,
            rawCount: 0,
            parsedCount: 0,
            provider: this.name,
          },
        };
      }

      let data: SearxJsonResponse;
      try {
        data = (await response.json()) as SearxJsonResponse;
      } catch {
        return {
          status: "provider_error",
          provider: this.name,
          results: [],
          error: "Réponse JSON SearXNG invalide",
          diagnostics: {
            httpStatus: response.status,
            rawCount: 0,
            parsedCount: 0,
            provider: this.name,
          },
        };
      }

      const raw = data.results ?? [];
      const results = normalizeWebHits(
        raw.map((r) => ({
          title: r.title,
          url: r.url,
          snippet: r.content,
          source: r.engine ?? r.engines?.join(", "),
          publishedAt: r.publishedDate ?? r.pubdate,
        })),
        options.maxResults
      );

      if (results.length === 0) {
        const engineIssue = describeUnresponsiveEngines(
          data.unresponsive_engines
        );
        if (engineIssue) {
          return {
            status: "blocked",
            provider: this.name,
            results: [],
            error: engineIssue,
            diagnostics: {
              httpStatus: response.status,
              rawCount: 0,
              parsedCount: 0,
              provider: this.name,
            },
          };
        }
      }

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
