import type { OrchestratorEvent } from "@/lib/agent/events";
import type {
  AgentPhase,
  AgentPlan,
  AgentRunStats,
  StepAction,
  StepStatus,
} from "@/lib/agent/types";

export type AgentStepUiStatus =
  | "pending"
  | "running"
  | "completed"
  | "failed"
  | "skipped"
  | "error";

export type AgentRunUiStatus = "idle" | "running" | "completed" | "stopped";

export interface AgentUiStep {
  id: string;
  title: string;
  status: AgentStepUiStatus;
  actions: StepAction[];
  startedAt?: string;
  completedAt?: string;
}

export interface AgentUiPlan {
  steps: AgentUiStep[];
}

export interface AgentUiState {
  plan: AgentUiPlan | null;
  phase: AgentPhase | null;
  runStatus: AgentRunUiStatus;
  stepIndex?: number;
  totalSteps?: number;
  currentStepTitle?: string;
  currentAction: StepAction | null;
  summaryStats: AgentRunStats | null;
  stopReason?: string;
  runOutcome?: import("@/lib/agent/types").AgentRunOutcome;
}

const INITIAL: AgentUiState = {
  plan: null,
  phase: null,
  runStatus: "idle",
  currentAction: null,
  summaryStats: null,
};

const UI_STATUS_RANK: Record<AgentStepUiStatus, number> = {
  pending: 0,
  skipped: 1,
  running: 2,
  failed: 3,
  error: 4,
  completed: 5,
};

const AGENT_UI_DEBUG =
  typeof process !== "undefined" && process.env.NODE_ENV === "development";

function logUiEvent(event: OrchestratorEvent): void {
  if (!AGENT_UI_DEBUG) return;
  if (
    event.type === "agent_step_update" ||
    event.type === "agent_plan" ||
    event.type === "agent_done" ||
    event.type === "agent_status"
  ) {
    console.log(
      "[AGENT UI EVENT]",
      JSON.stringify({
        event: event.type,
        stepId: "stepId" in event ? event.stepId : undefined,
        status: "status" in event ? event.status : undefined,
        phase: "phase" in event ? event.phase : undefined,
      })
    );
  }
}

function logUiStepTransition(
  stepId: string,
  previousStatus: AgentStepUiStatus,
  nextStatus: AgentStepUiStatus
): void {
  if (!AGENT_UI_DEBUG || previousStatus === nextStatus) return;
  console.log(
    "[AGENT UI STATE]",
    JSON.stringify({ stepId, previousStatus, nextStatus })
  );
}

function backendToUiStatus(
  status: StepStatus,
  actions: StepAction[]
): AgentStepUiStatus {
  if (status === "failed") return "failed";
  if (status === "skipped") return "skipped";
  if (status === "active") return "running";
  if (status === "done") return "completed";
  if (actions.some((a) => a.status === "error")) return "error";
  return "pending";
}

function mergeUiStatus(
  current: AgentStepUiStatus,
  incoming: AgentStepUiStatus
): AgentStepUiStatus {
  return UI_STATUS_RANK[incoming] >= UI_STATUS_RANK[current]
    ? incoming
    : current;
}

function normalizePlanStep(
  step: AgentPlan["steps"][number]
): AgentUiStep {
  return {
    id: step.id,
    title: step.title,
    status: backendToUiStatus(step.status, step.actions),
    actions: step.actions.map((a) => ({ ...a })),
  };
}

function mergePlan(
  current: AgentUiPlan | null,
  incoming: AgentPlan
): AgentUiPlan {
  if (!current) {
    return { steps: incoming.steps.map((s) => normalizePlanStep(s)) };
  }

  const existingById = new Map(current.steps.map((s) => [s.id, s]));

  return {
    steps: incoming.steps.map((incomingStep) => {
      const existing = existingById.get(incomingStep.id);
      const normalized = normalizePlanStep(incomingStep);
      if (!existing) return normalized;

      const mergedActions =
        existing.actions.length >= incomingStep.actions.length
          ? existing.actions
          : normalized.actions;

      return {
        ...normalized,
        status: mergeUiStatus(existing.status, normalized.status),
        actions: mergedActions,
        startedAt: existing.startedAt,
        completedAt: existing.completedAt,
      };
    }),
  };
}

function updateStepInPlan(
  plan: AgentUiPlan,
  stepId: string,
  updater: (step: AgentUiStep) => AgentUiStep
): AgentUiPlan {
  return {
    steps: plan.steps.map((s) => (s.id === stepId ? updater(s) : s)),
  };
}

