import { describe, expect, it } from "vitest";
import { WebSearchTracker } from "./web-search-tracker";

describe("WebSearchTracker", () => {
  it("arrête après 2 échecs d'infrastructure consécutifs", () => {
    const tracker = new WebSearchTracker();
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

  it("arrête après 3 recherches vides distinctes", () => {
    const tracker = new WebSearchTracker();
    for (const q of ["a", "b", "c"]) {
      tracker.record({ query: q, status: "no_results", usableResultCount: 0 });
    }
    const stop = tracker.shouldStopForResearch();
    expect(stop.stop).toBe(true);
    expect(stop.kind).toBe("failure");
  });

  it("arrête quand assez de sources sont collectées", () => {
    const tracker = new WebSearchTracker();
    for (const q of ["alpha gpu france", "beta gpu prix", "gamma gpu stock", "delta gpu comparatif"]) {
      tracker.record({
        query: q,
        status: "success",
        usableResultCount: 5,
      });
    }
    const stop = tracker.shouldStopForResearch();
    expect(stop.stop).toBe(true);
    expect(stop.kind).toBe("sufficient");
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
