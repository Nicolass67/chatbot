import { groundSearchQueryWithContext } from "@/lib/context/conversation-continuity";
import { nanoid } from "nanoid";
import { eq } from "drizzle-orm";
import { maybeSummarizeConversation } from "@/lib/context/summarizer";
import { maybeGenerateConversationTitle } from "@/lib/conversation/title-generator";
import { getDb } from "@/lib/db";
import { conversations, messageSources, messages } from "@/lib/db/schema";
import { applyMemoryAfterResponse } from "@/lib/memory/apply-intent";
import { emitMemorySaved } from "@/lib/memory/emit-saved";
import type { MemoryIntentDecision } from "@/lib/memory/intent-classifier";
import type { LocalAIRuntime } from "@/lib/runtime/types";
import type { AppSettings } from "@/lib/settings/service";
import { getRegisteredTools } from "@/lib/tools/registry";
import type { ToolContext } from "@/lib/tools/types";
import { formatSearchResultsBlock, capSourcesForSynthesis } from "@/lib/tools/web-search/heuristics";
import { mergeUniqueSources } from "@/lib/tools/web-search/source-dedupe";
import { routeRequest, routeToWebSearchIntent, type RouteDecision } from "@/lib/request-router";
import { evaluateWebSearchAvailability } from "@/lib/tools/web-search/web-search-availability";
import type { ChatMessage, RuntimeUsage } from "@/lib/runtime/types";
import type { SearchResult } from "@/lib/tools/types";
import { resolveAgentLimits } from "./config";
import { buildContextHint } from "./context-builder";
import {
  buildEmailDraftWritingBlock,
} from "@/lib/email/draft";
import { executeToolCalls } from "./executor";
import type { OrchestratorEvent } from "./events";
import {
  createFreshnessStateFromRoute,
  createResearchFlowStateFromRoute,
} from "./route-agent-state";
import {
  buildHonestFailureResponse,
  buildSourceBasedFallbackResponse,
  formatResearchBlockForDecider,
  formatResearchContextForSynthesis,
  logAgentHeader,
  logFinalSummary,
  logResearchQuery,
  markInitialResearchSearchDone,
  recordWebSearchOutcome,
  validateBeforeSynthesis,
  type ResearchFlowState,
} from "./research-flow";
import {
  evaluateFreshnessForSynthesis,
  formatFreshnessBlock,
  markFreshnessFailed,
  updateFreshnessAfterWebSearch,
  type FreshnessState,
} from "./freshness-policy";
import { createAgentRunTracker, type AgentRunTracker } from "./observability";
import { sanitizeToolStartPayload } from "@/lib/observability/sse-sanitize";
import { createAgentPlan } from "./planner";
import {
  applyStepStatusChange,
  cloneAgentPlan,
  finalizePlanOnWebFailure,
  finalizePlanOnSuccess,
  finalizePlanSteps,
  sanitizePlanActiveSteps,
} from "./plan-state";
import { SearchQueryCache } from "./search-dedup";
import { WebSearchTracker, resolveSourceBudget, type WebSearchStopDecision } from "./web-search-tracker";
import {
  buildDeciderSystemPrompt,
  buildDeciderUserPrompt,
  buildSynthesisSystemPrompt,
  formatObservationsForSynthesis,
} from "./prompts";
import {
  buildSynthesisContinuationMessages,
  looksTruncated,
  resolveSynthesisMaxTokens,
} from "./synthesis";
import {
  logTemporalSearchDebug,
  resolveEffectiveScope,
} from "./temporal";
import {
  assessSearchResultsFreshness,
  formatFreshnessNotesForSynthesis,
} from "@/lib/tools/web-search/search-result-freshness";
import {
  agentDecisionSchema,
  type AgentDecision,
  type AgentExecutionContext,
  type AgentPlan,
  type AgentObservation,
  type AgentRunOutcome,
  type StepStatus,
} from "./types";

export interface AgentLoopInput {
  conversationId: string;
  userContent: string;
  settings: AppSettings;
  runtime: LocalAIRuntime;
  reasoningEffort: string | null;
  documentContext: string;
  signal?: AbortSignal;
  onEvent: (event: OrchestratorEvent) => void;
  pendingAttachmentNames?: string[];
  routeDecision?: RouteDecision;
  memoryIntent?: MemoryIntentDecision;
  flushInitialMemorySaves?: (messageId: string) => void;
  userId?: string;
  toolCtxBase?: Omit<ToolContext, "signal">;
  emailEnabled?: boolean;
  emailToolCandidates?: string[];
  /** Adresse Gmail connectée — pour brouillons « à moi ». */
  accountEmail?: string | null;
  filesEnabled?: boolean;
  fileToolCandidates?: string[];
  /** Historique court user/assistant pour planning + synthèse. */
  conversationHistory?: string;
  /** Tours utilisateur antérieurs (hors message courant). */
  priorUserMessages?: string[];
}

class RequestIdTracker {
  private ids = new Set<string>();

  register(id: string) {
    this.ids.add(id);
  }

  abortAll(runtime: LocalAIRuntime) {
    for (const id of this.ids) {
      void runtime.abort(id);
    }
    this.ids.clear();
  }
}

