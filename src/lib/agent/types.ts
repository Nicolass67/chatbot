import { z } from "zod";

export const chatModeSchema = z.enum(["chat", "agent"]);
export type ChatMode = z.infer<typeof chatModeSchema>;

export const agentDepthSchema = z.enum(["fast", "standard", "thorough"]);
export type AgentDepth = z.infer<typeof agentDepthSchema>;

export const stepStatusSchema = z.enum([
  "pending",
  "active",
  "done",
  "skipped",
  "failed",
]);
export type StepStatus = z.infer<typeof stepStatusSchema>;

export const actionStatusSchema = z.enum([
  "pending",
  "running",
  "done",
  "error",
]);
export type ActionStatus = z.infer<typeof actionStatusSchema>;

export interface StepAction {
  id: string;
  tool: string;
  input: unknown;
  status: ActionStatus;
  summary?: string;
  sourceCount?: number;
  durationMs?: number;
  error?: string;
  webSearchProvider?: string;
  webSearchStatus?: import("@/lib/tools/types").WebSearchStatus;
}

export interface PlanStep {
  id: string;
  title: string;
  status: StepStatus;
  actions: StepAction[];
}

export interface AgentPlan {
  steps: PlanStep[];
}

export const planStepDraftSchema = z.object({
  id: z.string().min(1),
  title: z.string().min(1),
});

export const agentPlanDraftSchema = z.object({
  steps: z.array(planStepDraftSchema).min(2).max(8),
});

export type AgentPlanDraft = z.infer<typeof agentPlanDraftSchema>;

export const toolCallRequestSchema = z.object({
  tool: z.string().min(1),
  input: z.record(z.unknown()),
});

export const planStepUpdateSchema = z.object({
  id: z.string().min(1),
  title: z.string().min(1).optional(),
  status: stepStatusSchema.optional(),
});

export const agentDecisionSchema = z.discriminatedUnion("type", [
  z.object({
    type: z.literal("tool_calls"),
    calls: z.array(toolCallRequestSchema).min(1).max(5),
    parallel: z.boolean().optional(),
    stepId: z.string().optional(),
  }),
  z.object({
    type: z.literal("revise_plan"),
    steps: z.array(planStepUpdateSchema).min(1),
    reason: z.string(),
  }),
  z.object({
    type: z.literal("advance_step"),
    stepId: z.string().min(1),
    status: z.enum(["done", "skipped"]),
  }),
  z.object({
    type: z.literal("finish"),
    reason: z.string(),
  }),
]);

export type AgentDecision = z.infer<typeof agentDecisionSchema>;
export type ToolCallRequest = z.infer<typeof toolCallRequestSchema>;

export interface AgentLimits {
  maxSteps: number;
  maxToolCalls: number;
  maxExecutionTimeMs: number;
}

export type AgentRunStatus =
  | "running"
  | "completed"
  | "stopped"
  | "limit_reached"
  | "error";

export type AgentRunOutcome =
  | "success"
  | "web_unavailable"
  | "limit_reached"
  | "stopped"
  | "error";

export interface AgentRunStats {
  /** Étapes du plan réellement exécutées (touchées) */
  planStepsExecuted: number;
  /** Nombre total d'étapes dans le plan */
  planStepsTotal: number;
  /** @deprecated Alias — utiliser planStepsExecuted */
  steps: number;
  toolCalls: number;
  webSearchCount: number;
  llmCalls: number;
  tokens: number;
  errors: number;
  durationMs: number;
}

export interface AgentRunRecord {
  id: string;
  conversationId: string;
  messageId: string | null;
  depth: AgentDepth;
  model: string;
  startedAt: string;
  endedAt: string | null;
  status: AgentRunStatus;
  plan: AgentPlan;
  stats: AgentRunStats;
  limitReason: string | null;
}

export type AgentPhase = "planning" | "executing" | "synthesizing";

export interface AgentObservation {
  stepId?: string;
  tool: string;
  input: unknown;
  output: unknown;
  summary: string;
  timestamp: string;
}

export interface AgentExecutionContext {
  goal: string;
  plan: AgentPlan;
  observations: AgentObservation[];
  stepCount: number;
  toolCallCount: number;
  startedAt: number;
  errors: string[];
  limits: AgentLimits;
  temporalContext?: import("./temporal").TemporalContext;
  routeDecision?: import("@/lib/request-router/types").RouteDecision;
  researchState?: import("./research-flow").ResearchFlowState;
  freshnessState?: import("./freshness-policy").FreshnessState;
  executedQueries?: string[];
}
