/**
 * Context debug observability (dev / CONTEXT_DEBUG=1 only).
 * Not persisted; no absolute paths; no UI panel in normal app.
 */

export type SelectionReason = {
  id: string;
  selected: boolean;
  score?: number;
  reason: string;
};

export type ContextDebugTrace = {
  version: 1;
  intent?: string;
  routeSummary?: {
    knowledge?: string;
    webMode?: string;
    emailIntent?: string;
    filesIntent?: string;
  };
  plan?: {
    memoryBudget: number;
    historyMode: string;
    personalRelevance: string;
    expandFollowUpQuery: boolean;
    answerContract: string;
  };
  activeContext?: {
    fileId?: string;
    mailThreadId?: string;
    rootId?: string;
    label?: string;
    resolved: boolean;
    ignoredReason?: string;
  };
  history: {
    selectedCount: number;
    excludedCount: number;
    selectedReasons: string[];
    excludedReasons: string[];
  };
  memories: {
    selected: SelectionReason[];
    excluded: SelectionReason[];
  };
  documents?: {
    selectedCount: number;
    reason: string;
  };
  web?: {
    enabled: boolean;
    selectedCount: number;
    reason?: string;
  };
  tools?: string[];
  budgets: {
    memoryBudget: number;
    historyMode: string;
    tokenBudget: number;
  };
  tokens: {
    bySource: Record<string, number>;
    total: number;
  };
  latencyMs: {
    retrieval: number;
    build: number;
    total: number;
  };
  retrievalQuery?: string;
};

export function isContextDebugEnabled(): boolean {
  if (process.env.CONTEXT_DEBUG === "1") return true;
  if (process.env.CONTEXT_DEBUG === "0") return false;
  return process.env.NODE_ENV === "development";
}

export function emptyContextDebugTrace(
  partial?: Partial<ContextDebugTrace>
): ContextDebugTrace {
  return {
    version: 1,
    history: {
      selectedCount: 0,
      excludedCount: 0,
      selectedReasons: [],
      excludedReasons: [],
    },
    memories: { selected: [], excluded: [] },
    budgets: {
      memoryBudget: 0,
      historyMode: "standard",
      tokenBudget: 0,
    },
    tokens: { bySource: {}, total: 0 },
    latencyMs: { retrieval: 0, build: 0, total: 0 },
    ...partial,
  };
}
