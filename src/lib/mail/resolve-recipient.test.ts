import { describe, expect, it } from "vitest";
import {
  extractRecipientNameHint,
  messageImpliesSelfRecipient,
} from "./resolve-recipient";

describe("resolve-recipient helpers", () => {
  it("détecte moi-même / à moi", () => {
    expect(messageImpliesSelfRecipient("Écris un mail à moi-même")).toBe(true);
    expect(messageImpliesSelfRecipient("Envoie ça à mon adresse")).toBe(true);
    expect(messageImpliesSelfRecipient("Écris à Maxime")).toBe(false);
  });

  it("extrait un nom de destinataire", () => {
    expect(
      extractRecipientNameHint("Écris un mail à Maxime Plançon pour demain")
    ).toBe("Maxime Plançon");
    expect(extractRecipientNameHint("Réponds à Alice")).toMatch(/Alice/i);
  });
});
