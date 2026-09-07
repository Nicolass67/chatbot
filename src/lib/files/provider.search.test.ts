import { describe, expect, it } from "vitest";
import { keepStrongSearchHits, nameScore, queryTokens } from "./provider";

describe("queryTokens / nameScore (phrases naturelles)", () => {
  it("retire les enveloppes conversationnelles, garde les termes utiles", () => {
    expect(queryTokens("Cherche la carte d'identité stp")).toEqual([
      "carte",
      "identite",
    ]);
  });

  it("matche un fichier sur les tokens restants sans hardcoder le domaine", () => {
    expect(
      nameScore("Docs/Perso/carte_identite.pdf", "Cherche la carte d'identité stp")
    ).toBeGreaterThan(0);
  });

  it("ne matche pas un fichier sans aucun token utile", () => {
    expect(nameScore("Unity/Library/cache.bin", "Cherche la carte d'identité stp")).toBe(
      0
    );
  });

  it("exige les 2 tokens : carte grise ne matche pas carte d'identité", () => {
    expect(
      nameScore("Resipark/carte_grise_scenic.pdf", "Trouve moi ma carte d'identité")
    ).toBe(0);
  });

  it("accepte CNI comme synonyme d'identité", () => {
    expect(nameScore("Identite/CNI.pdf", "carte d'identité")).toBeGreaterThan(0);
  });
});

describe("keepStrongSearchHits", () => {
  it("coupe les scores nettement plus faibles que le top", () => {
    const kept = keepStrongSearchHits(
      [
        { id: "a", score: 98 },
        { id: "b", score: 90 },
        { id: "c", score: 61 },
        { id: "d", score: 45 },
      ],
      { ratio: 0.82, minAbs: 50, max: 8 }
    );
    expect(kept.map((h) => h.id)).toEqual(["a", "b"]);
  });
});
