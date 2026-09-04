import { getEnv } from "@/lib/config/env";
import { buildReasoningRequestFields } from "@/lib/runtime/reasoning";
import { parseLmStudioUsage } from "@/lib/lm-studio/usage";
import {
  ensureModelManagerInitialized,
  getModelManager,
} from "@/lib/lm-studio/model-manager";
import { getSettings } from "@/lib/settings/service";
import type {
  ChatRequest,
  ChatResponse,
  LocalAIRuntime,
  ModelInfo,
  ModelRuntimeSnapshot,
  RuntimeStatus,
  RuntimeStatusInfo,
  StreamCallbacks,
} from "@/lib/runtime/types";

const abortControllers = new Map<string, AbortController>();

function mergeSignals(...signals: (AbortSignal | undefined)[]): AbortSignal {
  const controller = new AbortController();
  for (const signal of signals) {
    if (!signal) continue;
    if (signal.aborted) {
      controller.abort();
      break;
    }
    signal.addEventListener("abort", () => controller.abort(), { once: true });
  }
  return controller.signal;
}

async function fetchLmStudio(
  path: string,
  options: RequestInit = {}
): Promise<Response> {
  const env = getEnv();
  const url = `${env.LM_STUDIO_BASE_URL.replace(/\/$/, "")}${path}`;
  return fetch(url, {
    ...options,
    headers: {
      Authorization: `Bearer ${env.LM_STUDIO_API_KEY}`,
      "Content-Type": "application/json",
      ...options.headers,
    },
  });
}

export async function lmStudioHealthCheck(): Promise<boolean> {
  try {
    const res = await fetchLmStudio("/models", { signal: AbortSignal.timeout(3000) });
    return res.ok;
  } catch {
    return false;
  }
}

export async function lmStudioGetModels(): Promise<ModelInfo[]> {
  const res = await fetchLmStudio("/models");
  if (!res.ok) {
    throw new Error(`LM Studio models error: ${res.status}`);
  }
  const data = (await res.json()) as { data?: Array<{ id: string }> };
  return (data.data ?? []).map((m) => ({ id: m.id, name: m.id }));
}

function buildCompletionBody(
  request: ChatRequest,
  stream: boolean
): Record<string, unknown> {
  const body: Record<string, unknown> = {
    model: request.model,
    messages: request.messages,
    temperature: request.temperature,
    max_tokens: request.maxTokens,
    stream,
    ...buildReasoningRequestFields(request.reasoningEffort),
  };
  if (request.tools?.length) {
    body.tools = request.tools;
  }
  if (stream) {
    body.stream_options = { include_usage: true };
  }
  return body;
}

export async function lmStudioChat(request: ChatRequest): Promise<ChatResponse> {
  const controller = new AbortController();
  abortControllers.set(request.requestId, controller);

  const combinedSignal = mergeSignals(request.signal, controller.signal);

  try {
    const res = await fetchLmStudio("/chat/completions", {
      method: "POST",
      signal: combinedSignal,
      body: JSON.stringify(buildCompletionBody(request, false)),
    });

    if (!res.ok) {
      const text = await res.text();
      throw new Error(`LM Studio error ${res.status}: ${text}`);
    }

    const data = (await res.json()) as {
      choices?: Array<{
        message?: {
          content?: string | null;
          tool_calls?: Array<{
            id: string;
            function: { name: string; arguments: string };
          }>;
        };
      }>;
      usage?: {
        prompt_tokens?: number;
        completion_tokens?: number;
        total_tokens?: number;
        completion_tokens_details?: { reasoning_tokens?: number };
        prompt_tokens_details?: { cached_tokens?: number };
      };
      stats?: {
        tokens_per_second?: number;
        time_to_first_token?: number;
        generation_time?: number;
      };
      model_info?: { context_length?: number };
    };

    const message = data.choices?.[0]?.message as
      | {
          content?: string | null;
          reasoning_content?: string;
          tool_calls?: Array<{
            id: string;
            function: { name: string; arguments: string };
          }>;
        }
      | undefined;
    const usage = parseLmStudioUsage(data.usage, data.stats, data.model_info);
    const text = message?.content?.trim() ?? "";
    return {
      content: text,
      toolCalls: message?.tool_calls?.map((tc) => ({
        id: tc.id,
        name: tc.function.name,
        arguments: tc.function.arguments,
      })),
      usage,
      ...(typeof message?.reasoning_content === "string" &&
      message.reasoning_content.trim()
        ? { reasoningContent: message.reasoning_content.trim() }
        : {}),
    };
  } finally {
    abortControllers.delete(request.requestId);
  }
}

