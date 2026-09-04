import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

describe("createWebSearchProvider", () => {
  const originalEnv = { ...process.env };

  beforeEach(() => {
    vi.resetModules();
  });

  afterEach(() => {
    process.env = { ...originalEnv };
  });

  it("sélectionne SearXNG par défaut", async () => {
    delete process.env.WEB_SEARCH_PROVIDER;
    process.env.SEARXNG_URL = "http://localhost:8080";
    const { createWebSearchProvider } = await import("./provider-factory");
    const provider = createWebSearchProvider();
    expect(provider.name).toBe("searxng");
  });

  it("compose auto avec SearXNG puis Brave si clé présente", async () => {
    process.env.WEB_SEARCH_PROVIDER = "auto";
    process.env.SEARXNG_URL = "http://localhost:8080";
    process.env.BRAVE_SEARCH_API_KEY = "test-key";
    const { createWebSearchProvider } = await import("./provider-factory");
    const provider = createWebSearchProvider();
    expect(provider.name).toBe("auto");
  });

  it("exige BRAVE_SEARCH_API_KEY pour le mode brave", async () => {
    process.env.WEB_SEARCH_PROVIDER = "brave";
    delete process.env.BRAVE_SEARCH_API_KEY;
    const { createWebSearchProvider } = await import("./provider-factory");
    expect(() => createWebSearchProvider()).toThrow(/BRAVE_SEARCH_API_KEY/);
  });
});
