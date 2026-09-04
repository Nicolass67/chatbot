import { describe, expect, it } from "vitest";
import {
  fallbackTitleFromExchange,
  normalizeConversationTitle,
  parseTitleResponse,
} from "./title-generator";

describe("normalizeConversationTitle", () => {
  it("retire les guillemets et tronque", () => {
    expect(normalizeConversationTitle('"Fonctionnement du DLSS"')).toBe(
      "Fonctionnement du DLSS"
    );
    expect(normalizeConversationTitle("a".repeat(120)).length).toBeLessThanOrEqual(
      80
    );
  });
});

describe("parseTitleResponse", () => {
  it("parse un JSON de titre", () => {
    expect(
      parseTitleResponse('{"title":"Comparaison RTX 5080 et 5090"}')
    ).toBe("Comparaison RTX 5080 et 5090");
  });
});

describe("fallbackTitleFromExchange", () => {
  it("ignore un opener générique et utilise l'assistant", () => {
    expect(
      fallbackTitleFromExchange({
        userText: "Bonjour",
        assistantText:
          "Le DLSS est une technologie de supersampling par intelligence artificielle développée par NVIDIA.",
      })
    ).toContain("DLSS");
  });

  it("utilise le message user s'il est descriptif", () => {
    expect(
      fallbackTitleFromExchange({
        userText: "Explique le fonctionnement du DLSS",
        assistantText: "Le DLSS utilise des modèles neuronaux...",
      })
    ).toBe("Explique le fonctionnement du DLSS");
  });
});

describe("shouldAutoUpdateTitle via maybeGenerateConversationTitle", () => {
  it("exporte les constantes attendues", async () => {
    const mod = await import("./title-generator");
    expect(mod.TITLE_MAX_LENGTH).toBe(80);
    expect(mod.TITLE_REFRESH_EVERY_MESSAGES).toBe(6);
  });
});