export async function lmStudioStream(
  request: ChatRequest,
  callbacks: StreamCallbacks
): Promise<void> {
  const controller = new AbortController();
  abortControllers.set(request.requestId, controller);

  const combinedSignal = mergeSignals(request.signal, controller.signal);

  try {
    const res = await fetchLmStudio("/chat/completions", {
      method: "POST",
      signal: combinedSignal,
      body: JSON.stringify(buildCompletionBody(request, true)),
    });

    if (!res.ok) {
      const text = await res.text();
      throw new Error(`LM Studio error ${res.status}: ${text}`);
    }

    if (!res.body) {
      throw new Error("No response body from LM Studio");
    }

    const reader = res.body.getReader();
    const decoder = new TextDecoder();
    let buffer = "";
    let fullContent = "";
    let lastUsage: ReturnType<typeof parseLmStudioUsage>;
    let finishReason: string | null = null;
    const streamStartedAt = Date.now();
    let firstTokenAt: number | undefined;
    const toolCallsMap = new Map<
      number,
      { id: string; name: string; arguments: string }
    >();

    while (true) {
      const { done, value } = await reader.read();
      if (done) break;

      buffer += decoder.decode(value, { stream: true });
      const lines = buffer.split("\n");
      buffer = lines.pop() ?? "";

      for (const line of lines) {
        const trimmed = line.trim();
        if (!trimmed.startsWith("data: ")) continue;
        const payload = trimmed.slice(6);
        if (payload === "[DONE]") continue;

        try {
          const parsed = JSON.parse(payload) as {
            choices?: Array<{
              finish_reason?: string | null;
              delta?: {
                content?: string;
                tool_calls?: Array<{
                  index: number;
                  id?: string;
                  function?: { name?: string; arguments?: string };
                }>;
              };
            }>;
            usage?: {
              prompt_tokens?: number;
              completion_tokens?: number;
              total_tokens?: number;
              completion_tokens_details?: { reasoning_tokens?: number };
              prompt_tokens_details?: { cached_tokens?: number };
            };
            stats?: {
              tokens_per_second?: number;
              time_to_first_token?: number;
              generation_time?: number;
            };
            model_info?: { context_length?: number };
          };

          if (parsed.usage || parsed.stats) {
            lastUsage = parseLmStudioUsage(
              parsed.usage,
              parsed.stats,
              parsed.model_info,
              {
                timeToFirstTokenMs: firstTokenAt
                  ? firstTokenAt - streamStartedAt
                  : undefined,
                totalGenerationMs: Date.now() - streamStartedAt,
              }
            );
            if (lastUsage) callbacks.onUsage?.(lastUsage);
          }

          const choice = parsed.choices?.[0];
          if (choice?.finish_reason) {
            finishReason = choice.finish_reason;
          }

          const delta = choice?.delta;
          // Ne jamais exposer reasoning_content à l'utilisateur sauf demande explicite.
          const token =
            request.streamContentOnly === false
              ? (delta?.content ??
                (delta as { reasoning_content?: string } | undefined)
                  ?.reasoning_content)
              : delta?.content;
          if (token) {
            if (firstTokenAt === undefined) firstTokenAt = Date.now();
            fullContent += token;
            callbacks.onToken(token);
          }

          if (delta?.tool_calls) {
            for (const tc of delta.tool_calls) {
              const existing = toolCallsMap.get(tc.index) ?? {
                id: tc.id ?? "",
                name: "",
                arguments: "",
              };
              if (tc.id) existing.id = tc.id;
              if (tc.function?.name) existing.name = tc.function.name;
              if (tc.function?.arguments)
                existing.arguments += tc.function.arguments;
              toolCallsMap.set(tc.index, existing);
              callbacks.onToolCallDelta?.({
                id: existing.id,
                name: existing.name,
                arguments: existing.arguments,
              });
            }
          }
        } catch {
          // skip malformed SSE chunks
        }
      }
    }

    const toolCalls = Array.from(toolCallsMap.values()).map((tc) => ({
      id: tc.id,
      name: tc.name,
      arguments: tc.arguments,
    }));

    callbacks.onDone({
      content: fullContent,
      finishReason,
      toolCalls: toolCalls.length > 0 ? toolCalls : undefined,
      usage: lastUsage,
    });
  } catch (error) {
    if (error instanceof Error && error.name === "AbortError") {
      callbacks.onDone({ content: "" });
      return;
    }
    callbacks.onError(error instanceof Error ? error : new Error(String(error)));
  } finally {
    abortControllers.delete(request.requestId);
  }
}

