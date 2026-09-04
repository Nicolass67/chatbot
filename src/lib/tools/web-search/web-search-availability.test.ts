import { beforeEach, describe, expect, it, vi } from "vitest";
import { evaluateWebSearchAvailability } from "./web-search-availability";

vi.mock("@/lib/config/env", () => ({
  getEnv: vi.fn(),
}));

vi.mock("./searxng-health", () => ({
  getCachedSearxngHealth: vi.fn(),
  clearSearxngHealthCache: vi.fn(),
  waitForSearxngHealth: vi.fn(),
}));

import { getEnv } from "@/lib/config/env";
import {
  clearSearxngHealthCache,
  getCachedSearxngHealth,
  waitForSearxngHealth,
} from "./searxng-health";

const baseEnv = {
  WEB_SEARCH_ENABLED: true,
  WEB_SEARCH_PROVIDER: "searxng" as const,
  SEARXNG_URL: "http://localhost:8080",
};

describe("evaluateWebSearchAvailability", () => {
  beforeEach(() => {
    vi.mocked(getEnv).mockReturnValue(baseEnv as ReturnType<typeof getEnv>);
    vi.mocked(waitForSearxngHealth).mockReset();
    vi.mocked(clearSearxngHealthCache).mockReset();
  });

  it("disponible quand SearXNG connecté", async () => {
    vi.mocked(getCachedSearxngHealth).mockResolvedValue({
      status: "connected",
      url: "http://localhost:8080",
      checkedAt: new Date().toISOString(),
    });

    const result = await evaluateWebSearchAvailability();
    expect(result.available).toBe(true);
  });

  it("indisponible quand SearXNG absent (mode searxng)", async () => {
    vi.mocked(getCachedSearxngHealth).mockResolvedValue({
      status: "unavailable",
      url: "http://localhost:8080",
      message: "SearXNG indisponible",
      checkedAt: new Date().toISOString(),
    });

    const result = await evaluateWebSearchAvailability();
    expect(result.available).toBe(false);
    expect(result.reason).toMatch(/SearXNG indisponible/);
  });

  it("auto avec Brave configuré reste disponible", async () => {
    vi.mocked(getEnv).mockReturnValue({
      ...baseEnv,
      WEB_SEARCH_PROVIDER: "auto",
      BRAVE_SEARCH_API_KEY: "test-key",
    } as ReturnType<typeof getEnv>);
    vi.mocked(getCachedSearxngHealth).mockResolvedValue({
      status: "unavailable",
      url: "http://localhost:8080",
      checkedAt: new Date().toISOString(),
    });

    const result = await evaluateWebSearchAvailability();
    expect(result.available).toBe(true);
    expect(result.provider).toBe("auto");
  });

  it("attend SearXNG en démarrage puis devient disponible", async () => {
    vi.mocked(getCachedSearxngHealth).mockResolvedValue({
      status: "starting",
      url: "http://localhost:8080",
      message: "moteurs suspendus",
      checkedAt: new Date().toISOString(),
    });
    vi.mocked(waitForSearxngHealth).mockResolvedValue({
      status: "connected",
      url: "http://localhost:8080",
      checkedAt: new Date().toISOString(),
      resultCount: 3,
    });

    const result = await evaluateWebSearchAvailability({ waitIfStartingMs: 5000 });

    expect(waitForSearxngHealth).toHaveBeenCalled();
    expect(clearSearxngHealthCache).toHaveBeenCalled();
    expect(result.available).toBe(true);
  });

  it("chat normal possible — Web désactivé n'est pas une erreur runtime", async () => {
    vi.mocked(getEnv).mockReturnValue({
      ...baseEnv,
      WEB_SEARCH_ENABLED: false,
    } as ReturnType<typeof getEnv>);
    vi.mocked(getCachedSearxngHealth).mockResolvedValue({
      status: "disabled",
      url: "http://localhost:8080",
      checkedAt: new Date().toISOString(),
    });

    const result = await evaluateWebSearchAvailability();
    expect(result.available).toBe(false);
    expect(result.searxng.status).toBe("disabled");
  });
});
