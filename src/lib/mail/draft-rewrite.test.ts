import { describe, expect, it } from "vitest";
import {
  MAIL_COMPOSE_DRAFT_SYSTEM,
  MAIL_DRAFT_REWRITE_SYSTEM,
  buildComposeUserPrompt,
  buildRewriteUserPrompt,
  stripRewriteMeta,
} from "./draft-rewrite";

describe("draft-rewrite prompts", () => {
  it("place l’instruction utilisateur en tête et ne mélange pas d’anciennes consignes", () => {
    const prompt = buildRewriteUserPrompt({
      instruction: "Écris-le en anglais",
      body: "Bonjour Jean, je serai disponible mardi.",
      to: "jean@example.com",
      subject: "RDV",
    });
    expect(prompt.indexOf("USER INSTRUCTION")).toBeLessThan(
      prompt.indexOf("CURRENT DRAFT")
    );
    expect(prompt).toContain("Écris-le en anglais");
    expect(prompt).toContain("Bonjour Jean, je serai disponible mardi.");
    expect(prompt).toContain("Do not re-apply older instructions");
    expect(MAIL_DRAFT_REWRITE_SYSTEM).toContain("PRIORITÉ 1 — USER INSTRUCTION");
    expect(MAIL_DRAFT_REWRITE_SYSTEM).toMatch(/entièrement dans cette langue/i);
  });

  it("accepte une instruction libre arbitraire", () => {
    const prompt = buildRewriteUserPrompt({
      instruction:
        "Commence par remercier la personne et termine en indiquant que je suis disponible mardi.",
      body: "Bonjour,\n\nSuite à votre message.",
    });
    expect(prompt).toContain("Commence par remercier");
    expect(prompt).toContain("disponible mardi");
  });

    it("compose n’affirme jamais un envoi", () => {
      expect(MAIL_COMPOSE_DRAFT_SYSTEM).toContain(
        "N’écris JAMAIS que le message a été envoyé"
      );
    const prompt = buildComposeUserPrompt({
      instruction: "Écris un mail à Jean pour lui confirmer le rendez-vous.",
      recipientHint: "Jean",
    });
    expect(prompt).toContain("Jean");
    expect(prompt).toContain("confirmer le rendez-vous");
  });

  it("stripRewriteMeta enlève les fences et préfaces", () => {
    expect(stripRewriteMeta("```\nHello Jean\n```")).toBe("Hello Jean");
    expect(
      stripRewriteMeta("Voici une version plus claire :\nHello")
    ).toBe("Hello");
  });
});
