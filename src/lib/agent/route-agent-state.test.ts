import { describe, expect, it } from "vitest";
import {
  createFreshnessStateFromRoute,
  createResearchFlowStateFromRoute,
} from "./route-agent-state";
import type { RouteDecision } from "@/lib/request-router/types";
import { EMPTY_EMAIL_ROUTE, EMPTY_FILES_ROUTE } from "@/lib/request-router/email-intent";

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
      searchQuery: "test",
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
      userIntent: "test",
      isTimeSensitive: true,
      userMentionedYears: [],
    },
    confidence: 0.9,
    source: "llm_classifier",
    reason: "test",
    latencyMs: 1,
    ...overrides,
  };
}

describe("createFreshnessStateFromRoute", () => {
  it("current + required â†’ fresh required", () => {
    const state = createFreshnessStateFromRoute(baseRoute(), true);
    expect(state.requiresFreshWebData).toBe(true);
    expect(state.status).toBe("required");
  });

  it("unknown + required â†’ fresh required", () => {
    const state = createFreshnessStateFromRoute(
      baseRoute({ knowledge: "unknown" }),
      true
    );
    expect(state.requiresFreshWebData).toBe(true);
  });

  it("static â†’ not required", () => {
    const state = createFreshnessStateFromRoute(
      baseRoute({
        knowledge: "static",
        web: {
          ...baseRoute().web,
          mode: "none",
          searchType: "none",
          mandatory: false,
          wouldBeUseful: false,
        },
      }),
      true
    );
    expect(state.requiresFreshWebData).toBe(false);
    expect(state.status).toBe("not_required");
  });
});

describe("createResearchFlowStateFromRoute", () => {
  it("research searchType â†’ research required", () => {
    const state = createResearchFlowStateFromRoute(
      baseRoute({
        web: { ...baseRoute().web, searchType: "research" },
      }),
      "Compare X et Y"
    );
    expect(state.required).toBe(true);
  });
});


