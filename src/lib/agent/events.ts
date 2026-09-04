import type { EmailDraftPreview } from "@/lib/email/draft";
import type { ContextSnapshot } from "@/lib/context/builder";
import type { ActiveContextHint } from "@/lib/context/active-context";
import type { ContextDebugTrace } from "@/lib/context/debug-trace";
import type { MemoryIntentDecision } from "@/lib/memory/intent-classifier";
import type { SavedMemoryItem } from "@/lib/memory/saved-memory";
import type { RouteDecision } from "@/lib/request-router";
import type { RuntimeUsage } from "@/lib/runtime/types";
import type { SearchResult } from "@/lib/tools/types";
import type {
  AgentPlan,
  AgentRunStats,
  StepAction,
  StepStatus,
  AgentPhase,
} from "./types";

export type OrchestratorEvent =
  | { type: "runtime_status"; status: string; message?: string }
  | { type: "route_decision"; decision: RouteDecision }
  | { type: "memory_intent"; decision: MemoryIntentDecision }
  | { type: "memory_saved"; messageId: string; memories: SavedMemoryItem[] }
  | { type: "context_snapshot"; snapshot: ContextSnapshot }
  /** Dev/debug only — emitted when CONTEXT_DEBUG=1 or NODE_ENV=development */
  | { type: "context_debug"; trace: ContextDebugTrace }
  | { type: "generation_usage"; usage: RuntimeUsage }
  | { type: "token"; content: string }
  | { type: "tool_start"; tool: string; input: unknown }
  | { type: "tool_done"; tool: string; summary: string; sourceCount?: number }
  | { type: "draft_preview"; draft: EmailDraftPreview }
  | {
      type: "mail_handoff";
      intent: import("@/lib/request-router/types").EmailIntent;
      reason: string;
      query?: string;
      threadId?: string;
      label?: string;
      /** @deprecated Web path dérivé — clients doivent préférer les IDs */
      url?: string;
    }
  | {
      type: "files_handoff";
      intent: import("@/lib/request-router/types").FileIntent;
      reason: string;
      query?: string;
      rootId?: string;
      /** @deprecated Web path dérivé — clients doivent préférer les IDs */
      url?: string;
    }
  | {
      type: "file_action_pending";
      actionId: string;
      confirmationToken: string;
      expiresAt: string;
      op: "create_directory" | "rename_file" | "move_file";
      payload: {
        sourceRelativePath?: string;
        destRootId: string;
        destRelativePath: string;
      };
      notice?: string;
    }
  | { type: "sources"; sources: SearchResult[] }
  | { type: "assistant_start"; messageId: string }
  | { type: "assistant_discard"; messageId: string }
  | { type: "done"; messageId: string }
  | { type: "conversation_title"; title: string }
  | { type: "error"; message: string; code?: import("@/lib/http/api-error").ApiErrorCode }
  | { type: "agent_start"; runId: string }
  | { type: "agent_plan"; plan: AgentPlan }
  | {
      type: "agent_step_update";
      stepId: string;
      status: StepStatus;
      stepIndex: number;
      totalSteps: number;
    }
  | { type: "agent_action_start"; stepId: string; action: StepAction }
  | {
      type: "agent_action_done";
      stepId: string;
      actionId: string;
      summary: string;
      sourceCount?: number;
    }
  | {
      type: "agent_status";
      phase: AgentPhase;
      currentStepTitle?: string;
      stepIndex?: number;
      totalSteps?: number;
    }
  | { type: "agent_limit_reached"; reason: string }
  | {
      type: "agent_done";
      runId: string;
      stats: AgentRunStats;
      plan?: AgentPlan;
      stopReason?: string;
      runOutcome?: import("./types").AgentRunOutcome;
    };

export interface ChatOrchestratorInput {
  conversationId: string;
  userContent: string;
  userId?: string;
  attachmentIds?: string[];
  signal?: AbortSignal;
  regenerate?: boolean;
  editMessageId?: string;
  mode?: "chat" | "agent";
  /** Client hint only — server resolves + authorizes (never trust as auth). */
  activeContext?: ActiveContextHint;
  onEvent: (event: OrchestratorEvent) => void;
}
