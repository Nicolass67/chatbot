import { describe, expect, it } from "vitest";
import {
  groundSearchQueryWithContext,
  isFollowUpTurn,
  priorUserMessages,
} from "./conversation-continuity";

describe("conversation continuity", () => {
  it("détecte le follow-up aspirateurs / modèles", () => {
    expect(
      isFollowUpTurn("Donne clairement 5 modèles maintenant", true)
    ).toBe(true);
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

  it("exclut le message courant des priors", () => {
    expect(
      priorUserMessages(["Aspirateurs", "Donne 5 modèles"], "Donne 5 modèles")
    ).toEqual(["Aspirateurs"]);
  });
});
