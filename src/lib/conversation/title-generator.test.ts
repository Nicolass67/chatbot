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

  it("raccourcit un message user descriptif", () => {
    expect(
      fallbackTitleFromExchange({
        userText: "Explique le fonctionnement du DLSS",
        assistantText: "Le DLSS utilise des modèles neuronaux...",
      })
    ).toBe("Fonctionnement du DLSS");
  });

  it("extrait un sujet Files depuis une requête polie", () => {
    expect(
      fallbackTitleFromExchange({
        userText: "Peux-tu me trouver ma carte d'identité ?",
        assistantText: "Voici les fichiers correspondants.",
      })
    ).toMatch(/carte d'identité/i);
  });
});

describe("shouldAutoUpdateTitle", () => {
  it("autorise un placeholder Mail/Files après le 1er échange", async () => {
    const { shouldAutoUpdateTitle } = await import("./title-generator");
    expect(
      shouldAutoUpdateTitle({
        title: "Mail Assistant",
        titleSource: "auto",
        messageCount: 2,
      })
    ).toBe(true);
    expect(
      shouldAutoUpdateTitle({
        title: "Files Assistant",
        titleSource: "auto",
        messageCount: 2,
      })
    ).toBe(true);
  });

  it("bloque un titre manuel et un titre déjà stabilisé", async () => {
    const { shouldAutoUpdateTitle } = await import("./title-generator");
    expect(
      shouldAutoUpdateTitle({
        title: "Nouvelle conversation",
        titleSource: "user",
        messageCount: 4,
      })
    ).toBe(false);
    expect(
      shouldAutoUpdateTitle({
        title: "Voyage à Tokyo",
        titleSource: "auto",
        messageCount: 12,
      })
    ).toBe(false);
  });

  it("exporte les constantes attendues", async () => {
    const mod = await import("./title-generator");
    expect(mod.TITLE_MAX_LENGTH).toBe(80);
    expect(mod.TITLE_REFRESH_EVERY_MESSAGES).toBe(6);
  });
});