export function lmStudioAbort(requestId: string): void {
  abortControllers.get(requestId)?.abort();
  abortControllers.delete(requestId);
}

let lastActivityAt: Date | null = null;
let busy = false;

export function recordRuntimeActivity(): void {
  lastActivityAt = new Date();
}

export function setRuntimeBusy(value: boolean): void {
  busy = value;
}

function mapModelPhaseToRuntimeStatus(
  model: ModelRuntimeSnapshot,
  healthy: boolean,
  isBusy: boolean
): RuntimeStatus {
  if (!healthy) return "ERROR";
  if (isBusy) return "BUSY";
  switch (model.phase) {
    case "unloading":
    case "loading":
      return "LOADING_MODEL";
    case "error":
      return "ERROR";
    case "idle":
      return model.preferredModel ? "LOADING_MODEL" : "READY";
    case "ready":
      return "READY";
    default:
      return "READY";
  }
}

export async function getRuntimeStatus(): Promise<RuntimeStatusInfo> {
  await ensureModelManagerInitialized().catch(() => undefined);

  const healthy = await lmStudioHealthCheck();
  const modelState = getModelManager().getState();
  const status = mapModelPhaseToRuntimeStatus(modelState, healthy, busy);

  return {
    status,
    modelLoaded: modelState.loadedModel,
    message:
      !healthy
        ? "LM Studio inaccessible"
        : modelState.message ?? modelState.error,
    lastActivityAt: lastActivityAt?.toISOString(),
    model: modelState,
  };
}

export function createLmStudioLocalRuntime(): LocalAIRuntime {
  return {
    status: getRuntimeStatus,
    ensureReady: async ({ signal, model, contextLength } = {}) => {
      await ensureModelManagerInitialized();
      const settings = await getSettings();
      const modelKey = model ?? settings.selectedModel;
      if (!modelKey) {
        throw new Error(
          "Aucun modèle sélectionné. Configurez-en un dans Paramètres."
        );
      }
      if (signal?.aborted) throw new Error("Aborted");

      const ctx = contextLength ?? settings.contextLength;
      const mgr = getModelManager();
      mgr.setPreferredModel(modelKey, ctx);

      const readyPromise = mgr.ensureModelReady(modelKey, ctx);
      if (!signal) {
        await readyPromise;
      } else {
        await Promise.race([
          readyPromise,
          new Promise<void>((_, reject) => {
            if (signal.aborted) {
              reject(new Error("Aborted"));
              return;
            }
            signal.addEventListener(
              "abort",
              () => reject(new Error("Aborted")),
              { once: true }
            );
          }),
        ]);
      }

      recordRuntimeActivity();
    },
    getModels: lmStudioGetModels,
    chat: async (request) => {
      recordRuntimeActivity();
      setRuntimeBusy(true);
      try {
        return await lmStudioChat(request);
      } finally {
        setRuntimeBusy(false);
      }
    },
    stream: async (request, callbacks) => {
      recordRuntimeActivity();
      setRuntimeBusy(true);
      try {
        await lmStudioStream(request, callbacks);
      } finally {
        setRuntimeBusy(false);
      }
    },
    abort: async (requestId) => {
      lmStudioAbort(requestId);
    },
  };
}
