import { describe, expect, it } from "vitest";
import {
  createInitialAgentUiState,
  reduceAgentUiState,
} from "@/components/chat/agent-ui-state";
import type { AgentPlan } from "@/lib/agent/types";

const samplePlan: AgentPlan = {
  steps: [
    { id: "step-1", title: "Découverte", status: "active", actions: [] },
    { id: "step-2", title: "Analyse", status: "pending", actions: [] },
  ],
};

describe("agent-ui-state", () => {
  it("merge le plan sans perdre les statuts avancés", () => {
    let state = createInitialAgentUiState();
    state = reduceAgentUiState(state, { type: "agent_start", runId: "r1" });
    state = reduceAgentUiState(state, { type: "agent_plan", plan: samplePlan });
    state = reduceAgentUiState(state, {
      type: "agent_step_update",
      stepId: "step-1",
      status: "done",
      stepIndex: 0,
      totalSteps: 2,
    });

    state = reduceAgentUiState(state, {
      type: "agent_plan",
      plan: {
        steps: [
          { id: "step-1", title: "Découverte", status: "active", actions: [] },
          { id: "step-2", title: "Analyse", status: "pending", actions: [] },
        ],
      },
    });

    expect(state.plan?.steps[0]?.status).toBe("completed");
  });

  it("finalise les étapes running à agent_done", () => {
    let state = createInitialAgentUiState();
    state = reduceAgentUiState(state, { type: "agent_start", runId: "r1" });
    state = reduceAgentUiState(state, {
      type: "agent_plan",
      plan: {
        steps: [
          {
            id: "step-1",
            title: "Collecte",
            status: "active",
            actions: [{ id: "a1", tool: "web_search", input: {}, status: "done" }],
          },
          { id: "step-2", title: "Synthèse", status: "pending", actions: [] },
        ],
      },
    });

    state = reduceAgentUiState(state, {
      type: "agent_done",
      runId: "r1",
      stats: {
        planStepsExecuted: 1,
        planStepsTotal: 2,
        steps: 1,
        toolCalls: 1,
        webSearchCount: 1,
        llmCalls: 2,
        tokens: 100,
        errors: 0,
        durationMs: 1000,
      },
      plan: {
        steps: [
          {
            id: "step-1",
            title: "Collecte",
            status: "done",
            actions: [{ id: "a1", tool: "web_search", input: {}, status: "done" }],
          },
          { id: "step-2", title: "Synthèse", status: "done", actions: [] },
        ],
      },
      runOutcome: "success" as const,
    });

    expect(state.runStatus).toBe("completed");
    expect(state.plan?.steps[0]?.status).toBe("completed");
    expect(state.plan?.steps[1]?.status).toBe("completed");
    expect(state.phase).toBeNull();
  });

  it("une seule étape running à la fois", () => {
    let state = createInitialAgentUiState();
    state = reduceAgentUiState(state, { type: "agent_start", runId: "r1" });
    state = reduceAgentUiState(state, { type: "agent_plan", plan: samplePlan });
    state = reduceAgentUiState(state, {
      type: "agent_step_update",
      stepId: "step-2",
      status: "active",
      stepIndex: 1,
      totalSteps: 2,
    });

    const running = state.plan?.steps.filter((s) => s.status === "running") ?? [];
    expect(running.length).toBe(1);
    expect(running[0]?.id).toBe("step-2");
    expect(state.plan?.steps[0]?.status).toBe("completed");
  });
});
