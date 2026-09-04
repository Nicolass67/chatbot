import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import {
  checkSearxngHealth,
  clearSearxngHealthCache,
  waitForSearxngHealth,
} from "./searxng-health";

vi.mock("@/lib/config/env", () => ({
  getEnv: vi.fn(() => ({
    WEB_SEARCH_ENABLED: true,
    WEB_SEARCH_PROVIDER: "searxng",
    SEARXNG_URL: "http://localhost:8080",
  })),
}));

vi.mock("./provider-factory", () => ({
  getSearxngUrl: () => "http://localhost:8080",
}));

function mockFetch(impl: (url: string) => Response | Promise<Response>) {
  const original = globalThis.fetch;
  globalThis.fetch = vi.fn(async (input: RequestInfo | URL) => {
    const url = typeof input === "string" ? input : input.toString();
    return impl(url);
  }) as typeof fetch;
  return () => {
    globalThis.fetch = original;
  };
}

describe("checkSearxngHealth", () => {
  beforeEach(() => {
    clearSearxngHealthCache();
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  it("SearXNG déjà disponible", async () => {
    const restore = mockFetch(() =>
      Response.json({ results: [{ title: "t", url: "https://x.com" }] })
    );
    try {
      const result = await checkSearxngHealth({ timeoutMs: 3000 });
      expect(result.status).toBe("connected");
      expect(result.resultCount).toBe(1);
    } finally {
      restore();
    }
  });

  it("SearXNG absent (connexion refusée)", async () => {
    const restore = mockFetch(() => {
      throw new TypeError("fetch failed");
    });
    try {
      const result = await checkSearxngHealth({ timeoutMs: 1000 });
      expect(result.status).toBe("unavailable");
    } finally {
      restore();
    }
  });

  it("SearXNG démarré mais pas encore prêt (HTTP 503)", async () => {
    const restore = mockFetch(() => new Response("Service Unavailable", { status: 503 }));
    try {
      const result = await checkSearxngHealth({ timeoutMs: 3000 });
      expect(result.status).toBe("starting");
    } finally {
      restore();
    }
  });

  it("SearXNG répond sans résultats — moteurs suspendus", async () => {
    const restore = mockFetch(() =>
      Response.json({
        results: [],
        unresponsive_engines: [["duckduckgo", "timeout"]],
      })
    );
    try {
      const result = await checkSearxngHealth({ timeoutMs: 3000 });
      expect(result.status).toBe("starting");
      expect(result.message).toMatch(/suspendus/i);
    } finally {
      restore();
    }
  });

  it("timeout health check", async () => {
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
      const result = await checkSearxngHealth({ timeoutMs: 50 });
      expect(result.status).toBe("starting");
      expect(result.message).toMatch(/timeout/i);
    } finally {
      globalThis.fetch = original;
    }
  });

  it("utilise Wikipedia uniquement pour un health check rapide", async () => {
    const restore = mockFetch((url) => {
      expect(url).toContain("engines=wikipedia");
      return Response.json({ results: [{ title: "t", url: "https://x.com" }] });
    });
    try {
      await checkSearxngHealth({ timeoutMs: 3000 });
    } finally {
      restore();
    }
  });

  it("Web désactivé", async () => {
    const { getEnv } = await import("@/lib/config/env");
    vi.mocked(getEnv).mockReturnValueOnce({
      WEB_SEARCH_ENABLED: false,
      WEB_SEARCH_PROVIDER: "searxng",
      SEARXNG_URL: "http://localhost:8080",
    } as ReturnType<typeof getEnv>);

    const result = await checkSearxngHealth();
    expect(result.status).toBe("disabled");
  });
});

describe("waitForSearxngHealth", () => {
  it("SearXNG finalement disponible après attente", async () => {
    let calls = 0;
    const restore = mockFetch(() => {
      calls++;
      if (calls < 3) {
        return new Response("not ready", { status: 503 });
      }
      return Response.json({ results: [{ title: "t", url: "https://x.com" }] });
    });

    try {
      const result = await waitForSearxngHealth({
        timeoutMs: 5000,
        intervalMs: 100,
        checkTimeoutMs: 500,
      });
      expect(result.status).toBe("connected");
      expect(calls).toBeGreaterThanOrEqual(3);
    } finally {
      restore();
    }
  });

  it("timeout de démarrage", async () => {
    const restore = mockFetch(() => new Response("not ready", { status: 503 }));
    try {
      const result = await waitForSearxngHealth({
        timeoutMs: 300,
        intervalMs: 50,
        checkTimeoutMs: 5000,
      });
      expect(result.status).toBe("starting");
    } finally {
      restore();
    }
  });
});
