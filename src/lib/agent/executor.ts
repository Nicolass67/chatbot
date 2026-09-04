import { nanoid } from "nanoid";
import { getDb } from "@/lib/db";
import { toolCalls } from "@/lib/db/schema";
import type { AppSettings } from "@/lib/settings/service";
import { executeToolWithPolicy } from "@/lib/tools/execute-with-policy";
import { summarizeEmailToolResult } from "@/lib/tools/email/summarize";
import {
  getEmailDraftForUser,
  toEmailDraftPreview,
} from "@/lib/email/draft";
import type { SearchResult, ToolContext, WebSearchOutput } from "@/lib/tools/types";
import {
  buildWebSearchTemporalInput,
  type TemporalContext,
} from "./temporal";
import type { SearchQueryCache } from "./search-dedup";
import { logSearchDedup } from "./research-flow";
import { logWebSearchDebug } from "@/lib/tools/web-search/debug";
import {
  getPrimaryProviderLabel,
} from "@/lib/tools/web-search/provider-factory";
import { WebSearchError } from "@/lib/tools/web-search/tool";
import type { WebSearchStatus } from "@/lib/tools/types";
import type {
  AgentPlan,
  PlanStep,
  StepAction,
  ToolCallRequest,
} from "./types";

export interface ExecutorCallbacks {
  onActionStart: (stepId: string, action: StepAction) => void;
  onActionDone: (
    stepId: string,
    actionId: string,
    summary: string,
    sourceCount?: number
  ) => void;
  onToolStart: (tool: string, input: unknown) => void;
  onToolDone: (
    tool: string,
    summary: string,
    sourceCount?: number
  ) => void;
  onDraftPreview?: (
    draft: import("@/lib/email/draft").EmailDraftPreview
  ) => void;
  onFileActionPending?: (payload: {
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
  }) => void;
  onFilesFound?: (files: Array<{
    fileId: string;
    filename: string;
    relativePath?: string;
    rootId?: string;
    sizeBytes?: number;
    mtimeMs?: number;
    extension?: string;
  }>) => void;
  onSources: (sources: SearchResult[]) => void;
}

export interface ExecuteToolCallsInput {
  calls: ToolCallRequest[];
  parallel?: boolean;
  stepId?: string;
  plan: AgentPlan;
  conversationId: string;
  settings: AppSettings;
  signal?: AbortSignal;
  userGoal: string;
  temporalContext: TemporalContext;
  callbacks: ExecutorCallbacks;
  searchCache?: SearchQueryCache;
  userId?: string;
  toolCtxBase?: Omit<ToolContext, "signal">;
}

export interface ToolExecutionResult {
  tool: string;
  input: unknown;
  output: unknown;
  summary: string;
  sources: SearchResult[];
  error?: string;
  durationMs: number;
  deduplicated?: boolean;
}

function findOrCreateStep(plan: AgentPlan, stepId?: string): PlanStep {
  if (stepId) {
    const found = plan.steps.find((s) => s.id === stepId);
    if (found) return found;
  }
  const active = plan.steps.find((s) => s.status === "active");
  if (active) return active;
  const pending = plan.steps.find((s) => s.status === "pending");
  if (pending) {
    pending.status = "active";
    return pending;
  }
  return plan.steps[plan.steps.length - 1];
}

function prepareToolInput(
  call: ToolCallRequest,
  ctx: Omit<ExecuteToolCallsInput, "calls" | "parallel">
): Record<string, unknown> {
  if (call.tool !== "web_search") {
    return call.input;
  }

  const rawQuery =
    typeof call.input.query === "string"
      ? call.input.query
      : JSON.stringify(call.input);

  const temporalInput = buildWebSearchTemporalInput(
    rawQuery,
    ctx.userGoal,
    ctx.temporalContext
  );

  return {
    ...call.input,
    ...temporalInput,
  };
}