function extractJsonFromContent(content: string): unknown {
  const trimmed = content.trim();
  const fenceMatch = trimmed.match(/```(?:json)?\s*([\s\S]*?)```/);
  const jsonStr = fenceMatch ? fenceMatch[1].trim() : trimmed;
  const start = jsonStr.indexOf("{");
  const end = jsonStr.lastIndexOf("}");
  if (start === -1 || end === -1) {
    throw new Error("Réponse sans JSON valide");
  }
  return JSON.parse(jsonStr.slice(start, end + 1));
}

function parseDecision(content: string): AgentDecision | null {
  try {
    const raw = extractJsonFromContent(content);
    return agentDecisionSchema.parse(raw);
  } catch {
    return null;
  }
}

function getActiveStepIndex(plan: AgentPlan): number {
  const activeIdx = plan.steps.findIndex((s) => s.status === "active");
  if (activeIdx >= 0) return activeIdx;
  const pendingIdx = plan.steps.findIndex((s) => s.status === "pending");
  return pendingIdx >= 0 ? pendingIdx : plan.steps.length - 1;
}

function applyPlanRevision(
  plan: AgentPlan,
  updates: Array<{ id: string; title?: string; status?: StepStatus }>
) {
  for (const update of updates) {
    const step = plan.steps.find((s) => s.id === update.id);
    if (step) {
      if (update.title) step.title = update.title;
      if (update.status) step.status = update.status;
    } else if (update.title) {
      plan.steps.push({
        id: update.id,
        title: update.title,
        status: update.status ?? "pending",
        actions: [],
      });
    }
  }
}

function checkLimits(ctx: AgentExecutionContext): string | null {
  const elapsed = Date.now() - ctx.startedAt;
  if (ctx.stepCount >= ctx.limits.maxSteps) {
    return `Limite d'étapes atteinte (${ctx.limits.maxSteps})`;
  }
  if (ctx.toolCallCount >= ctx.limits.maxToolCalls) {
    return `Limite d'appels outils atteinte (${ctx.limits.maxToolCalls})`;
  }
  if (elapsed >= ctx.limits.maxExecutionTimeMs) {
    return `Temps d'exécution maximum atteint (${Math.round(ctx.limits.maxExecutionTimeMs / 1000)}s)`;
  }
  return null;
}

async function runMandatoryRouteWebSearch(
  input: AgentLoopInput,
  plan: AgentPlan,
  route: RouteDecision,
  searchCache: SearchQueryCache,
  collectedSources: SearchResult[],
  onEvent: (event: OrchestratorEvent) => void,
  options?: { stepTitle?: string; perQueryMaxResults?: number }
): Promise<{
  observation: AgentObservation | null;
  toolResult: import("./executor").ToolExecutionResult | null;
  uniqueAdded: number;
}> {
  const query = route.web.searchQuery;
  logResearchQuery(query);
  const sourcesBefore = collectedSources.length;

  onEvent({
    type: "agent_status",
    phase: "executing",
    currentStepTitle: options?.stepTitle ?? "Recherche Web",
    stepIndex: 0,
    totalSteps: plan.steps.length,
  });

  const results = await executeToolCalls({
    calls: [{ tool: "web_search", input: { query } }],
    parallel: true,
    stepId: plan.steps[0]?.id,
    plan,
    conversationId: input.conversationId,
    settings: {
      ...input.settings,
      webSearchMaxResults:
        options?.perQueryMaxResults ?? input.settings.webSearchMaxResults,
    },
    signal: input.signal,
    userGoal: input.userContent,
    temporalContext: route.temporal,
    searchCache,
    userId: input.userId,
    toolCtxBase: input.toolCtxBase,
    callbacks: {
      onActionStart: (stepId, action) => {
        onEvent({ type: "agent_action_start", stepId, action });
      },
      onActionDone: (stepId, actionId, summary, sourceCount) => {
        onEvent({
          type: "agent_action_done",
          stepId,
          actionId,
          summary,
          sourceCount,
        });
      },
      onToolStart: (tool, toolInput) => {
        onEvent({
          type: "tool_start",
          tool,
          input: sanitizeToolStartPayload(tool, toolInput),
        });
      },
      onToolDone: (tool, summary, sourceCount) => {
        onEvent({ type: "tool_done", tool, summary, sourceCount });
      },
      onDraftPreview: (draft) => {
        onEvent({ type: "draft_preview", draft });
      },
      onFileActionPending: (payload) => {
        onEvent({ type: "file_action_pending", ...payload });
      },
      onFilesFound: (files) => {
        onEvent({ type: "files_found", files });
      },
      onSources: (sources) => {
        mergeUniqueSources(collectedSources, sources, {
          maxTotal: MAX_COLLECTED_SOURCES_CEILING,
        });
        onEvent({ type: "sources", sources: [...collectedSources] });
      },
    },
  });

  const result = results[0];
  const observation: AgentObservation | null = result
    ? {
        stepId: plan.steps[0]?.id,
        tool: result.tool,
        input: result.input,
        output: result.output,
        summary: result.summary,
        timestamp: new Date().toISOString(),
      }
    : null;

  return {
    observation,
    toolResult: result ?? null,
    uniqueAdded: Math.max(0, collectedSources.length - sourcesBefore),
  };
}

