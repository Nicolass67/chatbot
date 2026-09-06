import { describe, expect, it } from "vitest";
import {
  applyStepStatusChange,
  finalizePlanOnSuccess,
  finalizePlanOnWebFailure,
  finalizePlanSteps,
  progressPlanToStepIndex,
  sanitizePlanActiveSteps,
} from "./plan-state";
import type { AgentPlan } from "./types";

function makePlan(): AgentPlan {
  return {
    steps: [
      { id: "step-1", title: "A", status: "active", actions: [{ id: "a1", tool: "web_search", input: {}, status: "done" }] },
      { id: "step-2", title: "B", status: "active", actions: [] },
      { id: "step-3", title: "C", status: "pending", actions: [] },
    ],
  };
}

describe("plan-state", () => {
  it("émet plusieurs événements quand une nouvelle étape devient active", () => {
    const plan = makePlan();
    const events: Array<{ stepId: string; status: string }> = [];
    applyStepStatusChange(plan, "step-3", "active", (e) => {
      if (e.type === "agent_step_update") {
        events.push({ stepId: e.stepId, status: e.status });
      }
    });
    expect(events).toEqual([
      { stepId: "step-1", status: "done" },
      { stepId: "step-2", status: "done" },
      { stepId: "step-3", status: "active" },
    ]);
  });

  it("finalise les étapes actives avec ou sans actions (arrêt partiel)", () => {
    const plan = makePlan();
    finalizePlanSteps(plan);
    expect(plan.steps[0]?.status).toBe("done");
    expect(plan.steps[1]?.status).toBe("skipped");
    expect(plan.steps[2]?.status).toBe("skipped");
  });

  it("finalise en succès : toutes les étapes non échouées sont done", () => {
    const plan = makePlan();
    finalizePlanOnSuccess(plan);
    expect(plan.steps.every((s) => s.status === "done")).toBe(true);
  });

  it("ne garde qu'une seule étape active", () => {
    const plan = makePlan();
    sanitizePlanActiveSteps(plan);
    const active = plan.steps.filter((s) => s.status === "active");
    expect(active.length).toBeLessThanOrEqual(1);
  });

  it("finalise le plan après échec Web", () => {
    const plan: AgentPlan = {
      steps: [
        {
          id: "step-1",
          title: "Découverte",
          status: "done",
          actions: [{ id: "a1", tool: "web_search", input: {}, status: "done" }],
        },
        { id: "step-2", title: "Sélection", status: "pending", actions: [] },
        { id: "step-3", title: "Comparaison", status: "pending", actions: [] },
      ],
    };
    finalizePlanOnWebFailure(plan);
    expect(plan.steps[0]?.status).toBe("done");
    expect(plan.steps[1]?.status).toBe("failed");
    expect(plan.steps[2]?.status).toBe("skipped");
  });

  it("progressPlanToStepIndex avance les étapes précédentes", () => {
    const plan: AgentPlan = {
      steps: [
        { id: "step-1", title: "Recherche", status: "active", actions: [] },
        { id: "step-2", title: "Analyse", status: "pending", actions: [] },
        { id: "step-3", title: "Synthèse", status: "pending", actions: [] },
      ],
    };
    const events: Array<{ stepId: string; status: string }> = [];
    progressPlanToStepIndex(plan, 1, (e) => {
      if (e.type === "agent_step_update") {
        events.push({ stepId: e.stepId, status: e.status });
      }
    });
    expect(plan.steps[0]?.status).toBe("done");
    expect(plan.steps[1]?.status).toBe("active");
    expect(plan.steps[2]?.status).toBe("pending");
    expect(events).toEqual([
      { stepId: "step-1", status: "done" },
      { stepId: "step-2", status: "active" },
    ]);
  });
});