async function executeSingleTool(
  call: ToolCallRequest,
  ctx: Omit<ExecuteToolCallsInput, "calls" | "parallel">
): Promise<ToolExecutionResult> {
  const step = findOrCreateStep(ctx.plan, ctx.stepId);
  const preparedInput = prepareToolInput(call, ctx);

  if (call.tool === "web_search" && ctx.searchCache) {
    const query =
      typeof preparedInput.query === "string" ? preparedInput.query : "";
    const cached = ctx.searchCache.findEquivalent(query);
    if (cached) {
      logSearchDedup(query, cached.query);
      logWebSearchDebug({
        query,
        status: "success",
        provider: getPrimaryProviderLabel(),
        resultCount: cached.sourceCount,
        parsedResultCount: cached.sourceCount,
        usableResultCount: cached.sourceCount,
        deduplicated: true,
      });
      return {
        tool: call.tool,
        input: preparedInput,
        output: cached.output,
        summary: `[Réutilisé] ${cached.resultSummary}`,
        sources: cached.sources,
        durationMs: 0,
        deduplicated: true,
      };
    }
  }

  const actionId = nanoid();
  const action: StepAction = {
    id: actionId,
    tool: call.tool,
    input: preparedInput,
    status: "running",
    webSearchProvider:
      call.tool === "web_search" ? getPrimaryProviderLabel() : undefined,
  };
  step.actions.push(action);
  ctx.callbacks.onActionStart(step.id, action);
  ctx.callbacks.onToolStart(call.tool, preparedInput);

  const start = Date.now();
  const toolCallId = nanoid();
  const db = getDb();

  try {
    if (ctx.signal?.aborted) {
      throw new DOMException("Aborted", "AbortError");
    }

    const result = await executeToolWithPolicy(call.tool, preparedInput, {
      ...(ctx.toolCtxBase ?? {
        settings: ctx.settings,
        conversationId: ctx.conversationId,
        runtimeLocation: "local" as const,
        userId: ctx.userId,
      }),
      signal:
        ctx.signal ??
        AbortSignal.timeout(ctx.settings.webSearchTimeoutMs + 5000),
    });

    const durationMs = Date.now() - start;
    let summary = call.tool;
    let sources: SearchResult[] = [];

    if (call.tool === "web_search") {
      const webResult = result as WebSearchOutput;
      sources = webResult.results;
      const providerLabel =
        webResult.provider === "searxng"
          ? "SearXNG"
          : webResult.provider === "brave"
            ? "Brave"
            : webResult.provider === "duckduckgo"
              ? "DuckDuckGo"
              : getPrimaryProviderLabel();

      action.webSearchProvider = providerLabel;
      action.webSearchStatus = webResult.status;

      if (webResult.status === "no_results") {
        summary = `${providerLabel} · "${webResult.query}" — aucune source trouvée`;
      } else {
        summary = `${providerLabel} · "${webResult.query}" — ${webResult.results.length} source(s)`;
      }

      ctx.callbacks.onSources(webResult.results);
      ctx.callbacks.onToolDone(
        call.tool,
        providerLabel,
        webResult.results.length
      );
      ctx.searchCache?.store(
        webResult.query,
        summary,
        webResult.results.length,
        webResult.results,
        result
      );
    } else if (call.tool.startsWith("email_")) {
      summary = summarizeEmailToolResult(call.tool, result);
      ctx.callbacks.onToolDone(call.tool, summary);
      if (
        call.tool === "email_create_draft" &&
        result &&
        typeof result === "object" &&
        "draftId" in result
      ) {
        const draftId = (result as { draftId?: string }).draftId;
        if (draftId) {
          const draft = await getEmailDraftForUser(
            draftId,
            ctx.toolCtxBase?.userId ?? ctx.userId ?? "local"
          );
          if (draft) {
            ctx.callbacks.onDraftPreview?.(await toEmailDraftPreview(draft));
          }
        }
      }
    } else if (
      call.tool === "file_create_directory" ||
      call.tool === "file_rename" ||
      call.tool === "file_move"
    ) {
      const pending = result as {
        status?: string;
        actionId?: string;
        confirmationToken?: string;
        expiresAt?: string;
        payload?: {
          op?: "create_directory" | "rename_file" | "move_file";
          sourceRelativePath?: string;
          destRootId?: string;
          destRelativePath?: string;
        };
        notice?: string;
      };
      summary =
        pending.status === "pending_confirmation"
          ? "Action fichiers en attente de confirmation"
          : call.tool;
      ctx.callbacks.onToolDone(call.tool, summary);
      if (
        pending.status === "pending_confirmation" &&
        pending.actionId &&
        pending.confirmationToken &&
        pending.expiresAt &&
        pending.payload?.op &&
        pending.payload.destRootId &&
        pending.payload.destRelativePath
      ) {
        ctx.callbacks.onFileActionPending?.({
          actionId: pending.actionId,
          confirmationToken: pending.confirmationToken,
          expiresAt: pending.expiresAt,
          op: pending.payload.op,
          payload: {
            sourceRelativePath: pending.payload.sourceRelativePath,
            destRootId: pending.payload.destRootId,
            destRelativePath: pending.payload.destRelativePath,
          },
          notice: pending.notice,
        });
      }
    } else if (call.tool === "file_search" || call.tool === "file_list") {
      const payload = result as {
        results?: Array<Record<string, unknown>>;
        entries?: Array<Record<string, unknown>>;
      };
      const raw = payload.results ?? payload.entries ?? [];
      const files = raw
        .map((r) => ({
          fileId: String(r.fileId ?? ""),
          filename: String(r.filename ?? r.name ?? "fichier"),
          relativePath:
            typeof r.relativePath === "string" ? r.relativePath : undefined,
          rootId: typeof r.rootId === "string" ? r.rootId : undefined,
          sizeBytes: typeof r.sizeBytes === "number" ? r.sizeBytes : undefined,
          mtimeMs: typeof r.mtimeMs === "number" ? r.mtimeMs : undefined,
          extension: typeof r.extension === "string" ? r.extension : undefined,
        }))
        .filter((f) => f.fileId.length > 0)
        .slice(0, 8);
      summary =
        files.length > 0
          ? `${files.length} fichier(s) trouvé(s)`
          : call.tool === "file_search"
            ? "Aucun fichier trouvé"
            : call.tool;
      ctx.callbacks.onToolDone(call.tool, summary, files.length);
      if (files.length > 0) {
        ctx.callbacks.onFilesFound?.(files);
      }
    } else {
      ctx.callbacks.onToolDone(call.tool, summary);
    }

    action.status = "done";
    action.summary = summary;
    action.sourceCount = sources.length;
    action.durationMs = durationMs;
    ctx.callbacks.onActionDone(step.id, actionId, summary, sources.length);

    await db.insert(toolCalls).values({
      id: toolCallId,
      conversationId: ctx.conversationId,
      toolName: call.tool,
      input: JSON.stringify(preparedInput),
      output: JSON.stringify(result),
      status: "success",
      durationMs,
    });

    return {
      tool: call.tool,
      input: preparedInput,
      output: result,
      summary,
      sources,
      durationMs,
    };
  } catch (error) {
    const durationMs = Date.now() - start;
    const errMsg = error instanceof Error ? error.message : String(error);
    let webStatus: WebSearchStatus | undefined;
    let providerLabel = getPrimaryProviderLabel();

    if (error instanceof WebSearchError) {
      webStatus = error.status;
      providerLabel =
        error.provider === "searxng"
          ? "SearXNG"
          : error.provider === "brave"
            ? "Brave"
            : error.provider;
    }

    action.status = "error";
    action.error =
      call.tool === "web_search" && webStatus
        ? `${providerLabel} indisponible`
        : errMsg;
    action.webSearchProvider =
      call.tool === "web_search" ? providerLabel : undefined;
    action.webSearchStatus = webStatus ?? "provider_error";
    action.durationMs = durationMs;
    ctx.callbacks.onActionDone(step.id, actionId, action.error ?? errMsg);
    ctx.callbacks.onToolDone(call.tool, action.error ?? `Erreur: ${errMsg}`);

    await db.insert(toolCalls).values({
      id: toolCallId,
      conversationId: ctx.conversationId,
      toolName: call.tool,
      input: JSON.stringify(preparedInput),
      output: "",
      status: "error",
      error: errMsg,
      durationMs,
    });

    return {
      tool: call.tool,
      input: preparedInput,
      output: { error: errMsg, status: webStatus },
      summary: `Erreur: ${errMsg}`,
      sources: [],
      error: errMsg,
      durationMs,
    };
  }
}

export async function executeToolCalls(
  input: ExecuteToolCallsInput
): Promise<ToolExecutionResult[]> {
  const ctx = {
    stepId: input.stepId,
    plan: input.plan,
    conversationId: input.conversationId,
    settings: input.settings,
    signal: input.signal,
    userGoal: input.userGoal,
    temporalContext: input.temporalContext,
    callbacks: input.callbacks,
    searchCache: input.searchCache,
    userId: input.userId,
    toolCtxBase: input.toolCtxBase,
  };

  const useParallel =
    input.calls.length > 1 && (input.parallel ?? true);

  if (useParallel) {
    if (input.signal?.aborted) {
      throw new DOMException("Aborted", "AbortError");
    }
    const results = await Promise.all(
      input.calls.map((call) => executeSingleTool(call, ctx))
    );
    return results;
  }

  const results: ToolExecutionResult[] = [];
  for (const call of input.calls) {
    if (input.signal?.aborted) {
      throw new DOMException("Aborted", "AbortError");
    }
    results.push(await executeSingleTool(call, ctx));
  }
  return results;
}