function applyWebResultToFreshness(
  freshnessState: FreshnessState,
  result: {
    error?: string;
    sources: SearchResult[];
  },
  route: RouteDecision,
  researchState: ResearchFlowState
): FreshnessState {
  return updateFreshnessAfterWebSearch(freshnessState, {
    success: !result.error,
    usableResultCount: result.sources.length,
    sources: result.sources,
    route,
    researchState,
  });
}

function checkWebSearchStop(
  tracker: WebSearchTracker,
  _requiresFresh: boolean
): WebSearchStopDecision {
  // Toujours appliquer le critère d'arrêt — pas seulement en mode "fresh".
  // Sinon l'agent peut enchaîner des dizaines de recherches inutiles.
  void _requiresFresh;
  return tracker.shouldStopForResearch();
}

function getWebSearchQuery(input: unknown): string {
  if (typeof input === "object" && input !== null && "query" in input) {
    return String((input as { query: string }).query);
  }
  return "";
}

function trackWebSearchResult(
  tracker: WebSearchTracker,
  result: {
    tool: string;
    input: unknown;
    output?: unknown;
    sources: SearchResult[];
    error?: string;
    deduplicated?: boolean;
  },
  uniqueAdded?: number
): void {
  if (result.tool !== "web_search") return;

  let status: import("@/lib/tools/types").WebSearchStatus = "success";
  if (result.deduplicated) {
    status = result.sources.length > 0 ? "success" : "no_results";
  } else if (result.error) {
    if (
      typeof result.output === "object" &&
      result.output !== null &&
      "status" in result.output
    ) {
      status = (result.output as { status: import("@/lib/tools/types").WebSearchStatus })
        .status;
    } else {
      status = "provider_error";
    }
  } else if (
    typeof result.output === "object" &&
    result.output !== null &&
    "status" in result.output
  ) {
    status = (result.output as { status: import("@/lib/tools/types").WebSearchStatus })
      .status;
  } else if (result.sources.length === 0) {
    status = "no_results";
  }

  tracker.record({
    query: getWebSearchQuery(result.input),
    status,
    usableResultCount: result.sources.length,
    uniqueAdded,
    error: result.error,
    deduplicated: result.deduplicated,
  });
}

/** Plafond structurel — borné par le budget adaptatif (jusqu’à 25). */
const MAX_COLLECTED_SOURCES_CEILING = 25;

function shouldSkipDeciderLoop(
  researchState: ResearchFlowState,
  collectedSources: SearchResult[]
): boolean {
  return (
    researchState.initialSearchDone &&
    collectedSources.length > 0 &&
    !researchState.required
  );
}

function applyWebSearchStopDecision(
  stop: WebSearchStopDecision,
  freshnessState: FreshnessState,
  currentStopReason: string | null
): {
  freshnessState: FreshnessState;
  webStopReason: string | null;
  webSearchStopped: boolean;
} {
  if (!stop.stop) {
    return {
      freshnessState,
      webStopReason: currentStopReason,
      webSearchStopped: false,
    };
  }
  const reason = stop.reason ?? "Recherches Web interrompues.";
  if (stop.kind === "sufficient") {
    return {
      freshnessState,
      webStopReason: currentStopReason,
      webSearchStopped: true,
    };
  }
  return {
    freshnessState: markFreshnessFailed(freshnessState, reason),
    webStopReason: reason,
    webSearchStopped: true,
  };
}

