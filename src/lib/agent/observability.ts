import { nanoid } from "nanoid";
import { eq } from "drizzle-orm";
import { getDb } from "@/lib/db";
import { agentRuns } from "@/lib/db/schema";
import type {
  AgentPlan,
  AgentRunRecord,
  AgentRunStats,
  AgentRunStatus,
  AgentDepth,
} from "./types";

export function createEmptyStats(planStepsTotal = 0): AgentRunStats {
  return {
    planStepsExecuted: 0,
    planStepsTotal,
    steps: 0,
    toolCalls: 0,
    llmCalls: 0,
    tokens: 0,
    errors: 0,
    durationMs: 0,
    webSearchCount: 0,
  };
}

export class AgentRunTracker {
  readonly id: string;
  readonly conversationId: string;
  readonly depth: AgentDepth;
  readonly model: string;
  readonly startedAt: string;
  plan: AgentPlan;
  stats: AgentRunStats;
  status: AgentRunStatus = "running";
  messageId: string | null = null;
  limitReason: string | null = null;
  private startMs: number;
  private executedStepIds = new Set<string>();

  constructor(params: {
    id: string;
    conversationId: string;
    model: string;
    plan: AgentPlan;
  }) {
    this.id = params.id;
    this.conversationId = params.conversationId;
    this.depth = "standard";
    this.model = params.model;
    this.plan = params.plan;
    this.startedAt = new Date().toISOString();
    this.stats = createEmptyStats(params.plan.steps.length);
    this.startMs = Date.now();
  }

  recordLlmCall() {
    this.stats.llmCalls++;
  }

  recordStepExecuted(stepId: string) {
    this.executedStepIds.add(stepId);
    this.stats.planStepsExecuted = this.executedStepIds.size;
    this.stats.steps = this.stats.planStepsExecuted;
  }

  syncExecutedStepsFromPlan() {
    this.executedStepIds.clear();
    for (const step of this.plan.steps) {
      if (step.status === "done") {
        this.executedStepIds.add(step.id);
      }
    }
    this.stats.planStepsExecuted = this.executedStepIds.size;
    this.stats.steps = this.stats.planStepsExecuted;
    this.stats.planStepsTotal = this.plan.steps.length;
  }

  addTokens(count: number) {
    this.stats.tokens += count;
  }

  recordToolCall(toolName: string) {
    this.stats.toolCalls++;
    if (toolName === "web_search") {
      this.stats.webSearchCount++;
    }
  }

  recordError() {
    this.stats.errors++;
  }

  setPlan(plan: AgentPlan) {
    this.plan = plan;
    this.stats.planStepsTotal = plan.steps.length;
    this.syncExecutedStepsFromPlan();
  }

  finalize(status: AgentRunStatus, limitReason?: string) {
    this.status = status;
    this.limitReason = limitReason ?? null;
    this.stats.durationMs = Date.now() - this.startMs;
    this.syncExecutedStepsFromPlan();
  }

  toRecord(): AgentRunRecord {
    return {
      id: this.id,
      conversationId: this.conversationId,
      messageId: this.messageId,
      depth: this.depth,
      model: this.model,
      startedAt: this.startedAt,
      endedAt: new Date().toISOString(),
      status: this.status,
      plan: this.plan,
      stats: this.stats,
      limitReason: this.limitReason,
    };
  }

  async persist(): Promise<void> {
    const db = getDb();
    const record = this.toRecord();
    const existing = await db.query.agentRuns.findFirst({
      where: eq(agentRuns.id, this.id),
    });

    if (existing) {
      await db
        .update(agentRuns)
        .set({
          messageId: record.messageId,
          endedAt: record.endedAt,
          status: record.status,
          stepsJson: JSON.stringify(record.plan),
          statsJson: JSON.stringify(record.stats),
          limitReason: record.limitReason,
        })
        .where(eq(agentRuns.id, this.id));
    } else {
      await db.insert(agentRuns).values({
        id: this.id,
        conversationId: this.conversationId,
        messageId: record.messageId,
        depth: this.depth,
        model: this.model,
        startedAt: this.startedAt,
        endedAt: record.endedAt,
        status: record.status,
        stepsJson: JSON.stringify(record.plan),
        statsJson: JSON.stringify(record.stats),
        limitReason: record.limitReason,
      });
    }
  }
}

export async function createAgentRunTracker(params: {
  conversationId: string;
  model: string;
  plan: AgentPlan;
}): Promise<AgentRunTracker> {
  const tracker = new AgentRunTracker({
    id: nanoid(),
    ...params,
  });
  await tracker.persist();
  return tracker;
}
