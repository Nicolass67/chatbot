import { describe, expect, it } from "vitest";
import {
  buildWebSearchQuery,
  capSourcesForSynthesis,
  extractWebSearchQuery,
  shouldAutoWebSearch,
  shouldSkipWebSearch,
} from "@/lib/tools/web-search/heuristics";

describe("shouldAutoWebSearch / shouldSkipWebSearch", () => {
  it("ne décident plus via mots-clés (toujours false)", () => {
    expect(
      shouldAutoWebSearch(
        "recherche sur internet les derniers avancés sur le dlss 5"
      )
    ).toBe(false);
    expect(shouldAutoWebSearch("Explique-moi le DLSS 5")).toBe(false);
    expect(shouldSkipWebSearch("Bonjour !")).toBe(false);
    expect(shouldSkipWebSearch("Explique-moi le DLSS 5")).toBe(false);
  });
});

describe("capSourcesForSynthesis", () => {
  it("limite et déduplique les sources pour la synthèse", () => {
    const sources = Array.from({ length: 20 }, (_, i) => ({
      title: `GPU ${i}`,
      url: i < 2 ? "https://example.com/a" : `https://example.com/${i}`,
      domain: "example.com",
      snippet: "s",
    }));
    const capped = capSourcesForSynthesis(sources, 5);
    expect(capped).toHaveLength(5);
    expect(capped[0]?.url).toBe("https://example.com/a");
  });
});

describe("buildWebSearchQuery", () => {
  it("priorise route.web.searchQuery", () => {
    expect(
      buildWebSearchQuery({
        userMessage: "prix actuel du bitcoin",
        route: { searchQuery: "Bitcoin current price" },
      })
    ).toBe("Bitcoin current price");
  });

  it("renvoie le message utilisateur sans strip lexical", () => {
    const query = buildWebSearchQuery({
      userMessage: "analyse le prix actuel du bitcoin",
    });
    expect(query).toBe("analyse le prix actuel du bitcoin");
  });
});

describe("extractWebSearchQuery", () => {
  it("ne strip plus les préfixes — message intact", () => {
    expect(
      extractWebSearchQuery(
        "recherche sur internet les derniers avancés sur le dlss 5"
      )
    ).toBe("recherche sur internet les derniers avancés sur le dlss 5");
  });
});


describe("buildWebSearchQuery grounding", () => {
  it("ancre un follow-up court avec le contexte aspirateurs", () => {
    const query = buildWebSearchQuery({
      userMessage: "Donne clairement 5 modèles maintenant",
      recentUserMessages: [
        "Fait un comparatif des meilleurs aspirateurs sur le marché",
      ],
    });
    expect(query.toLowerCase()).toContain("aspirateur");
  });
});