export async function runAgentLoop(input: AgentLoopInput): Promise<void> {
  const limits = resolveAgentLimits(input.settings);
  const requestTracker = new RequestIdTracker();
  const db = getDb();
  const collectedSources: SearchResult[] = [];
  let tracker: AgentRunTracker | null = null;

  const abortIfNeeded = () => {
    if (input.signal?.aborted) {
      requestTracker.abortAll(input.runtime);
      throw new DOMException("Aborted", "AbortError");
    }
  };

  try {
    abortIfNeeded();

    let route =
      input.routeDecision ??
      (await routeRequest({
        message: input.userContent,
        webSearchEnabled: input.settings.webSearchEnabled,
        chatMode: "agent",
        imageCount: 0,
        attachmentCount: input.pendingAttachmentNames?.length ?? 0,
        modelId: input.settings.selectedModel,
        runtime: input.runtime,
        signal: input.signal,
      }));

    const temporalContext = route.temporal;

    let documentContext = input.documentContext;
    if ((input.priorUserMessages?.length ?? 0) > 0) {
      if (input.conversationHistory?.trim()) {
        documentContext = `${documentContext}\n\n<conversation_history>\n${input.conversationHistory.trim()}\n</conversation_history>`.trim();
      }
      if (route.web?.searchQuery) {
        route = {
          ...route,
          web: {
            ...route.web,
            searchQuery: groundSearchQueryWithContext({
              query: route.web.searchQuery,
              recentUserMessages: input.priorUserMessages ?? [],
            }),
          },
        };
      }
    }

    // Les instructions brouillon sont injectées par l'orchestrateur quand l'assistant
    // mail est actif. Fallback si intent=draft sans injection préalable.
    if (
      input.emailEnabled &&
      route.email.intent === "draft" &&
      !documentContext.includes("<email_draft_instructions>")
    ) {
      const { buildEmailDraftInstructionsBlock } = await import(
        "@/lib/email/draft"
      );
      documentContext = `${documentContext}\n\n${buildEmailDraftInstructionsBlock(
        await buildEmailDraftWritingBlock(),
        { accountEmail: input.accountEmail }
      )}`;
    }

    logAgentHeader(resolveEffectiveScope(temporalContext));

    logTemporalSearchDebug({
      userGoal: input.userContent,
      temporalScope: temporalContext.scope,
      userIntent: temporalContext.userIntent,
      generatedQuery: route.web.searchQuery,
      finalQuery: route.web.searchQuery,
      corrected: false,
      clock: temporalContext.clock,
    });

    input.onEvent({
      type: "agent_status",
      phase: "planning",
    });

    const plan = await createAgentPlan({
      goal: input.userContent,
      conversationHistory: input.conversationHistory,
      contextHint: buildContextHint(documentContext),
      temporalContext,
      runtime: input.runtime,
      model: input.settings.selectedModel,
      settings: input.settings,
      reasoningEffort: input.reasoningEffort,
      signal: input.signal,
      registerRequestId: (id) => requestTracker.register(id),
    });

    tracker = await createAgentRunTracker({
      conversationId: input.conversationId,
      model: input.settings.selectedModel,
      plan,
    });

    tracker.recordLlmCall();

    input.onEvent({ type: "agent_start", runId: tracker.id });
    input.onEvent({ type: "agent_plan", plan });

    const searchCache = new SearchQueryCache();
    const sourceBudget = resolveSourceBudget({
      searchType: route.web.searchType,
      researchRequired:
        route.web.mode === "required" || route.web.searchType === "research",
      webSearchMaxResults: input.settings.webSearchMaxResults,
    });
    const maxCollectedSources = Math.min(
      MAX_COLLECTED_SOURCES_CEILING,
      sourceBudget.hardMax
    );
    const webSearchTracker = new WebSearchTracker(sourceBudget);
    let webStopReason: string | null = null;
    let webSearchStopped = false;
    let runOutcome: AgentRunOutcome = "success";
    const webIntent = routeToWebSearchIntent(route);

    let researchState = createResearchFlowStateFromRoute(
      route,
      input.userContent
    );
    let freshnessState = createFreshnessStateFromRoute(
      route,
      input.settings.webSearchEnabled
    );

    if (process.env.NODE_ENV !== "production") {
      console.log(`[FRESHNESS]\n${formatFreshnessBlock(freshnessState)}`);
    }

    const execCtx: AgentExecutionContext = {
      goal: input.userContent,
      plan,
      observations: [],
      stepCount: 0,
      toolCallCount: 0,
      startedAt: Date.now(),
      errors: [],
      limits,
      temporalContext,
      routeDecision: route,
      researchState,
      executedQueries: [],
      freshnessState,
    };

    if (freshnessState.status === "failed") {
      webStopReason =
        freshnessState.blockReason ??
        "Impossible de vérifier les informations actuelles.";
    } else if (freshnessState.requiresFreshWebData && webIntent.allowed) {
      const webAvailability = await evaluateWebSearchAvailability({
        // Hot path agent : fail-fast — ne pas bloquer jusqu'à 45s sur SearXNG starting
        waitIfStartingMs: 500,
      });
      if (!webAvailability.available) {
        webStopReason =
          webAvailability.reason ??
          "SearXNG indisponible — impossible de vérifier les données actuelles.";
        freshnessState = markFreshnessFailed(freshnessState, webStopReason);
        execCtx.freshnessState = freshnessState;
        if (process.env.NODE_ENV !== "production") {
          console.log(`[WEB STATUS]\n${webStopReason}`);
        }
      } else {
        const mandatoryRun = await runMandatoryRouteWebSearch(
          input,
          plan,
          route,
          searchCache,
          collectedSources,
          input.onEvent,
          {
            stepTitle: researchState.required
              ? "Recherche approfondie initiale"
              : "Recherche Web (données actuelles)",
            perQueryMaxResults: sourceBudget.perQueryMaxResults,
          }
        );
        researchState = markInitialResearchSearchDone(researchState);
        researchState = recordWebSearchOutcome(
          researchState,
          !mandatoryRun.toolResult?.error,
          mandatoryRun.toolResult?.sources.length ?? 0
        );
        execCtx.researchState = researchState;
        execCtx.executedQueries = searchCache.executedQueries;
        if (mandatoryRun.observation) {
          execCtx.observations.push(mandatoryRun.observation);
          execCtx.toolCallCount++;
          tracker.recordToolCall("web_search");
        }
        if (mandatoryRun.toolResult) {
          trackWebSearchResult(
            webSearchTracker,
            mandatoryRun.toolResult,
            mandatoryRun.uniqueAdded
          );
          freshnessState = applyWebResultToFreshness(
            freshnessState,
            mandatoryRun.toolResult,
            route,
            researchState
          );
          const stop = checkWebSearchStop(
            webSearchTracker,
            freshnessState.requiresFreshWebData
          );
          if (stop.stop) {
            const applied = applyWebSearchStopDecision(
              stop,
              freshnessState,
              webStopReason
            );
            freshnessState = applied.freshnessState;
            webStopReason = applied.webStopReason;
            webSearchStopped = webSearchStopped || applied.webSearchStopped;
          }
        }
      }
      execCtx.freshnessState = freshnessState;
    }

    const availableTools = getRegisteredTools({
      webSearchEnabled: webIntent.allowed,
      emailEnabled: input.emailEnabled,
      emailToolCandidates: input.emailToolCandidates,
      filesEnabled: input.filesEnabled,
      fileToolCandidates: input.fileToolCandidates,
    }).map((t) => t.name);

    let consecutiveParseFailures = 0;
    const MAX_PARSE_FAILURES = 2;
    let sufficientWebEvidence = false;

    const skipDeciderLoop = shouldSkipDeciderLoop(
      researchState,
      collectedSources
    );

    if (!skipDeciderLoop) {
    while (true) {
      abortIfNeeded();

      if (webStopReason) {
        break;
      }

      const limitReason = checkLimits(execCtx);
      if (limitReason) {
        input.onEvent({ type: "agent_limit_reached", reason: limitReason });
        tracker.finalize("limit_reached", limitReason);
        finalizePlanSteps(plan);
        input.onEvent({ type: "agent_plan", plan: cloneAgentPlan(plan) });
        break;
      }

      const activeIdx = getActiveStepIndex(plan);
      const activeStep = plan.steps[activeIdx];

      input.onEvent({
        type: "agent_status",
        phase: "executing",
        currentStepTitle: activeStep?.title,
        stepIndex: activeIdx,
        totalSteps: plan.steps.length,
      });

      const decideRequestId = nanoid();
      requestTracker.register(decideRequestId);

      let decideResponse;
      try {
        decideResponse = await input.runtime.chat({
          requestId: decideRequestId,
          model: input.settings.selectedModel,
          messages: [
            {
              role: "system",
              content: buildDeciderSystemPrompt(
                plan,
                availableTools,
                temporalContext,
                researchState.required
                  ? formatResearchBlockForDecider(researchState)
                  : undefined
              ),
            },
            {
              role: "user",
              content: buildDeciderUserPrompt(execCtx),
            },
          ],
          temperature: 0.4,
          maxTokens: 2048,
          signal: input.signal,
          reasoningEffort: null,
        });
      } catch (decideError) {
        const msg =
          decideError instanceof Error ? decideError.message : String(decideError);
        execCtx.errors.push(`Décideur indisponible: ${msg}`);
        tracker.recordError();
        break;
      }

      if (decideResponse.usage) {
        tracker.addTokens(
          (decideResponse.usage.promptTokens ?? 0) +
            (decideResponse.usage.completionTokens ?? 0)
        );
        input.onEvent({ type: "generation_usage", usage: decideResponse.usage });
      }

      tracker.recordLlmCall();
      execCtx.stepCount++;

      const decision = decideResponse.content
        ? parseDecision(decideResponse.content)
        : null;

      if (!decision) {
        consecutiveParseFailures++;
        execCtx.errors.push("Décision non parsable");
        tracker.recordError();
        if (consecutiveParseFailures >= MAX_PARSE_FAILURES) {
          break;
        }
        continue;
      }

      consecutiveParseFailures = 0;

      if (decision.type === "finish") {
        const webSearchCount = execCtx.observations.filter(
          (o) => o.tool === "web_search"
        ).length;
        const freshnessGate = evaluateFreshnessForSynthesis(freshnessState, {
          route,
          researchState,
          webSearchCount,
          collectedSources,
        });
        if (
          freshnessState.requiresFreshWebData &&
          !freshnessGate.allowLlmSynthesis
        ) {
          execCtx.errors.push(
            freshnessGate.blockReason ?? "Données Web actuelles non vérifiées"
          );
          execCtx.observations.push({
            tool: "system",
            input: { type: "finish_rejected_freshness" },
            output: freshnessGate,
            summary:
              freshnessGate.blockReason ??
              "finish rejeté — données Web actuelles non vérifiées",
            timestamp: new Date().toISOString(),
          });
          continue;
        }
        const validation = validateBeforeSynthesis(
          researchState,
          webSearchCount
        );
        if (!validation.canProceed) {
          execCtx.errors.push(validation.blockReason ?? "Validation échouée");
          execCtx.observations.push({
            tool: "system",
            input: { type: "finish_rejected" },
            output: validation,
            summary: validation.blockReason ?? "finish rejeté",
            timestamp: new Date().toISOString(),
          });
          continue;
        }
        break;
      }

      if (decision.type === "advance_step") {
        applyStepStatusChange(
          plan,
          decision.stepId,
          decision.status === "done" ? "done" : "skipped",
          input.onEvent
        );
        tracker.recordStepExecuted(decision.stepId);
        tracker.setPlan(plan);
        continue;
      }

      if (decision.type === "revise_plan") {
        applyPlanRevision(plan, decision.steps);
        sanitizePlanActiveSteps(plan);
        input.onEvent({ type: "agent_plan", plan: cloneAgentPlan(plan) });
        tracker.setPlan(plan);
        continue;
      }

      if (decision.type === "tool_calls") {
        let callsToRun = decision.calls;
        if (
          webSearchStopped &&
          callsToRun.some((c) => c.tool === "web_search")
        ) {
          const nonWeb = callsToRun.filter((c) => c.tool !== "web_search");
          execCtx.observations.push({
            tool: "system",
            input: callsToRun,
            output: {
              stopped: true,
              reason:
                webStopReason ??
                "Limite de recherches Web atteinte — assez de sources collectées.",
            },
            summary:
              webStopReason ??
              "Recherches Web arrêtées — sources suffisantes pour synthèse.",
            timestamp: new Date().toISOString(),
          });
          // Assez de sources : passer à la synthèse au lieu de reboucler.
          if (nonWeb.length === 0 && collectedSources.length > 0) {
            sufficientWebEvidence = true;
            break;
          }
          if (nonWeb.length === 0) {
            continue;
          }
          callsToRun = nonWeb;
        }

        if (
          webStopReason &&
          callsToRun.some((c) => c.tool === "web_search")
        ) {
          execCtx.observations.push({
            tool: "system",
            input: callsToRun,
            output: { stopped: true, reason: webStopReason },
            summary: webStopReason,
            timestamp: new Date().toISOString(),
          });
          break;
        }

        if (decision.stepId) {
          applyStepStatusChange(plan, decision.stepId, "active", input.onEvent);
          tracker.recordStepExecuted(decision.stepId);
        }

        const results = await executeToolCalls({
          calls: callsToRun,
          parallel: decision.parallel ?? callsToRun.length > 1,
          stepId: decision.stepId,
          plan,
          conversationId: input.conversationId,
          settings: {
            ...input.settings,
            webSearchMaxResults: sourceBudget.perQueryMaxResults,
          },
          signal: input.signal,
          userGoal: input.userContent,
          temporalContext,
          searchCache,
          userId: input.userId,
          toolCtxBase: input.toolCtxBase,
          callbacks: {
            onActionStart: (stepId, action) => {
              input.onEvent({ type: "agent_action_start", stepId, action });
            },
            onActionDone: (stepId, actionId, summary, sourceCount) => {
              input.onEvent({
                type: "agent_action_done",
                stepId,
                actionId,
                summary,
                sourceCount,
              });
            },
            onToolStart: (tool, toolInput) => {
              input.onEvent({
                type: "tool_start",
                tool,
                input: sanitizeToolStartPayload(tool, toolInput),
              });
            },
            onToolDone: (tool, summary, sourceCount) => {
              input.onEvent({ type: "tool_done", tool, summary, sourceCount });
            },
            onDraftPreview: (draft) => {
              input.onEvent({ type: "draft_preview", draft });
            },
            onFileActionPending: (payload) => {
              input.onEvent({ type: "file_action_pending", ...payload });
            },
            onFilesFound: (files) => {
              input.onEvent({ type: "files_found", files });
            },
            onSources: (sources) => {
              mergeUniqueSources(collectedSources, sources, {
                maxTotal: maxCollectedSources,
              });
              input.onEvent({ type: "sources", sources: [...collectedSources] });
            },
          },
        });

        for (const result of results) {
          if (!result.deduplicated) {
            execCtx.toolCallCount++;
            tracker.recordToolCall(result.tool);
          }
          if (result.error) {
            execCtx.errors.push(result.error);
            tracker.recordError();
          }

          if (result.tool === "web_search") {
            // uniqueAdded approximé : taille du batch (déjà dédupliqué à l'URL)
            const uniqueAdded = result.deduplicated ? 0 : result.sources.length;
            trackWebSearchResult(webSearchTracker, result, uniqueAdded);
            researchState = recordWebSearchOutcome(
              researchState,
              !result.error,
              result.sources.length
            );
            execCtx.researchState = researchState;

            freshnessState = applyWebResultToFreshness(
              freshnessState,
              result,
              route,
              researchState
            );
            execCtx.freshnessState = freshnessState;

            if (!webSearchStopped) {
              const stop = checkWebSearchStop(
                webSearchTracker,
                freshnessState.requiresFreshWebData
              );
              if (stop.stop) {
                const applied = applyWebSearchStopDecision(
                  stop,
                  freshnessState,
                  webStopReason
                );
                freshnessState = applied.freshnessState;
                webStopReason = applied.webStopReason;
                webSearchStopped =
                  webSearchStopped || applied.webSearchStopped;
                execCtx.freshnessState = freshnessState;
                execCtx.observations.push({
                  tool: "system",
                  input: { type: "web_search_stop" },
                  output: stop,
                  summary: webStopReason ?? stop.reason ?? "",
                  timestamp: new Date().toISOString(),
                });
                // Passer à la synthèse dès que le critère d'arrêt est atteint
                if (
                  applied.webSearchStopped &&
                  stop.kind === "sufficient" &&
                  collectedSources.length > 0
                ) {
                  sufficientWebEvidence = true;
                  break;
                }
              }
            }
          }

          execCtx.executedQueries = searchCache.executedQueries;

          const observation: AgentObservation = {
            stepId: decision.stepId,
            tool: result.tool,
            input: result.input,
            output: result.output,
            summary: result.summary,
            timestamp: new Date().toISOString(),
          };
          execCtx.observations.push(observation);
        }

        if (webStopReason || sufficientWebEvidence) {
          tracker.setPlan(plan);
          break;
        }

        tracker.setPlan(plan);
      }
    }
    }

    abortIfNeeded();

    const webSearchCount = execCtx.observations.filter(
      (o) => o.tool === "web_search"
    ).length;
    const synthesisValidation = validateBeforeSynthesis(
      researchState,
      webSearchCount
    );
    const freshnessGate = evaluateFreshnessForSynthesis(freshnessState, {
      route,
      researchState,
      webSearchCount,
      collectedSources,
    });

    logFinalSummary({
      sourcesUsed: collectedSources.length,
      currentDataVerified:
        freshnessGate.status === "verified" &&
        synthesisValidation.currentDataVerified,
      webSearchCount,
    });

    const isWebFailure =
      freshnessGate.forceHonestResponse ||
      synthesisValidation.forceHonestResponse ||
      (freshnessState.requiresFreshWebData &&
        freshnessGate.status !== "verified");

    if (isWebFailure) {
      finalizePlanOnWebFailure(plan, input.onEvent);
      runOutcome = "web_unavailable";
      webStopReason =
        webStopReason ??
        freshnessGate.blockReason ??
        "Agent arrêté : aucune source Web exploitable";
      freshnessState = markFreshnessFailed(
        freshnessState,
        webStopReason
      );
    } else {
      finalizePlanOnSuccess(plan);
    }
    tracker.setPlan(plan);
    input.onEvent({ type: "agent_plan", plan: cloneAgentPlan(plan) });

    input.onEvent({
      type: "agent_status",
      phase: "synthesizing",
    });

    const observationsText = formatObservationsForSynthesis(
      execCtx.observations
    );
    const synthesisSources = capSourcesForSynthesis(
      collectedSources,
      maxCollectedSources
    );
    // Conservé pour UI/DB : même ensemble que la synthèse (budget adaptatif).
    const sourcesForPersist = synthesisSources.length > 0
      ? synthesisSources
      : capSourcesForSynthesis(collectedSources, maxCollectedSources);
    const sourcesBlock =
      synthesisSources.length > 0
        ? formatSearchResultsBlock(
            input.userContent.slice(0, 80),
            synthesisSources
          )
        : "";

    const aggregateFreshness = assessSearchResultsFreshness(
      collectedSources,
      {
        fetchedAt: new Date(),
        temporalScope: resolveEffectiveScope(temporalContext),
        referenceYear: temporalContext.referenceYear,
        currentYear: temporalContext.clock.currentYear,
      }
    );
    const freshnessNotes = formatFreshnessNotesForSynthesis(
      aggregateFreshness.assessments
    );
    const researchContextBlock =
      formatResearchContextForSynthesis(researchState);

    const assistantId = nanoid();
    let fullContent = "";

    input.onEvent({ type: "assistant_start", messageId: assistantId });
    input.flushInitialMemorySaves?.(assistantId);

    if (!freshnessGate.allowLlmSynthesis) {
      fullContent = buildHonestFailureResponse(temporalContext, {
        detail: webStopReason ?? freshnessGate.blockReason,
      });
      input.onEvent({ type: "token", content: fullContent });
    } else if (synthesisValidation.forceHonestResponse) {
      fullContent = buildHonestFailureResponse(temporalContext, {
        detail: freshnessGate.blockReason,
      });
      input.onEvent({ type: "token", content: fullContent });
    } else {
      const synthesisMessages = [
        {
          role: "system" as const,
          content: buildSynthesisSystemPrompt(
            observationsText,
            sourcesBlock,
            temporalContext,
            freshnessNotes,
            researchContextBlock,
            {
              currentDataVerified:
                freshnessGate.status === "verified" &&
                synthesisValidation.currentDataVerified,
              forceHonestResponse:
                synthesisValidation.forceHonestResponse ||
                !freshnessGate.allowLlmSynthesis,
              userGoal: input.userContent,
            }
          ),
        },
        {
          role: "user" as const,
          content: input.conversationHistory?.trim()
            ? `Historique récent :\n${input.conversationHistory.trim()}\n\nMessage actuel :\n${input.userContent}`
            : input.userContent,
        },
      ];

      const synthesisMaxTokens = resolveSynthesisMaxTokens(input.settings);
      let synthesisErrorDetail: string | undefined;

      const emitSynthesisUsage = (usage: RuntimeUsage) => {
        tracker?.addTokens(
          (usage.promptTokens ?? 0) + (usage.completionTokens ?? 0)
        );
        input.onEvent({ type: "generation_usage", usage });
      };

      const runSynthesisChatFallback = async (
        messages: ChatMessage[]
      ): Promise<string> => {
        const chatRequestId = nanoid();
        requestTracker.register(chatRequestId);
        tracker?.recordLlmCall();
        const response = await input.runtime.chat({
          requestId: chatRequestId,
          model: input.settings.selectedModel,
          messages,
          temperature: input.settings.temperature,
          maxTokens: synthesisMaxTokens,
          signal: input.signal,
          reasoningEffort: null,
        });
        if (response.usage) {
          emitSynthesisUsage(response.usage);
        }
        return response.content?.trim() ?? "";
      };

      const runSynthesisGenerate = async (
        messages: ChatMessage[]
      ): Promise<string> => {
        const streamRequestId = nanoid();
        requestTracker.register(streamRequestId);
        tracker?.recordLlmCall();

        let streamedContent = "";

        try {
          await new Promise<void>((resolve, reject) => {
            void input.runtime
              .stream(
                {
                  requestId: streamRequestId,
                  model: input.settings.selectedModel,
                  messages,
                  temperature: input.settings.temperature,
                  maxTokens: synthesisMaxTokens,
                  signal: input.signal,
                  reasoningEffort: null,
                  streamContentOnly: true,
                },
                {
                  onToken: (token) => {
                    streamedContent += token;
                    input.onEvent({ type: "token", content: token });
                  },
                  onUsage: (usage) => {
                    emitSynthesisUsage(usage);
                  },
                  onDone: (result) => {
                    streamedContent = result.content || streamedContent;
                    if (result.usage) {
                      emitSynthesisUsage(result.usage);
                    }
                    resolve();
                  },
                  onError: (error) => {
                    reject(error);
                  },
                }
              )
              .catch(reject);
          });

          return streamedContent.trim();
        } catch (streamError) {
          if (process.env.NODE_ENV !== "production") {
            console.warn(
              "[SYNTHESIS] Stream échoué, repli chat:",
              streamError instanceof Error ? streamError.message : streamError
            );
          }

          const fallbackContent = await runSynthesisChatFallback(messages);
          if (fallbackContent) {
            input.onEvent({ type: "token", content: fallbackContent });
          }
          return fallbackContent;
        }
      };

      try {
        fullContent = await runSynthesisGenerate(synthesisMessages);

        if (fullContent && looksTruncated(fullContent)) {
          const continuationMessages = buildSynthesisContinuationMessages(
            synthesisMessages,
            fullContent
          );
          const continuation = await runSynthesisGenerate(continuationMessages);
          if (continuation) {
            fullContent += continuation;
          }
        }
      } catch (synthesisError) {
        synthesisErrorDetail =
          synthesisError instanceof Error
            ? synthesisError.message
            : String(synthesisError);
        if (process.env.NODE_ENV !== "production") {
          console.warn("[SYNTHESIS] Chat échoué:", synthesisError);
        }
      }

      if (!fullContent.trim()) {
        const llmDetail =
          synthesisErrorDetail ??
          `Le modèle n'a pas produit de texte (${collectedSources.length} sources collectées, ${synthesisSources.length} en synthèse).`;
        if (collectedSources.length > 0) {
          fullContent = buildSourceBasedFallbackResponse(
            temporalContext,
            synthesisSources,
            { llmDetail }
          );
        } else {
          fullContent = buildHonestFailureResponse(temporalContext, {
            detail: llmDetail,
            webSearchSucceeded: false,
          });
        }
        input.onEvent({ type: "token", content: fullContent });
      }
    }

    await db.insert(messages).values({
      id: assistantId,
      conversationId: input.conversationId,
      role: "assistant",
      content: fullContent,
    });

    for (const source of sourcesForPersist) {
      await db.insert(messageSources).values({
        id: nanoid(),
        messageId: assistantId,
        title: source.title,
        domain: source.domain,
        url: source.url,
        snippet: source.snippet,
      });
    }

    if (sourcesForPersist.length > 0) {
      input.onEvent({ type: "sources", sources: sourcesForPersist });
    }

    await db
      .update(conversations)
      .set({ updatedAt: new Date().toISOString() })
      .where(eq(conversations.id, input.conversationId));

    void maybeGenerateConversationTitle({
      conversationId: input.conversationId,
      onTitle: (title) => {
        input.onEvent({ type: "conversation_title", title });
      },
    });

    if (tracker) {
      const finalPlan = cloneAgentPlan(plan);
      if (tracker.status === "running") {
        if (runOutcome === "web_unavailable") {
          tracker.finalize("stopped", webStopReason ?? undefined);
        } else {
          tracker.finalize("completed");
          runOutcome = "success";
        }
      }
      tracker.messageId = assistantId;
      await tracker.persist();
      input.onEvent({
        type: "agent_done",
        runId: tracker.id,
        stats: tracker.stats,
        plan: finalPlan,
        stopReason: webStopReason ?? undefined,
        runOutcome,
      });
    }

    input.onEvent({ type: "done", messageId: assistantId });

    if (input.memoryIntent?.shouldRemember && input.settings.memoryEnabled) {
      const saved = await applyMemoryAfterResponse({
        intent: input.memoryIntent,
        userMessage: input.userContent,
        assistantMessage: fullContent,
        memoryEnabled: input.settings.memoryEnabled,
      });
      emitMemorySaved(input.onEvent, assistantId, saved);
    }
    void maybeSummarizeConversation(input.conversationId);
  } catch (error) {
    const errorPlan = tracker?.plan;

    if (error instanceof DOMException && error.name === "AbortError") {
      if (tracker && errorPlan) {
        finalizePlanSteps(errorPlan);
        tracker.finalize("stopped");
        await tracker.persist();
        input.onEvent({
          type: "agent_done",
          runId: tracker.id,
          stats: tracker.stats,
          plan: cloneAgentPlan(errorPlan),
        });
      }
      throw error;
    }

    if (tracker && errorPlan) {
      finalizePlanSteps(errorPlan);
      tracker.finalize("error");
      await tracker.persist();
      input.onEvent({
        type: "agent_done",
        runId: tracker.id,
        stats: tracker.stats,
        plan: cloneAgentPlan(errorPlan),
      });
    }

    input.onEvent({
      type: "error",
      message: error instanceof Error ? error.message : String(error),
    });
  } finally {
    requestTracker.abortAll(input.runtime);
  }
}
