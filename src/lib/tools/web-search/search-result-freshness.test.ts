import { describe, expect, it } from "vitest";
import {
  assessResultFreshness,
  assessSearchResultsFreshness,
} from "./search-result-freshness";

const CURRENT_CONTEXT = {
  fetchedAt: new Date("2026-09-01T12:00:00Z"),
  temporalScope: "current" as const,
  currentYear: 2026,
};

describe("assessResultFreshness", () => {
  it("publication récente → fresh sans année dans le titre", () => {
    const assessment = assessResultFreshness(
      {
        title: "Cours actuel",
        url: "https://example.com/x",
        domain: "example.com",
        snippet: "Valeur du jour",
        publishedAt: "2026-08-30T10:00:00Z",
      },
      CURRENT_CONTEXT
    );
    expect(assessment.status).toBe("fresh");
  });

  it("absence de date → unknown (pas stale)", () => {
    const assessment = assessResultFreshness(
      {
        title: "Indice du marché",
        url: "https://example.com/y",
        domain: "example.com",
        snippet: "Dernière cotation disponible",
      },
      CURRENT_CONTEXT
    );
    expect(assessment.status).toBe("unknown");
    expect(assessment.status).not.toBe("stale");
  });

  it("année clairement antérieure → stale", () => {
    const assessment = assessResultFreshness(
      {
        title: "Rapport 2020",
        url: "https://example.com/z",
        domain: "example.com",
        snippet: "Chiffres de 2020",
      },
      CURRENT_CONTEXT
    );
    expect(assessment.status).toBe("stale");
  });
});

describe("assessSearchResultsFreshness", () => {
  it("current : unknown seul reste suffisant", () => {
    const aggregate = assessSearchResultsFreshness(
      [
        {
          title: "Source sans date",
          url: "https://example.com/a",
          domain: "example.com",
          snippet: "Information récente non datée",
        },
      ],
      CURRENT_CONTEXT
    );
    expect(aggregate.sufficientForCurrentKnowledge).toBe(true);
  });

  it("current : uniquement stale → insuffisant", () => {
    const aggregate = assessSearchResultsFreshness(
      [
        {
          title: "Archive 2019",
          url: "https://example.com/old",
          domain: "example.com",
          snippet: "Données de 2019",
        },
      ],
      CURRENT_CONTEXT
    );
    expect(aggregate.sufficientForCurrentKnowledge).toBe(false);
  });
});
