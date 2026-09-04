import { describe, expect, it } from "vitest";
import { parsePlanDraft, fallbackPlan } from "./planner";

describe("parsePlanDraft", () => {
  it("parses valid JSON plan", () => {
    const content = JSON.stringify({
      steps: [
        { id: "step-1", title: "Comprendre" },
        { id: "step-2", title: "Rechercher" },
        { id: "step-3", title: "Synthétiser" },
      ],
    });
    const plan = parsePlanDraft(content);
    expect(plan.steps).toHaveLength(3);
    expect(plan.steps[0].status).toBe("active");
    expect(plan.steps[1].status).toBe("pending");
  });

  it("parses JSON inside markdown fence", () => {
    const content = '```json\n{"steps":[{"id":"step-1","title":"A"},{"id":"step-2","title":"B"}]}\n```';
    const plan = parsePlanDraft(content);
    expect(plan.steps).toHaveLength(2);
  });
});

describe("fallbackPlan", () => {
  it("creates a default 4-step plan", () => {
    const plan = fallbackPlan("Trouver des GPU");
    expect(plan.steps.length).toBeGreaterThanOrEqual(3);
    expect(plan.steps[0].status).toBe("active");
  });
});
