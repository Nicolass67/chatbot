import { describe, expect, it } from "vitest";
import {
  evaluateFinishAgainstPlan,
  getOpenNonSynthesisSteps,
  shouldSkipDeciderForPlan,
} from "./plan-execution";
import type { AgentPlan } from "./types";

function multiStepPlan(
  overrides?: Array<Partial<AgentPlan["steps"][number]>>
): AgentPlan {
  const defaults: AgentPlan["steps"] = [
    {
      id: "step-1",
      title: "Recherche Web",
      status: "done",
      actions: [{ id: "a1", tool: "web_search", input: {}, status: "done" }],
    },
    {
      id: "step-2",
      title: "Identifier les alternatives",
      status: "pending",
      actions: [],
    },
    {
      id: "step-3",
      title: "Comparer les options",
      status: "pending",
      actions: [],
    },
    {
      id: "step-4",
      title: "Synthèse de la réponse",
      status: "pending",
      actions: [],
    },
  ];
  return {
    steps: defaults.map((s, i) => ({ ...s, ...(overrides?.[i] ?? {}) })),
  };
}

describe("plan-execution", () => {
  it("ne skip pas le décidur si plusieurs étapes d'exécution restent ouvertes", () => {
    const plan = multiStepPlan();
    expect(
      shouldSkipDeciderForPlan(plan, {
        initialSearchDone: true,
        collectedSourceCount: 10,
        researchRequired: false,
      })
    ).toBe(false);
    expect(getOpenNonSynthesisSteps(plan).map((s) => s.id)).toEqual([
      "step-2",
      "step-3",
    ]);
  });

  it("ne skip pas le décidur si une étape d'analyse reste ouverte après la recherche", () => {
    const plan = multiStepPlan([
      {},
      { status: "active" },
      { status: "pending" },
      {},
    ]);
    // step-2 + step-3 ouverts hors synthèse → décidur obligatoire
    expect(
      shouldSkipDeciderForPlan(plan, {
        initialSearchDone: true,
        collectedSourceCount: 10,
        researchRequired: false,
      })
    ).toBe(false);
  });

  it("ne skip pas le décidur s'il ne reste qu'une étape d'analyse (cas classique recherche→analyse→synthèse)", () => {
    const plan: AgentPlan = {
      steps: [
        {
          id: "step-1",
          title: "Recherche Web",
          status: "done",
          actions: [{ id: "a1", tool: "web_search", input: {}, status: "done" }],
        },
        {
          id: "step-2",
          title: "Analyser et comparer",
          status: "active",
          actions: [],
        },
        {
          id: "step-3",
          title: "Synthèse de la réponse",
          status: "pending",
          actions: [],
        },
      ],
    };
    expect(
      shouldSkipDeciderForPlan(plan, {
        initialSearchDone: true,
        collectedSourceCount: 8,
        researchRequired: false,
      })
    ).toBe(false);
  });

  it("skip le décidur si seule la synthèse reste ouverte", () => {
    const plan = multiStepPlan([
      {},
      {
        status: "done",
        actions: [{ id: "a2", tool: "web_search", input: {}, status: "done" }],
      },
      { status: "skipped" },
      {},
    ]);
    expect(
      shouldSkipDeciderForPlan(plan, {
        initialSearchDone: true,
        collectedSourceCount: 8,
        researchRequired: false,
      })
    ).toBe(true);
  });

  it("refuse finish tant que des étapes d'exécution n'ont pas d'action", () => {
    const plan = multiStepPlan();
    const gate = evaluateFinishAgainstPlan(plan);
    expect(gate.allowed).toBe(false);
    expect(gate.openStepIds).toEqual(["step-2", "step-3"]);
    expect(gate.reason).toMatch(/finish refusé/i);
  });

  it("autorise finish si les étapes ouvertes ont déjà des actions", () => {
    const plan = multiStepPlan([
      {},
      {
        status: "active",
        actions: [{ id: "a2", tool: "web_search", input: {}, status: "done" }],
      },
      { status: "skipped" },
      {},
    ]);
    expect(evaluateFinishAgainstPlan(plan).allowed).toBe(true);
  });
});
