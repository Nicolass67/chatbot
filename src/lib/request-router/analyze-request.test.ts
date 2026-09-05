import { describe, expect, it, vi } from "vitest";
import type { RouteDecision } from "@/lib/request-router/types";

vi.mock("./route-request", () => ({
  resolveRouteDecision: vi.fn(),
}));

vi.mock("./objective-context", () => ({
  buildObjectiveContext: vi.fn(() => ({})),
}));

import { resolveRouteDecision } from "./route-request";
import { analyzeRequest } from "./analyze-request";

describe("analyzeRequest", () => {
  it("ne classifie plus la mémoire en pré-stream (différé au post-processeur)", async () => {
    const mockRoute = { confidence: 0.9, reason: "Salutation" } as RouteDecision;
    vi.mocked(resolveRouteDecision).mockResolvedValue(mockRoute);

    const analysis = await analyzeRequest(
      {
        message: "Retiens que je préfère le français",
        webSearchEnabled: true,
        chatMode: "chat",
        imageCount: 0,
        attachmentCount: 0,
        modelId: "",
      } as never,
      { memoryEnabled: true }
    );

    expect(analysis.route).toEqual(mockRoute);
    expect(analysis.memory.shouldRemember).toBe(false);
    expect(analysis.memory.source).toBe("none");
    expect(analysis.memory.reason).toBe("deferred_to_post_processor");
    expect(analysis.latencyMs).toBeGreaterThanOrEqual(0);
    expect(resolveRouteDecision).toHaveBeenCalledOnce();
  });
});
