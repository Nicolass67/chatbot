import type { AgentPlan, PlanStep } from "./types";

/** Heuristique générique (pas de domaine métier) : étape de synthèse / rédaction. */
export function isLikelySynthesisStep(step: Pick<PlanStep, "title">): boolean {
  const t = step.title.toLowerCase();
  return /synth|r[ée]dig|r[ée]pond|pr[ée]sent|conclu|final|r[ée]sum|r[ée]ponse|recommand|formul/.test(
    t
  );
}

export function isTerminalStepStatus(
  status: PlanStep["status"]
): boolean {
  return status === "done" || status === "skipped" || status === "failed";
}

/** Étapes encore ouvertes hors synthèse (travail d'exécution restant). */
export function getOpenNonSynthesisSteps(plan: AgentPlan): PlanStep[] {
  return plan.steps.filter(
    (s) => !isTerminalStepStatus(s.status) && !isLikelySynthesisStep(s)
  );
}

/**
 * Skip du décidur seulement quand PLUS AUCUNE étape d'exécution n'est ouverte.
 * Avant : `<= 1` sautait l'unique étape « Analyse » après la recherche → faux plan.
 */
export function shouldSkipDeciderForPlan(
  plan: AgentPlan,
  opts: {
    initialSearchDone: boolean;
    collectedSourceCount: number;
    researchRequired: boolean;
  }
): boolean {
  if (!opts.initialSearchDone || opts.collectedSourceCount <= 0) return false;
  if (opts.researchRequired) return false;
  return getOpenNonSynthesisSteps(plan).length === 0;
}

export type FinishPlanGate = {
  allowed: boolean;
  reason?: string;
  openStepIds: string[];
};

/**
 * finish autorisé seulement si plus d'étape d'exécution ouverte sans travail,
 * ou si ces étapes ont déjà des actions (travail fait, statut pas encore avancé).
 */
export function evaluateFinishAgainstPlan(plan: AgentPlan): FinishPlanGate {
  const open = getOpenNonSynthesisSteps(plan);
  const needingWork = open.filter((s) => s.actions.length === 0);
  if (needingWork.length === 0) {
    return { allowed: true, openStepIds: open.map((s) => s.id) };
  }
  return {
    allowed: false,
    openStepIds: needingWork.map((s) => s.id),
    reason: `finish refusé — étape(s) encore ouvertes sans action : ${needingWork
      .map((s) => `"${s.title}" (${s.id})`)
      .join(", ")}. Utilise tool_calls, ou advance_step avec status "skipped"/"done", avant finish.`,
  };
}
