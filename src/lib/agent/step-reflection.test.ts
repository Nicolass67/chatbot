import { describe, expect, it } from "vitest";
import {
  applyStepReflection,
  buildDeterministicReflection,
} from "./step-reflection";
import type { AgentExecutionContext } from "./types";
import { clampPlanToExecutableLength } from "./planner";

describe("step-reflection", () => {
  it("chaîne la réflexion précédente dans le résumé déterministe", () => {
    const text = buildDeterministicReflection(
      "Comparer les options",
      "La recherche a trouvé 3 sources prix.",
      [{ tool: "web_search", summary: "3 résultats RTX" }]
    );
    expect(text).toMatch(/Comparer les options/);
    expect(text).toMatch(/3 résultats RTX/);
    expect(text).toMatch(/réflexion précédente|Suite de la réflexion/i);
  });

  it("applique lastReflection sur le contexte d'exécution", () => {
    const ctx = {
      goal: "test",
      plan: { steps: [] },
      observations: [],
      stepCount: 0,
      toolCallCount: 0,
      startedAt: Date.now(),
      errors: [],
      limits: { maxSteps: 12, maxToolCalls: 16, maxExecutionTimeMs: 60_000 },
    } as AgentExecutionContext;
    applyStepReflection(ctx, "step-1", "Recherche", "J'ai collecté 5 sources.");
    expect(ctx.lastReflection).toMatch(/5 sources/);
    expect(ctx.stepReflections).toHaveLength(1);
    expect(ctx.observations.some((o) => o.tool === "step_reflection")).toBe(true);
  });
});

describe("clampPlanToExecutableLength", () => {
  it("coupe un plan à plus de 4 étapes", () => {
    const plan = clampPlanToExecutableLength({
      steps: Array.from({ length: 7 }, (_, i) => ({
        id: `step-${i + 1}`,
        title: i === 6 ? "Synthèse finale" : `Étape ${i + 1}`,
        status: i === 0 ? ("active" as const) : ("pending" as const),
        actions: [],
      })),
    });
    expect(plan.steps.length).toBeLessThanOrEqual(4);
    expect(plan.steps.length).toBeGreaterThanOrEqual(3);
    expect(plan.steps[0]?.status).toBe("active");
  });
});