function applyBackendStatus(
  plan: AgentUiPlan,
  stepId: string,
  status: StepStatus
): AgentUiPlan {
  const now = new Date().toISOString();

  if (status === "active") {
    return {
      steps: plan.steps.map((s) => {
        if (s.id === stepId) {
          logUiStepTransition(s.id, s.status, "running");
          return { ...s, status: "running", startedAt: s.startedAt ?? now };
        }
        if (s.status === "running") {
          logUiStepTransition(s.id, s.status, "completed");
          return { ...s, status: "completed", completedAt: now };
        }
        return s;
      }),
    };
  }

  if (status === "done") {
    return updateStepInPlan(plan, stepId, (s) => {
      logUiStepTransition(s.id, s.status, "completed");
      return { ...s, status: "completed", completedAt: s.completedAt ?? now };
    });
  }

  if (status === "failed") {
    return updateStepInPlan(plan, stepId, (s) => {
      logUiStepTransition(s.id, s.status, "failed");
      return { ...s, status: "failed", completedAt: s.completedAt ?? now };
    });
  }

  if (status === "skipped") {
    return updateStepInPlan(plan, stepId, (s) => {
      logUiStepTransition(s.id, s.status, "skipped");
      return { ...s, status: "skipped", completedAt: s.completedAt ?? now };
    });
  }

  return updateStepInPlan(plan, stepId, (s) => {
    logUiStepTransition(s.id, s.status, "pending");
    return { ...s, status: "pending" };
  });
}

function finalizeUiPlan(plan: AgentUiPlan): AgentUiPlan {
  const now = new Date().toISOString();
  return {
    steps: plan.steps.map((s) => {
      if (s.status !== "running") return s;
      if (s.actions.length > 0) {
        logUiStepTransition(s.id, s.status, "completed");
        return { ...s, status: "completed", completedAt: s.completedAt ?? now };
      }
      logUiStepTransition(s.id, s.status, "skipped");
      return { ...s, status: "skipped", completedAt: s.completedAt ?? now };
    }),
  };
}

/** Succès : toutes les étapes non échouées affichent ✓ (aligné sur finalizePlanOnSuccess). */
function finalizeUiPlanOnSuccess(plan: AgentUiPlan): AgentUiPlan {
  const now = new Date().toISOString();
  return {
    steps: plan.steps.map((s) => {
      if (s.status === "failed" || s.status === "error") return s;
      if (s.status === "completed") return s;
      logUiStepTransition(s.id, s.status, "completed");
      return { ...s, status: "completed", completedAt: s.completedAt ?? now };
    }),
  };
}

export type AgentUiReducerAction =
  | OrchestratorEvent
  | { type: "__reset__" };

export function reduceAgentUiState(
  state: AgentUiState,
  action: AgentUiReducerAction
): AgentUiState {
  if (action.type === "__reset__") return INITIAL;

  logUiEvent(action);

  switch (action.type) {
    case "agent_start":
      return {
        ...INITIAL,
        runStatus: "running",
        phase: "planning",
      };

    case "agent_plan":
      return {
        ...state,
        plan: mergePlan(state.plan, action.plan),
        totalSteps: action.plan.steps.length,
      };

    case "agent_step_update":
      if (!state.plan || !action.stepId) return state;
      return {
        ...state,
        plan: applyBackendStatus(state.plan, action.stepId, action.status),
        stepIndex: action.stepIndex,
        totalSteps: action.totalSteps,
      };

    case "agent_action_start":
      if (!state.plan || !action.stepId || !action.action) return state;
      return {
        ...state,
        currentAction: action.action,
        plan: updateStepInPlan(state.plan, action.stepId, (s) => {
          const actions = s.actions.some((a) => a.id === action.action!.id)
            ? s.actions.map((a) =>
                a.id === action.action!.id ? action.action! : a
              )
            : [...s.actions, action.action!];
          return {
            ...s,
            actions,
            status: s.status === "pending" ? "running" : s.status,
            startedAt: s.startedAt ?? new Date().toISOString(),
          };
        }),
      };

    case "agent_action_done":
      if (!state.plan || !action.stepId) {
        return { ...state, currentAction: null };
      }
      return {
        ...state,
        currentAction: null,
        plan: updateStepInPlan(state.plan, action.stepId, (s) => ({
          ...s,
          actions: s.actions.map((a) =>
            a.id === action.actionId
              ? {
                  ...a,
                  status: "done" as const,
                  summary: action.summary,
                  sourceCount: action.sourceCount,
                }
              : a
          ),
        })),
      };

    case "agent_status":
      return {
        ...state,
        phase: action.phase,
        currentStepTitle: action.currentStepTitle ?? state.currentStepTitle,
        stepIndex: action.stepIndex ?? state.stepIndex,
        totalSteps: action.totalSteps ?? state.totalSteps,
      };

    case "agent_done": {
      const mergedPlan = action.plan
        ? mergePlan(state.plan, action.plan)
        : state.plan;
      const isWebFailure = action.runOutcome === "web_unavailable";
      const normalizedPlan = mergedPlan
        ? isWebFailure
          ? finalizeUiPlan(mergedPlan)
          : finalizeUiPlanOnSuccess(mergedPlan)
        : null;
      return {
        ...state,
        runStatus: isWebFailure ? "stopped" : "completed",
        phase: null,
        currentAction: null,
        summaryStats: action.stats,
        stopReason: action.stopReason,
        runOutcome: action.runOutcome,
        plan: normalizedPlan,
      };
    }

    default:
      return state;
  }
}

export function createInitialAgentUiState(): AgentUiState {
  return INITIAL;
}
