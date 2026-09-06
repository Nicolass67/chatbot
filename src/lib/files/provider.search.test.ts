import { describe, expect, it } from "vitest";
import { nameScore, queryTokens } from "./provider";

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
});
