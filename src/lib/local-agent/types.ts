/** V2: Local Agent on PC — types only */

import type {
  AgentPlan,
  AgentRunRecord,
  AgentRunStats,
  ChatMode,
  AgentDepth,
} from "@/lib/agent/types";

export interface QueuedRequest {
  id: string;
  payload: unknown;
  createdAt: string;
  status: "pending" | "processing" | "completed" | "failed";
}

export interface LocalAgent {
  getStatus(): Promise<{ status: string; modelLoaded: string | null }>;
  ensureReady(): Promise<void>;
  handleChatRequest(req: unknown): AsyncIterable<unknown>;
  reportActivity(): void;
  shutdownServices(): Promise<void>;
}

/**
 * V2: When PC is OFFLINE → STARTING → ... → READY,
 * the first user request is queued and auto-forwarded when ready.
 * The request must never be lost because the PC was off.
 */
export interface RequestQueue {
  enqueue(request: QueuedRequest): Promise<void>;
  dequeueReady(): Promise<QueuedRequest | null>;
  getPending(): Promise<QueuedRequest[]>;
}

/** Agent execution types re-exported for V2 compatibility */
export type {
  AgentPlan,
  AgentRunRecord,
  AgentRunStats,
  ChatMode,
  AgentDepth,
};
