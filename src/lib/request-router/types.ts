import type { TemporalContext } from "@/lib/agent/temporal";
import type { RuntimeClock } from "@/lib/runtime/clock";
import type { ModelCapabilities } from "@/lib/runtime/types";

export type KnowledgeNeed = "static" | "current" | "unknown";

export type WebMode = "none" | "optional" | "required";

export type WebSearchType = "none" | "single" | "research";

export type ExecutionMode = "direct" | "tool" | "research" | "agent";

export type RouteSource =
  | "fast_path"
  | "llm_classifier"
  | "fallback_conservative";

export type EmailIntent =
  | "none"
  | "list"
  | "search"
  | "read_thread"
  | "analyze"
  | "draft";

export type FileIntent =
  | "none"
  | "search"
  | "list"
  | "read"
  | "analyze"
  | "organize";

/** @deprecated Utiliser WebMode + WebSearchType */
export type WebRouteMode = WebMode | "research";

export interface RouteDecision {
  knowledge: KnowledgeNeed;
  web: {
    enabled: boolean;
    mode: WebMode;
    searchType: WebSearchType;
    wouldBeUseful: boolean;
    mandatory: boolean;
    autoSearch: boolean;
    searchQuery: string;
    reason: string;
  };
  email: {
    enabled: boolean;
    wouldBeUseful: boolean;
    intent: EmailIntent;
    suggestedTools: string[];
    searchQuery?: string;
    reason: string;
  };
  files: {
    enabled: boolean;
    wouldBeUseful: boolean;
    intent: FileIntent;
    suggestedTools: string[];
    searchQuery?: string;
    reason: string;
  };
  research: {
    objective?: string;
  };
  execution: {
    mode: ExecutionMode;
    suggestAgent: boolean;
  };
  vision: {
    required: boolean;
    reason: string;
  };
  tools: {
    allowToolCalling: boolean;
    candidates: string[];
  };
  temporal: TemporalContext;
  confidence: number;
  source: RouteSource;
  reason: string;
  latencyMs: number;
}

export interface RequestContext {
  message: string;
  webSearchEnabled: boolean;
  emailEnabled?: boolean;
  emailConnected?: boolean;
  filesEnabled?: boolean;
  filesConfigured?: boolean;
  chatMode: "chat" | "agent";
  imageCount: number;
  attachmentCount: number;
  modelId: string;
  runtime?: import("@/lib/runtime/types").LocalAIRuntime;
  recentUserMessages?: string[];
  clock?: RuntimeClock;
  signal?: AbortSignal;
  modelCapabilities?: ModelCapabilities;
}

export interface ObjectiveContext {
  clock: RuntimeClock;
  temporal: TemporalContext;
  message: string;
  trimmedMessage: string;
  webSearchEnabled: boolean;
  chatMode: "chat" | "agent";
  imageCount: number;
  attachmentCount: number;
  hasAttachments: boolean;
  modelId: string;
  modelCapabilities: ModelCapabilities;
  recentUserMessages: string[];
  conversationalContext?: string;
  explicitWebCommand: boolean;
  conversationalSkip: boolean;
  emailEnabled: boolean;
  emailConnected: boolean;
  filesEnabled: boolean;
  filesConfigured: boolean;
}

export interface SemanticClassification {
  knowledge: KnowledgeNeed;
  web: {
    mode: WebMode;
    searchType: WebSearchType;
    searchQuery?: string;
  };
  email?: {
    intent: EmailIntent;
    searchQuery?: string;
  };
  files?: {
    intent: FileIntent;
    searchQuery?: string;
  };
  research?: {
    objective?: string;
  };
  execution: ExecutionMode;
  vision: { required: boolean };
  tools: { allowToolCalling: boolean };
  confidence: number;
  reason: string;
}

export interface FastPathResult {
  hit: boolean;
  classification?: SemanticClassification;
  confidence?: number;
  reason?: string;
}

export interface EvaluationCase {
  id: string;
  message: string;
  recentUserMessages?: string[];
  imageCount?: number;
  webSearchEnabled?: boolean;
  emailEnabled?: boolean;
  emailConnected?: boolean;
  chatMode?: "chat" | "agent";
  expected: {
    webMode: WebMode;
    searchType?: WebSearchType;
    knowledge?: KnowledgeNeed;
    vision?: boolean;
    execution?: ExecutionMode;
    emailIntent?: EmailIntent;
    emailWouldBeUseful?: boolean;
  };
  mockClassification?: SemanticClassification;
}

