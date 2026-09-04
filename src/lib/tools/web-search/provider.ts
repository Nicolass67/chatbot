import { normalizeWebHits } from "./normalize";
import type {
  WebSearchOptions,
  WebSearchProvider,
  WebSearchProviderResult,
} from "./web-search-types";
import { classifyFetchError } from "./web-search-types";

function decodeHtml(text: string): string {
  return text
    .replace(/&amp;/g, "&")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/&#x([0-9a-f]+);/gi, (_, hex) =>
      String.fromCharCode(parseInt(hex, 16))
    )
    .replace(/&#(\d+);/g, (_, dec) => String.fromCharCode(parseInt(dec, 10)))
    .replace(/&nbsp;/g, " ");
}

function resolveResultUrl(rawHref: string): string | null {
  let url = decodeHtml(rawHref.trim());
  if (url.startsWith("//")) url = `https:${url}`;

  if (url.includes("duckduckgo.com/l/")) {
    try {
      const uddg = new URL(url).searchParams.get("uddg");
      if (uddg) url = uddg;
    } catch {
      return null;
    }
  }

  return url.startsWith("http") ? url : null;
}

function parseDuckDuckGoHtml(
  html: string,
  maxResults: number
): { hits: Array<{ title: string; url: string; snippet: string }>; rawCount: number } {
  const hits: Array<{ title: string; url: string; snippet: string }> = [];
  let rawCount = 0;

  const primaryRegex =
    /<a[^>]*class="[^"]*result__a[^"]*"[^>]*href="([^"]+)"[^>]*>([\s\S]*?)<\/a>[\s\S]*?<a[^>]*class="[^"]*result__snippet[^"]*"[^>]*>([\s\S]*?)<\/a>/gi;

  let match: RegExpExecArray | null;
  while (
    (match = primaryRegex.exec(html)) !== null &&
    hits.length < maxResults
  ) {
    rawCount++;
    const url = resolveResultUrl(match[1]);
    const title = decodeHtml(match[2].replace(/<[^>]+>/g, "").trim());
    const snippet = decodeHtml(match[3].replace(/<[^>]+>/g, "").trim());
    if (url && title) hits.push({ title, url, snippet });
  }

  return { hits, rawCount };
}

const BROWSER_HEADERS = {
  "Content-Type": "application/x-www-form-urlencoded",
  "User-Agent":
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36",
  Accept: "text/html,application/xhtml+xml",
  "Accept-Language": "fr-FR,fr;q=0.9,en-US;q=0.8,en;q=0.7",
};

/** Provider optionnel — souvent bloqué en requête serveur (anti-bot). */
export class DuckDuckGoProvider implements WebSearchProvider {
  readonly name = "duckduckgo";

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
      const response = await fetch("https://html.duckduckgo.com/html/", {
        method: "POST",
        headers: BROWSER_HEADERS,
        body: `q=${encodeURIComponent(query)}`,
        signal: timeoutController.signal,
      });

      const html = await response.text();
      const blocked =
        response.status === 202 || html.includes("anomaly-modal");

      if (blocked) {
        return {
          status: "blocked",
          provider: this.name,
          results: [],
          error: "DuckDuckGo anti-bot — requête bloquée",
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
          error: `DuckDuckGo HTTP ${response.status}`,
          diagnostics: {
            httpStatus: response.status,
            rawCount: 0,
            parsedCount: 0,
            provider: this.name,
          },
        };
      }

      const { hits, rawCount } = parseDuckDuckGoHtml(html, options.maxResults);
      const results = normalizeWebHits(
        hits.map((h) => ({
          title: h.title,
          url: h.url,
          snippet: h.snippet,
          source: "duckduckgo",
        })),
        options.maxResults
      );

      return {
        status: results.length > 0 ? "success" : "no_results",
        provider: this.name,
        results,
        diagnostics: {
          httpStatus: response.status,
          rawCount,
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

/** @deprecated Utiliser DuckDuckGoProvider — alias de compatibilité tests. */
export { DuckDuckGoProvider as default };
