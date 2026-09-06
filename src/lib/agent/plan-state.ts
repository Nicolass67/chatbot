import type { OrchestratorEvent } from "./events";
import type { AgentPlan, StepStatus } from "./types";

/** Applique un changement de statut et émet un événement pour chaque étape modifiée. */
export function applyStepStatusChange(
  plan: AgentPlan,
  stepId: string,
  status: StepStatus,
  onEvent?: (event: OrchestratorEvent) => void
): void {
  const step = plan.steps.find((s) => s.id === stepId);
  if (!step) return;

  const changes: Array<{ stepId: string; status: StepStatus }> = [];

  if (status === "active") {
    for (const s of plan.steps) {
      if (s.id !== stepId && s.status === "active") {
        s.status = "done";
        changes.push({ stepId: s.id, status: "done" });
      }
    }
  }

  if (step.status !== status) {
    step.status = status;
    changes.push({ stepId, status });
  }

  if (onEvent) {
    for (const change of changes) {
      emitStepUpdate(plan, change.stepId, change.status, onEvent);
    }
  }
}

export function emitStepUpdate(
  plan: AgentPlan,
  stepId: string,
  status: StepStatus,
  onEvent: (event: OrchestratorEvent) => void
): void {
  const stepIndex = plan.steps.findIndex((s) => s.id === stepId);
  if (stepIndex < 0) return;
  onEvent({
    type: "agent_step_update",
    stepId,
    status,
    stepIndex,
    totalSteps: plan.steps.length,
  });
}

/** Au plus une étape active dans le plan émis. */
export function sanitizePlanActiveSteps(plan: AgentPlan): void {
  let seenActive = false;
  for (const step of plan.steps) {
    if (step.status === "active") {
      if (seenActive) {
        step.status = step.actions.length > 0 ? "done" : "pending";
      } else {
        seenActive = true;
      }
    }
  }
}

/**
 * Clôture les étapes en cours à la fin de l'Agent (arrêt partiel, limite, abort).
 * - active + actions → done (réellement exécutée)
 * - active sans actions → pending (jamais exécutée)
 */
export function finalizePlanSteps(plan: AgentPlan): void {
  for (const step of plan.steps) {
    if (step.status !== "active") continue;
    step.status = step.actions.length > 0 ? "done" : "pending";
  }
  for (const step of plan.steps) {
    if (step.status === "pending") {
      step.status = "skipped";
    }
  }
  sanitizePlanActiveSteps(plan);
}

/**
 * Clôture réussie : le travail restant est couvert par la synthèse finale.
 * Toutes les étapes non échouées comptent comme terminées (UX + stats cohérentes).
 */
export function finalizePlanOnSuccess(plan: AgentPlan): void {
  for (const step of plan.steps) {
    if (step.status === "failed") continue;
    if (
      step.status === "active" ||
      step.status === "pending" ||
      step.status === "skipped"
    ) {
      step.status = "done";
    }
  }
  sanitizePlanActiveSteps(plan);
}

/**
 * Clôture le plan après échec Web : première étape bloquante en failed, le reste en skipped.
 */
export function finalizePlanOnWebFailure(
  plan: AgentPlan,
  onEvent?: (event: OrchestratorEvent) => void
): void {
  let failureMarked = false;

  for (const step of plan.steps) {
    if (step.status === "active") {
      const nextStatus: StepStatus =
        step.actions.length > 0 ? "done" : "failed";
      step.status = nextStatus;
      onEvent?.({
        type: "agent_step_update",
        stepId: step.id,
        status: nextStatus,
        stepIndex: plan.steps.findIndex((s) => s.id === step.id),
        totalSteps: plan.steps.length,
      });
      if (nextStatus === "failed") failureMarked = true;
      continue;
    }

    if (step.status === "done" || step.status === "skipped" || step.status === "failed") {
      continue;
    }

    if (step.status === "pending") {
      const nextStatus: StepStatus = failureMarked ? "skipped" : "failed";
      step.status = nextStatus;
      if (nextStatus === "failed") failureMarked = true;
      onEvent?.({
        type: "agent_step_update",
        stepId: step.id,
        status: nextStatus,
        stepIndex: plan.steps.findIndex((s) => s.id === step.id),
        totalSteps: plan.steps.length,
      });
    }
  }

  sanitizePlanActiveSteps(plan);
}

export function cloneAgentPlan(plan: AgentPlan): AgentPlan {
  return {
    steps: plan.steps.map((s) => ({
      ...s,
      actions: s.actions.map((a) => ({ ...a })),
    })),
  };
}

/**
 * Avance le plan vers l’étape `targetIndex` : les précédentes passent en done,
 * la cible devient active. Utile sur le chemin skip-décider (recherche → analyse → synthèse)
 * où le loop n’émettait pas d’entre-deux.
 */
export function progressPlanToStepIndex(
  plan: AgentPlan,
  targetIndex: number,
  onEvent?: (event: OrchestratorEvent) => void
): void {
  if (plan.steps.length === 0) return;
  const idx = Math.max(0, Math.min(targetIndex, plan.steps.length - 1));
  for (let i = 0; i < idx; i++) {
    const step = plan.steps[i];
    if (!step) continue;
    if (step.status === "pending" || step.status === "active") {
      applyStepStatusChange(plan, step.id, "done", onEvent);
    }
  }
  const target = plan.steps[idx];
  if (!target) return;
  if (target.status !== "done" && target.status !== "failed" && target.status !== "skipped") {
    applyStepStatusChange(plan, target.id, "active", onEvent);
  }
}
