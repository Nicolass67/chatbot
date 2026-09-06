import { groundSearchQueryWithContext } from "@/lib/context/conversation-continuity";
import { resolveConversationalWebRoute, rewriteMisroutedFileSearchCalls } from "@/lib/context/conversational-web-resolution";
import { isContextDebugEnabled } from "@/lib/context/debug-trace";
import {
  createLlmPageEvidenceAnalyzer,
  runWebEvidencePipeline,
} from "@/lib/context/web-evidence";
import { createWebSearchProvider } from "@/lib/tools/web-search/provider-factory";
import { fetchWebPageText } from "@/lib/tools/web-search/fetch-page";
import { nanoid } from "nanoid";
import { eq } from "drizzle-orm";
import { maybeSummarizeConversation } from "@/lib/context/summarizer";
import { maybeGenerateConversationTitle } from "@/lib/conversation/title-generator";
import { getDb } from "@/lib/db";
import { conversations, messageSources, messages } from "@/lib/db/schema";
import { awaitMemoryPostProcessAfterDone } from "@/lib/memory/post-processor";
import type { MemoryIntentDecision } from "@/lib/memory/intent-classifier";
import type { LocalAIRuntime } from "@/lib/runtime/types";
import type { AppSettings } from "@/lib/settings/service";
import { getRegisteredTools } from "@/lib/tools/registry";
import type { ToolContext } from "@/lib/tools/types";
import { formatSearchResultsBlock, capSourcesForSynthesis } from "@/lib/tools/web-search/heuristics";
import {
  formatWebSourcesForContext,
  isSnippetInsufficient,
  searchResultsToWebSources,
} from "@/lib/context/web-provenance";
import { deepenSearchResults } from "@/lib/tools/web-search/fetch-page";
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
  evaluateFinishAgainstPlan,
  shouldSkipDeciderForPlan,
} from "./plan-execution";
import {
  applyStepStatusChange,
  cloneAgentPlan,
  finalizePlanOnWebFailure,
  finalizePlanOnSuccess,
  finalizePlanSteps,
  progressPlanToStepIndex,
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
  /** Canal composer UI — source de vérité Chat/Mail/Files. */
  toolChannel?: import("@/lib/agent/tool-channel").ToolChannel;
  conversationId: string;
  userContent: string;
  settings: AppSettings;
  runtime: LocalAIRuntime;
  reasoningEffort: string | null;
  documentContext: string;
  signal?: AbortSignal;
  onEvent: (event: OrchestratorEvent) => void;
  pendingAttachmentNames?: string[];
  routeDecision?: RouteDecision;  alreadySavedCount?: number;  userId?: string;
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

  const domains = result.sources
    .map((s) => {
      const d = (s.domain || "").trim();
      if (d) return d;
      try {
        return new URL(s.url).hostname;
      } catch {
        return "";
      }
    })
    .filter(Boolean);

  tracker.record({
    query: getWebSearchQuery(result.input),
    status,
    usableResultCount: result.sources.length,
    uniqueAdded,
    domains,
    uniqueDomainsAdded: new Set(
      domains.map((d) => d.toLowerCase().replace(/^www\./, ""))
    ).size,
    error: result.error,
    deduplicated: result.deduplicated,
  });
}

/** Plafond structurel — borné par le budget adaptatif (jusqu’à 25). */
const MAX_COLLECTED_SOURCES_CEILING = 25;

