import { describe, expect, it } from "vitest";
import {
  areQueriesEquivalent,
  normalizeSearchQuery,
  SearchQueryCache,
} from "./search-dedup";

describe("search-dedup", () => {
  it("normalise les requêtes", () => {
    expect(normalizeSearchQuery("  Meilleur GPU  ")).toBe("meilleur gpu");
  });

  it("détecte des requêtes quasi-identiques", () => {
    const a =
      "meilleur GPU moins de 1000 euros France septembre 2026 prix disponibilité";
    const b =
      "meilleur GPU moins de 1000 euros France prix disponibilité septembre 2026";
    expect(areQueriesEquivalent(a, b)).toBe(true);
  });

  it("ne confond pas des requêtes différentes", () => {
    expect(
      areQueriesEquivalent(
        "GPU gaming moins de 1000 euros France",
        "RTX 4070 prix France"
      )
    ).toBe(false);
  });

  it("réutilise le cache pour une requête équivalente", () => {
    const cache = new SearchQueryCache();
    cache.store(
      "meilleur GPU moins de 1000 euros France septembre 2026",
      "3 résultats",
      3,
      [{ title: "t", url: "u", domain: "d", snippet: "s" }],
      { query: "meilleur GPU moins de 1000 euros France septembre 2026", results: [] }
    );
    const hit = cache.findEquivalent(
      "meilleur GPU moins de 1000 euros France prix disponibilité septembre 2026"
    );
    expect(hit).not.toBeNull();
    expect(hit?.sourceCount).toBe(3);
  });
});
