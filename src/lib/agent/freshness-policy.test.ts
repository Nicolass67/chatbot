import { describe, expect, it } from "vitest";
import type { RouteDecision } from "@/lib/request-router/types";
import { EMPTY_EMAIL_ROUTE, EMPTY_FILES_ROUTE } from "@/lib/request-router/email-intent";
import {
  createFreshnessStateFromRoute,
  evaluateFreshnessForSynthesis,
  updateFreshnessAfterWebSearch,
} from "./freshness-policy";
import { createResearchFlowStateFromRoute } from "./research-flow";

function baseRoute(overrides: Partial<RouteDecision> = {}): RouteDecision {
  return {
    knowledge: "current",
    web: {
      enabled: true,
      mode: "required",
      searchType: "single",
      wouldBeUseful: true,
      mandatory: true,
      autoSearch: true,
      searchQuery: "test query",
      reason: "test",
    },
    email: EMPTY_EMAIL_ROUTE,
    files: EMPTY_FILES_ROUTE,
    research: {},
    execution: { mode: "tool", suggestAgent: false },
    vision: { required: false, reason: "" },
    tools: { allowToolCalling: true, candidates: ["web_search"] },
    temporal: {
      clock: {
        currentDate: "2026-09-01",
        currentDateTime: "01/09/2026",
        timezone: "Europe/Paris",
        currentYear: 2026,
        currentMonth: 9,
      },
      scope: "current",
      referenceYear: null,
      userIntent: "information actuelle",
      isTimeSensitive: true,
      userMentionedYears: [],
    },
    confidence: 0.9,
    source: "fallback_conservative",
    reason: "test",
    latencyMs: 1,
    ...overrides,
  };
}

describe("createFreshnessStateFromRoute", () => {
  it("web required + current → fresh required", () => {
    const state = createFreshnessStateFromRoute(baseRoute(), true);
    expect(state.requiresFreshWebData).toBe(true);
    expect(state.status).toBe("required");
  });

  it("static knowledge → not required", () => {
    const state = createFreshnessStateFromRoute(
      baseRoute({
        knowledge: "static",
        web: {
          ...baseRoute().web,
          mode: "none",
          searchType: "none",
          mandatory: false,
        },
      }),
      true
    );
    expect(state.requiresFreshWebData).toBe(false);
    expect(state.status).toBe("not_required");
  });

  it("web disabled in settings → failed", () => {
    const state = createFreshnessStateFromRoute(baseRoute(), false);
    expect(state.status).toBe("failed");
    expect(state.blockReason).toMatch(/désactivée/i);
  });
});

describe("updateFreshnessAfterWebSearch", () => {
  it("marque verified avec sources récentes", () => {
    let state = createFreshnessStateFromRoute(baseRoute(), true);
    state = updateFreshnessAfterWebSearch(state, {
      success: true,
      usableResultCount: 2,
      sources: [
        {
          title: "Donnée récente",
          url: "https://example.com/a",
          domain: "example.com",
          snippet: "Valeur actuelle",
          publishedAt: new Date().toISOString(),
        },
      ],
      route: baseRoute(),
    });
    expect(state.status).toBe("verified");
    expect(state.freshSourceCount).toBeGreaterThan(0);
  });
});

describe("evaluateFreshnessForSynthesis", () => {
  it("bloque la synthèse sans recherche Web", () => {
    const route = baseRoute();
    const freshness = createFreshnessStateFromRoute(route, true);
    const research = createResearchFlowStateFromRoute(route, "objectif");

    const gate = evaluateFreshnessForSynthesis(freshness, {
      route,
      researchState: research,
      webSearchCount: 0,
      collectedSources: [],
    });

    expect(gate.allowLlmSynthesis).toBe(false);
    expect(gate.forceHonestResponse).toBe(true);
  });

  it("bloque si Web désactivé pour demande actuelle", () => {
    const route = baseRoute();
    const freshness = createFreshnessStateFromRoute(route, false);
    const gate = evaluateFreshnessForSynthesis(freshness, {
      route,
      researchState: createResearchFlowStateFromRoute(route, "objectif"),
      webSearchCount: 0,
      collectedSources: [],
    });
    expect(gate.allowLlmSynthesis).toBe(false);
  });
});
