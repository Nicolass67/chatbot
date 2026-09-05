export type RuntimeStatus =
  | "OFFLINE"
  | "STARTING"
  | "BOOTING_SERVICES"
  | "LOADING_MODEL"
  | "READY"
  | "BUSY"
  | "STOPPING"
  | "ERROR";

export type ModelLifecyclePhase =
  | "idle"
  | "unloading"
  | "loading"
  | "ready"
  | "error";

export type ModelLifecycleStep = "unloading" | "loading" | "initializing";

export interface ModelRuntimeSnapshot {
  phase: ModelLifecyclePhase;
  preferredModel: string | null;
  loadedModel: string | null;
  targetModel: string | null;
  step?: ModelLifecycleStep;
  message?: string;
  error?: string;
  /** Only when LM Studio exposes real progress — never fabricated. */
  progress?: number;
  pendingRequestCount: number;
}

export interface RuntimeStatusInfo {
  status: RuntimeStatus;
  modelLoaded: string | null;
  message?: string;
  lastActivityAt?: string;
  model?: ModelRuntimeSnapshot;
}

export interface ModelInfo {
  id: string;
  name?: string;
}

export interface MessageContentPart {
  type: "text" | "image_url";
  text?: string;
  image_url?: { url: string };
}

export interface ChatMessage {
  role: "system" | "user" | "assistant" | "tool";
  content: string | MessageContentPart[] | null;
  tool_call_id?: string;
  name?: string;
  tool_calls?: Array<{
    id: string;
    type: "function";
    function: { name: string; arguments: string };
  }>;
}

export interface ToolDefinition {
  type: "function";
  function: {
    name: string;
    description: string;
    parameters: Record<string, unknown>;
  };
}

export interface ChatRequest {
  requestId: string;
  model: string;
  messages: ChatMessage[];
  tools?: ToolDefinition[];
  temperature?: number;
  maxTokens?: number;
  stream?: boolean;
  signal?: AbortSignal;
  /** Resolved reasoning effort id (e.g. none, low, medium) — transmitted when model supports it. */
  reasoningEffort?: string | null;
  /** Ne streamer que delta.content (défaut). Passer false pour inclure reasoning_content. */
  streamContentOnly?: boolean;
}

export interface RuntimeUsage {
  promptTokens?: number;
  completionTokens?: number;
  totalTokens?: number;
  reasoningTokens?: number;
  cachedPromptTokens?: number;
  contextLength?: number;
  tokensPerSecond?: number;
  timeToFirstTokenMs?: number;
  totalGenerationMs?: number;
  source: "lm_studio" | "unavailable";
}

export interface ChatResponse {
  content: string;
  /** Contenu de raisonnement éventuel (ex. Qwen) — pas affiché à l'utilisateur. */
  reasoningContent?: string;
  finishReason?: string | null;
  toolCalls?: Array<{
    id: string;
    name: string;
    arguments: string;
  }>;
  usage?: RuntimeUsage;
}

export interface StreamCallbacks {
  onToken: (token: string) => void;
  onToolCallDelta?: (toolCall: { id?: string; name?: string; arguments?: string }) => void;
  onUsage?: (usage: RuntimeUsage) => void;
  onDone: (result: ChatResponse) => void;
  onError: (error: Error) => void;
}

export interface ModelCapabilities {
  text: boolean;
  vision: boolean;
  toolCalling: boolean;
  reasoning: boolean;
}

export interface ModelCapabilitiesInfo {
  modelId: string;
  capabilities: ModelCapabilities;
  source: "lm_studio_api" | "model_meta" | "heuristic" | "unknown";
  reasoning?: import("./reasoning-types").ReasoningCapabilitiesInfo;
}

export interface LocalAIRuntime {
  status(): Promise<RuntimeStatusInfo>;
  ensureReady(options?: {
    signal?: AbortSignal;
    model?: string;
    contextLength?: number;
  }): Promise<void>;
  getModels(): Promise<ModelInfo[]>;
  chat(request: ChatRequest): Promise<ChatResponse>;
  stream(request: ChatRequest, callbacks: StreamCallbacks): Promise<void>;
  abort(requestId: string): Promise<void>;
}

/** Wake-on-LAN / shutdown / restart — implemented by HostPowerController */
export interface PowerController {
  wake(): Promise<void>;
  shutdown(): Promise<void>;
  getPowerStatus(): Promise<"on" | "off" | "unknown">;
  /** Optional host reboot (Windows). */
  restart?(): Promise<void>;
}

/** V2: Inactivity timeout — types only */
export interface IdleManager {
  recordActivity(source: "chat" | "tool" | "settings"): void;
  getLastActivityAt(): Date | null;
  startMonitoring(config: IdleConfig): void;
  stopMonitoring(): void;
}

export interface IdleConfig {
  idleTimeoutMinutes: number;
  onIdle: () => Promise<void>;
}
