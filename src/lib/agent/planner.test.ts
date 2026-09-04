import { describe, expect, it } from "vitest";
import {
  parsePlanDraft,
  fallbackPlan,
  sanitizeAgentPlan,
  goalAwareFallbackSteps,
} from "./planner";

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
    const content =
      '```json\n{"steps":[{"id":"step-1","title":"A"},{"id":"step-2","title":"B"}]}\n```';
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

describe("goalAwareFallbackSteps", () => {
  it("uses web steps for graphics card shopping, not files", () => {
    const steps = goalAwareFallbackSteps(
      "Trouve la meilleure carte graphique à moins de 1000€ niveau puissance"
    );
    expect(steps[0].title).toMatch(/Recherche web/i);
    expect(steps.map((s) => s.title).join(" ")).not.toMatch(/fichier/i);
  });

  it("uses file steps only for explicit file goals", () => {
    const steps = goalAwareFallbackSteps("Trouve ma carte d'identité PDF");
    expect(steps[0].title).toMatch(/fichier/i);
  });
});

describe("sanitizeAgentPlan", () => {
  it("replaces fileish LLM plan for a product question", () => {
    const bad = {
      steps: [
        {
          id: "step-1",
          title: "Chercher le fichier demandé",
          status: "active" as const,
          actions: [],
        },
        {
          id: "step-2",
          title: "Vérifier le chemin et les droits",
          status: "pending" as const,
          actions: [],
        },
        {
          id: "step-3",
          title: "Présenter le document trouvé",
          status: "pending" as const,
          actions: [],
        },
      ],
    };
    const fixed = sanitizeAgentPlan(
      "Trouve la meilleure carte graphique à moins de 1000€",
      bad
    );
    expect(fixed.steps[0].title).toMatch(/Recherche web/i);
  });
});
