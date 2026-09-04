import { describe, expect, it } from "vitest";
import { createEmptyStats, AgentRunTracker } from "./observability";
import type { AgentPlan } from "./types";

describe("AgentRunTracker stats", () => {
  it("compte les étapes exécutées via actions et statuts", () => {
    const plan: AgentPlan = {
      steps: [
        { id: "step-1", title: "A", status: "done", actions: [{ id: "a1", tool: "web_search", input: {}, status: "done" }] },
        { id: "step-2", title: "B", status: "active", actions: [] },
        { id: "step-3", title: "C", status: "pending", actions: [] },
        { id: "step-4", title: "D", status: "pending", actions: [] },
      ],
    };

    const tracker = new AgentRunTracker({
      id: "run-1",
      conversationId: "conv-1",
      model: "test",
      plan,
    });

    tracker.recordStepExecuted("step-2");
    tracker.recordToolCall("web_search");
    tracker.recordLlmCall();
    tracker.recordLlmCall();
    tracker.finalize("completed");

    expect(tracker.stats.planStepsExecuted).toBe(1);
    expect(tracker.stats.planStepsTotal).toBe(4);
    expect(tracker.stats.webSearchCount).toBe(1);
    expect(tracker.stats.llmCalls).toBe(2);
    expect(tracker.stats.toolCalls).toBe(1);
  });

  it("initialise les compteurs séparément", () => {
    const stats = createEmptyStats(5);
    expect(stats.planStepsTotal).toBe(5);
    expect(stats.llmCalls).toBe(0);
    expect(stats.webSearchCount).toBe(0);
  });
});
