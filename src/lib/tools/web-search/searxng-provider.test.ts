import { describe, expect, it, vi } from "vitest";
import { SearxngProvider } from "./searxng-provider";

const BASE = "http://localhost:8080";

function mockFetch(
  impl: (url: string) => Response | Promise<Response>
): () => void {
  const original = globalThis.fetch;
  globalThis.fetch = vi.fn(async (input: RequestInfo | URL) => {
    const url = typeof input === "string" ? input : input.toString();
    return impl(url);
  }) as typeof fetch;
  return () => {
    globalThis.fetch = original;
  };
}

describe("SearxngProvider", () => {
  it("retourne des résultats normalisés en cas de succès", async () => {
    const restore = mockFetch(() =>
      Response.json({
        results: [
          {
            title: "Meilleur GPU 2026",
            url: "https://example.com/gpu",
            content: "Comparatif cartes graphiques.",
            engine: "google",
            publishedDate: "2026-09-01",
          },
        ],
      })
    );

    try {
      const provider = new SearxngProvider(BASE);
      const result = await provider.search("gpu france", {
        maxResults: 5,
        timeoutMs: 5000,
        signal: AbortSignal.timeout(5000),
      });

      expect(result.status).toBe("success");
      expect(result.provider).toBe("searxng");
      expect(result.results).toHaveLength(1);
      expect(result.results[0]?.url).toBe("https://example.com/gpu");
      expect(result.results[0]?.source).toBe("google");
      expect(result.results[0]?.publishedAt).toBe("2026-09-01");
      const calledUrl = String(
        (globalThis.fetch as ReturnType<typeof vi.fn>).mock.calls[0]?.[0]
      );
      expect(calledUrl).toContain("format=json");
      expect(calledUrl).toContain("gpu+france");
    } finally {
      restore();
    }
  });

  it("signale no_results quand SearXNG répond avec une liste vide", async () => {
    const restore = mockFetch(() => Response.json({ results: [] }));

    try {
      const result = await new SearxngProvider(BASE).search("xyz", {
        maxResults: 5,
        timeoutMs: 5000,
        signal: AbortSignal.timeout(5000),
      });
      expect(result.status).toBe("no_results");
      expect(result.results).toHaveLength(0);
    } finally {
      restore();
    }
  });

  it("signale timeout quand la requête dépasse le délai", async () => {
    const original = globalThis.fetch;
    globalThis.fetch = vi.fn(
      (_input, init?: RequestInit) =>
        new Promise<Response>((_, reject) => {
          init?.signal?.addEventListener("abort", () => {
            reject(new DOMException("Aborted", "AbortError"));
          });
        })
    ) as typeof fetch;

    try {
      const result = await new SearxngProvider(BASE).search("gpu", {
        maxResults: 5,
        timeoutMs: 50,
        signal: AbortSignal.timeout(5000),
      });
      expect(result.status).toBe("timeout");
      expect(result.error).toMatch(/Délai/i);
    } finally {
      globalThis.fetch = original;
    }
  });

  it("signale provider_error sur HTTP 500", async () => {
    const restore = mockFetch(() => new Response("error", { status: 500 }));

    try {
      const result = await new SearxngProvider(BASE).search("gpu", {
        maxResults: 5,
        timeoutMs: 5000,
        signal: AbortSignal.timeout(5000),
      });
      expect(result.status).toBe("provider_error");
      expect(result.error).toMatch(/HTTP 500/);
    } finally {
      restore();
    }
  });

  it("signale provider_error sur JSON malformé", async () => {
    const restore = mockFetch(() =>
      new Response("not-json", {
        status: 200,
        headers: { "content-type": "application/json" },
      })
    );

    try {
      const result = await new SearxngProvider(BASE).search("gpu", {
        maxResults: 5,
        timeoutMs: 5000,
        signal: AbortSignal.timeout(5000),
      });
      expect(result.status).toBe("provider_error");
      expect(result.error).toMatch(/JSON/i);
    } finally {
      restore();
    }
  });

  it("signale blocked quand tous les moteurs SearXNG sont suspendus", async () => {
    const restore = mockFetch(() =>
      Response.json({
        results: [],
        unresponsive_engines: [
          ["google cse", "Suspended: too many requests"],
          ["startpage", "Suspended: CAPTCHA"],
        ],
      })
    );

    try {
      const result = await new SearxngProvider(BASE).search("gpu", {
        maxResults: 5,
        timeoutMs: 5000,
        signal: AbortSignal.timeout(5000),
      });
      expect(result.status).toBe("blocked");
      expect(result.error).toMatch(/suspendus/i);
    } finally {
      restore();
    }
  });
});
