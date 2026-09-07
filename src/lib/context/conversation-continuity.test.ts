import { describe, expect, it } from "vitest";
import {
  groundSearchQueryWithContext,
  isAmbiguousSearchQuery,
  isFollowUpTurn,
  priorUserMessages,
} from "./conversation-continuity";

describe("conversation continuity", () => {
  it("détecte le follow-up aspirateurs / modèles", () => {
    expect(
      isFollowUpTurn("Donne clairement 5 modèles maintenant", true)
    ).toBe(true);
  });

  it("détecte un follow-up long (top 10 + recherche internet)", () => {
    const msg =
      "Tu peux me donner un top 10 des models maintenant ? Si besoin fait une recherche internet";
    expect(isFollowUpTurn(msg, true)).toBe(true);
    expect(isAmbiguousSearchQuery(msg)).toBe(true);
  });

  it("ancre la requête web sur aspirateurs", () => {
    const q = groundSearchQueryWithContext({
      query: "Donne clairement 5 modèles maintenant",
      recentUserMessages: [
        "Fait un comparatif des meilleurs aspirateurs sur le marché",
      ],
    });
    expect(q.toLowerCase()).toContain("aspirateur");
  });

  it("ancre top 10 models sur gazinières (pas les LLM)", () => {
    const q = groundSearchQueryWithContext({
      query:
        "Tu peux me donner un top 10 des models maintenant ? Si besoin fait une recherche internet",
      recentUserMessages: [
        "Fais un comparatif des meilleurs gazinières sur le marché",
      ],
    });
    const lower = q.toLowerCase();
    expect(lower).toMatch(/gazini/);
    expect(lower).not.toMatch(/llm|chatgpt|claude/);
  });

  it("exclut le message courant des priors", () => {
    expect(
      priorUserMessages(["Aspirateurs", "Donne 5 modèles"], "Donne 5 modèles")
    ).toEqual(["Aspirateurs"]);
  });

  it("ne force pas le follow-up sans historique", () => {
    // Sans historique : un top 10 ambigu n'est PAS un follow-up
    // (mais reste une query ambiguë pour l'ancrage si des priors existent ailleurs).
    expect(
      isFollowUpTurn(
        "Quels sont les meilleurs LLM open source en 2026 ?",
        false
      )
    ).toBe(false);
  });

  it("détecte un affinage budget avec pronom (micro-ondes → 200-300€)", () => {
    const msg =
      "J'aimerai qu'il coute entre 200 et 300€ si possible. Tu peux me chercher ça ?";
    expect(isFollowUpTurn(msg, true)).toBe(true);
    expect(isAmbiguousSearchQuery(msg)).toBe(true);
  });

  it("ancre la requête budget sur le sujet micro-ondes de l'historique", () => {
    const q = groundSearchQueryWithContext({
      query:
        "J'aimerai qu'il coute entre 200 et 300€ si possible. Tu peux me chercher ça ?",
      recentUserMessages: [
        "Tu peux me trouver les micro ondes avec le meilleur rapport qualité prix ? Donne des models précis",
      ],
    });
    const lower = q.toLowerCase();
    expect(lower).toMatch(/micro/);
    expect(lower).not.toMatch(/smartphone|iphone|voyage/);
  });

  it("ancre une fourchette de prix seule (sans pronom)", () => {
    const q = groundSearchQueryWithContext({
      query: "plutôt entre 200 et 300 euros",
      recentUserMessages: [
        "Cherche les meilleurs micro-ondes compacts du moment",
      ],
    });
    expect(q.toLowerCase()).toMatch(/micro/);
  });

  it("ancre « prix de ces 3 models » sur les entités de la réponse assistant (pas Tesla)", () => {
    const q = groundSearchQueryWithContext({
      query: "C'est quoi le prix de ces 3 models ?",
      recentUserMessages: ["Top 3 GPU RTX pour du gaming"],
      recentAssistantExcerpts: [
        "1. RTX 5090 — haut de gamme\n2. RTX 5080 — milieu\n3. Pour un budget optimisé : La RTX 5070 offre les technologies NVIDIA.",
      ],
    });
    const lower = q.toLowerCase();
    expect(lower).toMatch(/5070|5080|5090/);
    expect(lower).toMatch(/prix/);
    expect(lower).not.toMatch(/tesla|blogtesla/);
  });

  it("n'abandonne pas l'ancrage quand le prior user n'a que des tokens courts (GPU/RTX)", () => {
    const q = groundSearchQueryWithContext({
      query: "Donne clairement les modèles maintenant",
      recentUserMessages: ["Top 3 GPU RTX"],
      force: true,
    });
    expect(q.toLowerCase()).toMatch(/gpu|rtx|top 3/);
  });
});
