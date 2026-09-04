import { describe, expect, it } from "vitest";
import { WebSearchTracker, resolveSourceBudget } from "./web-search-tracker";

describe("resolveSourceBudget", () => {
  it("simple / single → budget serré", () => {
    const b = resolveSourceBudget({ searchType: "single", webSearchMaxResults: 5 });
    expect(b.intensity).toBe("simple");
    expect(b.targetMin).toBeGreaterThanOrEqual(8);
    expect(b.hardMax).toBeLessThanOrEqual(12);
  });

  it("research → budget élargi sans exploser", () => {
    const b = resolveSourceBudget({
      searchType: "research",
      researchRequired: true,
      webSearchMaxResults: 8,
    });
    expect(b.intensity).toBe("complex");
    expect(b.targetMin).toBeGreaterThanOrEqual(12);
    expect(b.hardMax).toBeGreaterThanOrEqual(18);
    expect(b.hardMax).toBeLessThanOrEqual(25);
  });
});

describe("WebSearchTracker", () => {
  it("arrête après 2 échecs d'infrastructure consécutifs", () => {
    const tracker = new WebSearchTracker(resolveSourceBudget({ searchType: "single" }));
    tracker.record({
      query: "gpu france",
      status: "provider_error",
      usableResultCount: 0,
      error: "SearXNG indisponible",
    });
    expect(tracker.shouldStopForResearch().stop).toBe(false);

    tracker.record({
      query: "meilleur gpu",
      status: "timeout",
      usableResultCount: 0,
      error: "timeout",
    });
    expect(tracker.shouldStopForResearch().stop).toBe(true);
    expect(tracker.shouldStopForResearch().reason).toMatch(/Délai de recherche/);
  });

  it("n'arrête pas trop tôt avec seulement 5 sources en mode standard", () => {
    const tracker = new WebSearchTracker(
      resolveSourceBudget({ searchType: "optional", webSearchMaxResults: 8 })
    );
    tracker.record({
      query: "alpha gpu france",
      status: "success",
      usableResultCount: 5,
      uniqueAdded: 5,
      uniqueDomainsAdded: 2,
    });
    expect(tracker.shouldStopForResearch().stop).toBe(false);
  });

  it("arrête quand targetMin + diversité sont atteints", () => {
    const tracker = new WebSearchTracker({
      intensity: "standard",
      targetMin: 10,
      hardMax: 20,
      maxSearches: 3,
      perQueryMaxResults: 8,
    });
    tracker.record({
      query: "q1",
      status: "success",
      usableResultCount: 10,
      uniqueAdded: 10,
      uniqueDomainsAdded: 4,
    });
    const stop = tracker.shouldStopForResearch();
    expect(stop.stop).toBe(true);
    expect(stop.kind).toBe("sufficient");
  });

  it("arrête au plus tard après maxSearches", () => {
    const tracker = new WebSearchTracker({
      intensity: "simple",
      targetMin: 8,
      hardMax: 12,
      maxSearches: 2,
      perQueryMaxResults: 6,
    });
    for (const q of ["q1", "q2"]) {
      tracker.record({
        query: q,
        status: "success",
        usableResultCount: 2,
        uniqueAdded: 2,
      });
    }
    const stop = tracker.shouldStopForResearch();
    expect(stop.stop).toBe(true);
  });

  it("ignore les requêtes dédupliquées", () => {
    const tracker = new WebSearchTracker();
    tracker.record({
      query: "gpu france",
      status: "no_results",
      usableResultCount: 0,
      deduplicated: true,
    });
    expect(tracker.stats.totalSearches).toBe(0);
  });
});
