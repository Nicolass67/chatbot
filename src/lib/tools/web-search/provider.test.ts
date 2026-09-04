import { describe, expect, it } from "vitest";
import { DuckDuckGoProvider } from "@/lib/tools/web-search/provider";

const SAMPLE_HTML = `
<div class="result">
  <a class="result__a" href="https://duckduckgo.com/l/?uddg=https%3A%2F%2Fexample.com%2Fgpu">Meilleur GPU 2026</a>
  <a class="result__snippet">Comparatif cartes graphiques gaming.</a>
</div>
`;

const BLOCKED_HTML = `<div class="anomaly-modal__modal">bot check</div>`;

describe("DuckDuckGoProvider", () => {
  it("parse les résultats HTML DuckDuckGo", async () => {
    const provider = new DuckDuckGoProvider();
    const originalFetch = globalThis.fetch;
    globalThis.fetch = async () =>
      new Response(SAMPLE_HTML, { status: 200 }) as Response;

    try {
      const result = await provider.search("gpu france", {
        maxResults: 3,
        timeoutMs: 5000,
        signal: AbortSignal.timeout(5000),
      });
      expect(result.status).toBe("success");
      expect(result.diagnostics.parsedCount).toBe(1);
      expect(result.results[0]?.url).toBe("https://example.com/gpu");
      expect(result.results[0]?.title).toContain("GPU");
    } finally {
      globalThis.fetch = originalFetch;
    }
  });

  it("signale un blocage anti-bot avec status blocked", async () => {
    const provider = new DuckDuckGoProvider();
    const originalFetch = globalThis.fetch;
    globalThis.fetch = async () =>
      new Response(BLOCKED_HTML, { status: 202 }) as Response;

    try {
      const result = await provider.search("gpu", {
        maxResults: 3,
        timeoutMs: 5000,
        signal: AbortSignal.timeout(5000),
      });
      expect(result.results).toHaveLength(0);
      expect(result.status).toBe("blocked");
      expect(result.diagnostics.httpStatus).toBe(202);
    } finally {
      globalThis.fetch = originalFetch;
    }
  });
});