function shouldSkipDeciderLoop(
  researchState: ResearchFlowState,
  collectedSources: SearchResult[],
  plan: AgentPlan
): boolean {
  return shouldSkipDeciderForPlan(plan, {
    initialSearchDone: researchState.initialSearchDone,
    collectedSourceCount: collectedSources.length,
    researchRequired: researchState.required,
  });
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

    route = resolveConversationalWebRoute({
      route,
      userMessage: input.userContent,
      priorUserMessages: input.priorUserMessages ?? [],
      priorWebUsed: Boolean(
        input.conversationHistory &&
          /web_search|web_sources|<web_/i.test(input.conversationHistory)
      ),
      toolChannel: input.toolChannel,
      llmFollowUp: route.understanding?.followUp,
    });

    const temporalContext = route.temporal;

    let documentContext = input.documentContext;
    const baseApplicationContext = input.documentContext;
    let durableWebSourcesBlock = "";
    const pageContentsByUrl: Record<string, string> = {};
    let lastWebEvidenceMeta: {
      packetCount: number;
      evidenceCount: number;
      researchPasses: number;
      coverageSufficient: boolean;
    } | null = null;
    let execCtxRef: AgentExecutionContext | null = null;
    const rebuildDocumentContext = () => {
      documentContext = [baseApplicationContext, durableWebSourcesBlock]
        .map((x) => x.trim())
        .filter(Boolean)
        .join("\n\n");
      if (execCtxRef) execCtxRef.applicationContext = documentContext;
    };
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
      applicationContext: documentContext,
    };
    execCtxRef = execCtx;

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
          // Entre-deux UX : recherche terminée → étape suivante (analyse).
          if (plan.steps.length > 1 && !mandatoryRun.toolResult.error) {
            progressPlanToStepIndex(plan, 1, input.onEvent);
            tracker.setPlan(plan);
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
      collectedSources,
      plan
    );

    
    // Evidence après recherche obligatoire — indépendant du skip décidur
    // (plan multi-étapes : evidence puis décidur pour les étapes restantes).
    if (
      collectedSources.length > 0 &&
      !durableWebSourcesBlock.includes("<web_evidence>")
    ) {
      try {
        // Analyse des sources — garder l’étape « analyse » active pendant le pipeline.
        if (plan.steps.length > 1) {
          progressPlanToStepIndex(plan, Math.min(1, plan.steps.length - 1), input.onEvent);
          tracker.setPlan(plan);
        }
        const query =
          route.web.searchQuery || input.userContent.slice(0, 120);
        const researchMode =
          route.web.searchType === "research" ||
          route.web.mode === "required";
        // Fetch manquant uniquement — éviter double deepen agressif
        const pageAnalyzer = createLlmPageEvidenceAnalyzer({
          runtime: input.runtime,
          model: input.settings.selectedModel,
          signal: input.signal,
          temperature: 0.1,
          maxTokens: 450,
        });
        const evidenceResult = await runWebEvidencePipeline({
          userQuestion: input.userContent,
          searchQuery: query,
          sources: collectedSources.map((src, i) => ({
            sourceId: `web_${i + 1}`,
            url: src.url,
            title: src.title,
            snippet: src.snippet ?? "",
            domain: src.domain,
            pageContent: pageContentsByUrl[src.url],
          })),
          pageContents: pageContentsByUrl,
          maxAnalyzePages: researchMode ? 10 : 8,
          maxTotalAnalyzePages: researchMode ? 28 : 18,
          maxCandidateSources: Math.max(
            30,
            Math.min(40, collectedSources.length)
          ),
          extractionConcurrency: 2,
          maxFollowUpPasses: researchMode ? 3 : 2,
          maxPageCharsForAnalysis: 24_000,
          conversationPriorUserMessages: input.priorUserMessages ?? [],
          modelId: input.settings.selectedModel,
          analyzeSource: pageAnalyzer,
          onSourceProgress: (info) => {
            input.onEvent({ type: "source_progress", ...info });
          },
          runFollowUpSearch: async (followQuery) => {
            const provider = createWebSearchProvider();
            const search = await provider.search(followQuery, {
              maxResults: Math.min(
                researchMode ? 16 : 12,
                Math.max(8, input.settings.webSearchMaxResults)
              ),
              timeoutMs: input.settings.webSearchTimeoutMs ?? 25_000,
              signal: input.signal ?? AbortSignal.timeout(25_000),
            });
            const sources = (search.results ?? []).map((src, i) => ({
              sourceId: `web_${collectedSources.length + i + 1}`,
              url: src.url,
              title: src.title,
              snippet: src.snippet ?? "",
              domain: src.domain,
            }));
            const pageContents: Record<string, string> = {};
            for (const src of sources.slice(0, 5)) {
              if (pageContentsByUrl[src.url]) {
                pageContents[src.url] = pageContentsByUrl[src.url]!;
                continue;
              }
              const page = await fetchWebPageText(src.url, {
                signal: input.signal,
                maxChars: 24_000,
              });
              if (page.ok && page.text) {
                pageContents[src.url] = page.text;
                pageContentsByUrl[src.url] = page.text;
              }
            }
            return {
              query: followQuery,
              sources: sources.map((s) => ({
                ...s,
                pageContent: pageContents[s.url],
              })),
              pageContents,
            };
          },
        });
        lastWebEvidenceMeta = {
          packetCount: evidenceResult.packets.length,
          evidenceCount: evidenceResult.evidence.length,
          researchPasses: evidenceResult.researchPasses,
          coverageSufficient: evidenceResult.coverage.sufficient,
        };
        durableWebSourcesBlock =
          evidenceResult.finalApplicationContext || durableWebSourcesBlock;
        rebuildDocumentContext();
        if (isContextDebugEnabled() && evidenceResult.metrics) {
          console.info(
            "[web-evidence-v4]",
            JSON.stringify({
              path: skipDeciderLoop
                ? "mandatory_skip_decider"
                : "mandatory_then_decider",
              metrics: evidenceResult.metrics,
              coverage: evidenceResult.coverage.reason,
            })
          );
        }
      } catch (err) {
        console.warn(
          "[web-grounding] mandatory evidence pipeline failed",
          err instanceof Error ? err.message : err
        );
      }
    }

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
          // Tool/decider : reasoning OFF explicite → 2048 OK.
          maxTokens: 2048,
          signal: input.signal,
          reasoningEffort: "off",
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
        const planGate = evaluateFinishAgainstPlan(plan);
        if (!planGate.allowed) {
          execCtx.errors.push(planGate.reason ?? "Plan incomplet");
          execCtx.observations.push({
            tool: "system",
            input: { type: "finish_rejected_plan" },
            output: planGate,
            summary: planGate.reason ?? "finish rejeté — étapes du plan encore ouvertes",
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
        let callsToRun = rewriteMisroutedFileSearchCalls(
          decision.calls,
          input.userContent,
          input.toolChannel
        );
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
            try {
              const query =
                typeof (result.input as { query?: string } | undefined)?.query ===
                "string"
                  ? (result.input as { query: string }).query
                  : input.userContent.slice(0, 120);
              const researchMode =
                route.web.searchType === "research" ||
                route.web.mode === "required";
              const deepened = await deepenSearchResults({
                query,
                results: result.sources.map((src) => ({
                  title: src.title,
                  url: src.url,
                  snippet: src.snippet ?? "",
                })),
                maxPages: researchMode ? 6 : 4, // V4: deepen léger — le pipeline fetch les pages sélectionnées
                signal: input.signal,
                snippetInsufficient: isSnippetInsufficient,
                onProgress: (info) => {
                  input.onEvent({
                    type: "source_progress",
                    phase: info.phase === "done" ? "done" : "fetching",
                    url: info.url,
                    title: info.title,
                    domain: info.domain,
                    index: info.index,
                    total: info.total,
                  });
                },
              });
              Object.assign(pageContentsByUrl, deepened);

              const pageAnalyzer = createLlmPageEvidenceAnalyzer({
                runtime: input.runtime,
                model: input.settings.selectedModel,
                signal: input.signal,
                temperature: 0.1,
                maxTokens: 450,
              });

              const evidenceResult = await runWebEvidencePipeline({
                userQuestion: input.userContent,
                searchQuery: query,
                sources: result.sources.map((src, i) => ({
                  sourceId: `web_${i + 1}`,
                  url: src.url,
                  title: src.title,
                  snippet: src.snippet ?? "",
                  domain: src.domain,
                  pageContent: pageContentsByUrl[src.url],
                })),
                pageContents: pageContentsByUrl,
                maxAnalyzePages: researchMode ? 10 : 8,
                maxTotalAnalyzePages: researchMode ? 28 : 18,
                maxCandidateSources: Math.max(
                  30,
                  Math.min(40, result.sources.length)
                ),
                extractionConcurrency: 2,
                maxFollowUpPasses: researchMode ? 3 : 2,
                maxPageCharsForAnalysis: 24_000,
                conversationPriorUserMessages: input.priorUserMessages ?? [],
                analyzeSource: pageAnalyzer,
                onSourceProgress: (info) => {
                  input.onEvent({ type: "source_progress", ...info });
                },
                proposeFollowUpQueries: async ({ question, missingNeeds, existingEvidence }) => {
                  const focuses = missingNeeds
                    .map((n) => n.description)
                    .filter(Boolean)
                    .slice(0, 3);
                  const base = groundSearchQueryWithContext({
                    query: route.web.searchQuery || question,
                    recentUserMessages: input.priorUserMessages ?? [],
                  });
                  if (focuses.length === 0) return [base.slice(0, 160)];
                  return focuses.map((f) => `${base} — ${f}`.slice(0, 180));
                },
                runFollowUpSearch: async (followQuery) => {
                  const provider = createWebSearchProvider();
                  const search = await provider.search(followQuery, {
                    maxResults: Math.min(
                      researchMode ? 16 : 12,
                      Math.max(8, input.settings.webSearchMaxResults)
                    ),
                    timeoutMs: input.settings.webSearchTimeoutMs ?? 25_000,
                    signal: input.signal ?? AbortSignal.timeout(25_000),
                  });
                  const sources = (search.results ?? []).map((src, i) => ({
                    sourceId: `web_${collectedSources.length + i + 1}`,
                    url: src.url,
                    title: src.title,
                    snippet: src.snippet ?? "",
                    domain: src.domain,
                  }));
                  const pageContents: Record<string, string> = {};
                  for (const src of sources.slice(0, 5)) {
                    if (pageContentsByUrl[src.url]) {
                      pageContents[src.url] = pageContentsByUrl[src.url]!;
                      continue;
                    }
                    const page = await fetchWebPageText(src.url, {
                      signal: input.signal,
                      maxChars: 24_000,
                    });
                    if (page.ok && page.text) {
                      pageContents[src.url] = page.text;
                      pageContentsByUrl[src.url] = page.text;
                    }
                  }
                  return {
                    query: followQuery,
                    sources: sources.map((s) => ({
                      ...s,
                      pageContent: pageContents[s.url],
                    })),
                    pageContents,
                  };
                },
              });

              lastWebEvidenceMeta = {
                packetCount: evidenceResult.packets.length,
                evidenceCount: evidenceResult.evidence.length,
                researchPasses: evidenceResult.researchPasses,
                coverageSufficient: evidenceResult.coverage.sufficient,
              };
              if (isContextDebugEnabled()) {
                const selectedCount = evidenceResult.selection.filter(
                  (d) => d.selected
                ).length;
                const fetchedStep = evidenceResult.trace.find(
                  (s) => s.stage === "fetch"
                );
                input.onEvent({
                  type: "context_debug",
                  trace: {
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
                    webEvidence: {
                      candidateCount: evidenceResult.selection.length,
                      selectedCount,
                      fetchedCount: fetchedStep?.kept.length,
                      packetCount: lastWebEvidenceMeta.packetCount,
                      evidenceCount: lastWebEvidenceMeta.evidenceCount,
                      researchPasses: lastWebEvidenceMeta.researchPasses,
                      coverageSufficient:
                        lastWebEvidenceMeta.coverageSufficient,
                      coverageReason: evidenceResult.coverage.reason,
                      stages: evidenceResult.trace.map((s) => s.stage),
                      finalContextChars:
                        evidenceResult.finalApplicationContext.length,
                    },
                  },
                });
                console.info(
                  "[web-evidence-v4]",
                  JSON.stringify({
                    packets: lastWebEvidenceMeta.packetCount,
                    evidence: lastWebEvidenceMeta.evidenceCount,
                    passes: lastWebEvidenceMeta.researchPasses,
                    coverage: evidenceResult.coverage.reason,
                    stages: evidenceResult.trace.map((s) => s.stage),
                    contextChars:
                      evidenceResult.finalApplicationContext.length,
                  })
                );
              }

              durableWebSourcesBlock =
                evidenceResult.finalApplicationContext ||
                formatWebSourcesForContext(
                  searchResultsToWebSources(query, result.sources, {
                    pageContents: pageContentsByUrl,
                  })
                );
              rebuildDocumentContext();
            } catch (enrichErr) {
              console.warn(
                "[web-grounding] evidence pipeline failed",
                enrichErr instanceof Error ? enrichErr.message : enrichErr
              );
            }
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
      // Synthèse en cours : étapes précédentes done, dernière active (pas tout validé d’un coup).
      for (let i = 0; i < plan.steps.length; i++) {
        const step = plan.steps[i];
        if (!step || step.status === "failed") continue;
        step.status = i === plan.steps.length - 1 ? "active" : "done";
      }
      sanitizePlanActiveSteps(plan);
    }
    tracker.setPlan(plan);
    input.onEvent({ type: "agent_plan", plan: cloneAgentPlan(plan) });

    input.onEvent({
      type: "agent_status",
      phase: "synthesizing",
      currentStepTitle: plan.steps[plan.steps.length - 1]?.title,
      stepIndex: Math.max(0, plan.steps.length - 1),
      totalSteps: plan.steps.length,
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
      durableWebSourcesBlock.includes("<web_evidence>")
        ? durableWebSourcesBlock
        : synthesisSources.length > 0
          ? formatWebSourcesForContext(
              searchResultsToWebSources(
                input.userContent.slice(0, 80),
                synthesisSources,
                { pageContents: pageContentsByUrl }
              )
            )
          : durableWebSourcesBlock;

    // Évite le doublon evidence dans applicationContext + sourcesBlock (overflow 8k).
    const synthesisApplicationContext = sourcesBlock.includes("<web_evidence>")
      ? baseApplicationContext
      : documentContext;

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

    input.onEvent({ type: "assistant_start", messageId: assistantId });    if (!freshnessGate.allowLlmSynthesis) {
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
              answerShape: route.understanding?.answerShape as
                | import("@/lib/prompts/response-policy").AnswerShape
                | undefined,
              userGoal: input.userContent,
              applicationContext: synthesisApplicationContext,
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
          // Synthèse structurée : reasoning OFF (évite budget mangé par thinking).
          reasoningEffort: "off",
        });
        if (response.usage) {
          emitSynthesisUsage(response.usage);
        }
        // content prioritaire ; reasoningContent uniquement si content vide.
        const text = (
          response.content?.trim() ||
          response.reasoningContent?.trim() ||
          ""
        ).trim();
        return text;
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
                  reasoningEffort: "off",
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

      // Stream vide ≠ synthèse échouée : tenter un chat non-stream avant fallback sources.
      if (!fullContent.trim() && !synthesisErrorDetail) {
        try {
          const chatRetry = await runSynthesisChatFallback(synthesisMessages);
          if (chatRetry) {
            fullContent = chatRetry;
            input.onEvent({ type: "token", content: fullContent });
          }
        } catch (retryErr) {
          synthesisErrorDetail =
            retryErr instanceof Error ? retryErr.message : String(retryErr);
        }
      }

      // Fallback « sources Web uniquement » uniquement si la synthèse a réellement échoué.
      if (!fullContent.trim()) {
        const hasEvidencePackets =
          durableWebSourcesBlock.includes("<web_evidence>") ||
          (lastWebEvidenceMeta?.packetCount ?? 0) > 0;
        const llmDetail =
          synthesisErrorDetail ??
          `Le modèle n'a pas produit de texte (${collectedSources.length} sources collectées, ${synthesisSources.length} en synthèse${
            hasEvidencePackets
              ? `, ${lastWebEvidenceMeta?.packetCount ?? 0} evidence packets`
              : ""
          }).`;
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
      if (!isWebFailure) {
        finalizePlanOnSuccess(plan);
        tracker.setPlan(plan);
      }
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

    // Attendre (budget borné) pour que memory_saved parte avant close SSE.
    await awaitMemoryPostProcessAfterDone({
      settings: input.settings,
      conversationId: input.conversationId,
      messageId: assistantId,
      userMessage: input.userContent,
      assistantMessage: fullContent,
      onEvent: input.onEvent,
      signal: input.signal,
    });
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
