import { describe, expect, it } from "vitest";
import { applyToolChannel } from "./tool-channel";
import type { RouteDecision } from "@/lib/request-router/types";

function baseRoute(): RouteDecision {
  return {
    knowledge: "unknown",
    web: {
      enabled: true,
      mode: "none",
      searchType: "none",
      wouldBeUseful: false,
      mandatory: false,
      autoSearch: false,
      searchQuery: "",
      reason: "test",
    },
    email: {
      enabled: true,
      wouldBeUseful: false,
      intent: "none",
      suggestedTools: [],
      reason: "test",
    },
    files: {
      enabled: true,
      wouldBeUseful: true,
      intent: "search",
      suggestedTools: ["file_search"],
      searchQuery: "restaurants",
      reason: "misrouted",
    },
    research: {},
    execution: { mode: "tool", suggestAgent: false },
    vision: { required: false, reason: "n/a" },
    tools: { allowToolCalling: true, candidates: ["file_search"] },
    temporal: {
      scope: "unspecified",
      userIntent: "unspecified",
      isTimeSensitive: false,
      referenceYear: 2026,
      clock: {
        currentDate: "2026-09-06",
        currentYear: 2026,
        timezone: "Europe/Paris",
      },
    },
    confidence: 0.5,
    source: "fallback_conservative",
    reason: "test",
    latencyMs: 0,
  } as unknown as RouteDecision;
}

const caps = {
  webSearchAllowed: true,
  emailConnected: true,
  emailFeatureEnabled: true,
  filesConfigured: true,
  filesFeatureEnabled: true,
};

describe("applyToolChannel", () => {
  it("web → force web_search, coupe files/email", () => {
    const r = applyToolChannel(baseRoute(), "web", caps);
    expect(r.route.web.mode).toBe("required");
    expect(r.route.files.intent).toBe("none");
    expect(r.webSearchEnabled).toBe(true);
    expect(r.fileToolCandidates).toEqual([]);
    expect(r.emailToolCandidates).toEqual([]);
    expect(r.route.tools.candidates).toEqual(["web_search"]);
  });

  it("files → file_search, coupe web", () => {
    const r = applyToolChannel(baseRoute(), "files", caps);
    expect(r.route.web.mode).toBe("none");
    expect(r.route.files.intent).toBe("search");
    expect(r.webSearchEnabled).toBe(false);
    expect(r.fileToolCandidates).toContain("file_search");
    expect(r.emailToolCandidates).toEqual([]);
  });

  it("email → outils mail, coupe web/files", () => {
    const r = applyToolChannel(baseRoute(), "email", caps);
    expect(r.route.web.mode).toBe("none");
    expect(r.route.files.intent).toBe("none");
    expect(r.emailEnabled).toBe(true);
    expect(r.emailToolCandidates).toContain("email_search");
    expect(r.suppressMailHandoff).toBe(true);
  });
});
