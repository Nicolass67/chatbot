import { describe, expect, it, vi } from "vitest";
import { webSearchTool } from "./tool";
import { WebSearchError } from "./web-search-types";

vi.mock("./provider-factory", () => ({
  createWebSearchProvider: vi.fn(),
}));

describe("webSearchTool", () => {
  it("propage provider_error sans masquer l'échec", async () => {
    const { createWebSearchProvider } = await import("./provider-factory");
    vi.mocked(createWebSearchProvider).mockReturnValue({
      name: "searxng",
      search: async () => ({
        status: "provider_error",
        provider: "searxng",
        results: [],
        error: "SearXNG indisponible",
        diagnostics: { rawCount: 0, parsedCount: 0, provider: "searxng" },
      }),
    });

    await expect(
      webSearchTool.execute(
        { query: "gpu france" },
        {
          signal: AbortSignal.timeout(5000),
          settings: {
            webSearchMaxResults: 5,
            webSearchTimeoutMs: 5000,
          } as import("@/lib/settings/service").AppSettings,
          conversationId: "c1",
          runtimeLocation: "local",
        }
      )
    ).rejects.toBeInstanceOf(WebSearchError);
  });

  it("retourne no_results sans throw", async () => {
    const { createWebSearchProvider } = await import("./provider-factory");
    vi.mocked(createWebSearchProvider).mockReturnValue({
      name: "searxng",
      search: async () => ({
        status: "no_results",
        provider: "searxng",
        results: [],
        diagnostics: { rawCount: 0, parsedCount: 0, provider: "searxng" },
      }),
    });

    const output = await webSearchTool.execute(
      { query: "xyz inexistant" },
      {
        signal: AbortSignal.timeout(5000),
        settings: {
          webSearchMaxResults: 5,
          webSearchTimeoutMs: 5000,
        } as import("@/lib/settings/service").AppSettings,
        conversationId: "c1",
        runtimeLocation: "local",
      }
    );

    expect(output.status).toBe("no_results");
    expect(output.results).toHaveLength(0);
  });
});
