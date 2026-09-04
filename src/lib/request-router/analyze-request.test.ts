import { describe, expect, it, vi } from "vitest";
import type { MemoryIntentDecision } from "@/lib/memory/intent-classifier";
import type { RouteDecision } from "@/lib/request-router/types";
import { EMPTY_EMAIL_ROUTE, EMPTY_FILES_ROUTE } from "@/lib/request-router/email-intent";

vi.mock("./route-request", () => ({
  resolveRouteDecision: vi.fn(),
}));

vi.mock("@/lib/memory/intent-classifier-runtime", () => ({
  classifyMemoryIntent: vi.fn(),
}));

import { classifyMemoryIntent } from "@/lib/memory/intent-classifier-runtime";
import { resolveRouteDecision } from "./route-request";
import { analyzeRequest } from "./analyze-request";

const mockRoute: RouteDecision = {
  source: "fast_path",
  knowledge: "static",
  web: {
    enabled: false,
    mode: "none",
    searchType: "none",
    wouldBeUseful: false,
    mandatory: false,
    autoSearch: false,
    searchQuery: "",
    reason: "Salutation",
  },
  email: EMPTY_EMAIL_ROUTE,
    files: EMPTY_FILES_ROUTE,
  research: {},
  execution: { mode: "direct", suggestAgent: false },
  vision: { required: false, reason: "" },
  tools: { allowToolCalling: false, candidates: [] },
  temporal: {
    scope: "unspecified",
    userIntent: "none",
    isTimeSensitive: false,
    referenceYear: null,
    userMentionedYears: [],
    clock: {
      currentDate: "2026-09-01",
      currentDateTime: "01/09/2026 12:00:00",
      timezone: "Europe/Paris",
      currentYear: 2026,
      currentMonth: 9,
    },
  },
  confidence: 0.9,
  reason: "Salutation",
  latencyMs: 1,
};

const mockMemory: MemoryIntentDecision = {
  shouldRemember: true,
  memories: [],
  confidence: 0.92,
  source: "fast_path",
  reason: "Signal explicite",
  latencyMs: 2,
};

describe("analyzeRequest", () => {
  it("lance route et mÃ©moire en parallÃ¨le", async () => {
    vi.mocked(resolveRouteDecision).mockResolvedValue(mockRoute);
    vi.mocked(classifyMemoryIntent).mockResolvedValue(mockMemory);

    const ctx = {
      message: "Retiens que je prÃ©fÃ¨re le franÃ§ais",
      webSearchEnabled: true,
      chatMode: "chat" as const,
      imageCount: 0,
      attachmentCount: 0,
      modelId: "",
    };

    const analysis = await analyzeRequest(ctx, { memoryEnabled: true });

    expect(analysis.route).toEqual(mockRoute);
    expect(analysis.memory).toEqual(mockMemory);
    expect(analysis.latencyMs).toBeGreaterThanOrEqual(0);
    expect(resolveRouteDecision).toHaveBeenCalledOnce();
    expect(classifyMemoryIntent).toHaveBeenCalledOnce();
  });
});


