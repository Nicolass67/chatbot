import { describe, expect, it } from "vitest";
import {
  buildSynthesisContinuationMessages,
  looksTruncated,
  resolveSynthesisMaxTokens,
  SYNTHESIS_MIN_MAX_TOKENS,
} from "./synthesis";

describe("synthesis", () => {
  it("applique un plancher de tokens pour la synthèse Agent", () => {
    expect(
      resolveSynthesisMaxTokens({
        maxTokens: 512,
      } as Parameters<typeof resolveSynthesisMaxTokens>[0])
    ).toBe(SYNTHESIS_MIN_MAX_TOKENS);
    expect(
      resolveSynthesisMaxTokens({
        maxTokens: 8192,
      } as Parameters<typeof resolveSynthesisMaxTokens>[0])
    ).toBe(8192);
  });

  it("détecte une réponse probablement tronquée", () => {
    const long = "A".repeat(300) + " analyse du marché sans fin";
    expect(looksTruncated(long)).toBe(true);
    expect(looksTruncated(`${"A".repeat(300)} fin complète.`)).toBe(false);
    expect(looksTruncated("Réponse courte.")).toBe(false);
  });

  it("construit un message de continuation", () => {
    const base = [
      { role: "system" as const, content: "sys" },
      { role: "user" as const, content: "goal" },
    ];
    const cont = buildSynthesisContinuationMessages(base, "Début…");
    expect(cont).toHaveLength(4);
    expect(cont[2]?.role).toBe("assistant");
    expect(cont[3]?.role).toBe("user");
  });
});
