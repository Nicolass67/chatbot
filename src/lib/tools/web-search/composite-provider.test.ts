import { describe, expect, it } from "vitest";
import {
  CompositeWebSearchError,
  CompositeWebSearchProvider,
} from "./composite-provider";
import type {
  WebSearchOptions,
  WebSearchProvider,
  WebSearchProviderResult,
} from "./web-search-types";

class MockProvider implements WebSearchProvider {
  constructor(
    readonly name: string,
    private readonly result: WebSearchProviderResult
  ) {}

  async search(): Promise<WebSearchProviderResult> {
    return this.result;
  }
}

const baseOptions: WebSearchOptions = {
  maxResults: 3,
  timeoutMs: 5000,
  signal: AbortSignal.timeout(5000),
};

describe("CompositeWebSearchProvider", () => {
  it("interroge les providers en parallèle (temps ~ max, pas somme)", async () => {
    class DelayProvider implements WebSearchProvider {
      constructor(
        readonly name: string,
        private readonly delayMs: number,
        private readonly result: WebSearchProviderResult
      ) {}

      async search(): Promise<WebSearchProviderResult> {
        await new Promise((r) => setTimeout(r, this.delayMs));
        return this.result;
      }
    }

    const composite = new CompositeWebSearchProvider([
      new DelayProvider("searxng", 80, {
        status: "provider_error",
        provider: "searxng",
        results: [],
        error: "timeout",
        diagnostics: { rawCount: 0, parsedCount: 0, provider: "searxng" },
      }),
      new DelayProvider("brave", 20, {
        status: "success",
        provider: "brave",
        results: [
          {
            title: "Rapide",
            url: "https://example.com",
            domain: "example.com",
            snippet: "ok",
          },
        ],
        diagnostics: {
          httpStatus: 200,
          rawCount: 1,
          parsedCount: 1,
          provider: "brave",
        },
      }),
    ]);

    const started = Date.now();
    const result = await composite.search("test parallele", baseOptions);
    const elapsed = Date.now() - started;

    expect(result.provider).toBe("brave");
    expect(elapsed).toBeLessThan(120);
  });

  it("bascule sur Brave si SearXNG est indisponible", async () => {
    const composite = new CompositeWebSearchProvider([
      new MockProvider("searxng", {
        status: "provider_error",
        provider: "searxng",
        results: [],
        error: "connexion refusée",
        diagnostics: {
          rawCount: 0,
          parsedCount: 0,
          provider: "searxng",
        },
      }),
      new MockProvider("brave", {
        status: "success",
        provider: "brave",
        results: [
          {
            title: "GPU Test",
            url: "https://example.com/gpu",
            domain: "example.com",
            snippet: "Comparatif",
          },
        ],
        diagnostics: {
          httpStatus: 200,
          rawCount: 1,
          parsedCount: 1,
          provider: "brave",
        },
      }),
    ]);

    const result = await composite.search("gpu france", baseOptions);
    expect(result.provider).toBe("brave");
    expect(result.results).toHaveLength(1);
  });

  it("retourne no_results si SearXNG répond sans hit exploitable", async () => {
    const composite = new CompositeWebSearchProvider([
      new MockProvider("searxng", {
        status: "no_results",
        provider: "searxng",
        results: [],
        diagnostics: {
          httpStatus: 200,
          rawCount: 0,
          parsedCount: 0,
          provider: "searxng",
        },
      }),
    ]);

    const result = await composite.search("xyz inexistant", baseOptions);
    expect(result.status).toBe("no_results");
    expect(result.provider).toBe("searxng");
  });

  it("échoue avec un message explicite si tous les providers échouent", async () => {
    const composite = new CompositeWebSearchProvider([
      new MockProvider("searxng", {
        status: "provider_error",
        provider: "searxng",
        results: [],
        error: "ECONNREFUSED",
        diagnostics: {
          rawCount: 0,
          parsedCount: 0,
          provider: "searxng",
        },
      }),
    ]);

    await expect(composite.search("gpu", baseOptions)).rejects.toBeInstanceOf(
      CompositeWebSearchError
    );
    await expect(composite.search("gpu", baseOptions)).rejects.toThrow(
      /SearXNG/
    );
  });
});
