import { nanoid } from "nanoid";
import { eq } from "drizzle-orm";
import { serializeContentForStorage } from "@/lib/attachments/multimodal";
import { attachToMessage } from "@/lib/attachments/storage";
import {
  getConversationAttachments,
  loadAttachmentsForMessages,
} from "@/lib/attachments/service";
import { snapshotFromMessages } from "@/lib/context/builder";
import { resolveActiveContext } from "@/lib/context/active-context";
import { isContextDebugEnabled } from "@/lib/context/debug-trace";
import { buildContextPlan } from "@/lib/context/plan";
import { maybeSummarizeConversation } from "@/lib/context/summarizer";
import { maybeGenerateConversationTitle } from "@/lib/conversation/title-generator";
import { getDb } from "@/lib/db";
import {
  conversations,
  messageSources,
  messages,
  toolCalls,
} from "@/lib/db/schema";
import { applyImmediateMemories, applyMemoryAfterResponse } from "@/lib/memory/apply-intent";
import { emitMemorySaved } from "@/lib/memory/emit-saved";
import type { MemoryIntentDecision } from "@/lib/memory/intent-classifier";
import type { SavedMemoryItem } from "@/lib/memory/saved-memory";
import { analyzeRequest, type RouteDecision } from "@/lib/request-router";
import {
  buildMailHandoffUrl,
  handoffMessageForIntent,
} from "@/lib/mail/handoff";
import {
  assertVisionSupported,
  contentToPlainText,
  getActiveModelCapabilities,
} from "@/lib/runtime/capabilities";
import type { RuntimeUsage } from "@/lib/runtime/types";
import { getSettings } from "@/lib/settings/service";
import { getToolDefinitions } from "@/lib/tools/registry";
import { executeToolWithPolicy } from "@/lib/tools/execute-with-policy";
import { resolveCombinedPolicyContext } from "@/lib/tools/policy-context";
import { isFilesFeatureEnabled } from "@/lib/files/feature";
import {
  buildFilesHandoffUrl,
} from "@/lib/files/handoff";
import type { ToolContext } from "@/lib/tools/types";
import type { WebSearchOutput } from "@/lib/tools/types";
import type { SearchResult, WebSearchStatus } from "@/lib/tools/types";
import { WebSearchError } from "@/lib/tools/web-search/tool";
import { mergeUniqueSources, dedupeAndCapSources } from "@/lib/tools/web-search/source-dedupe";
import { createTaintState } from "@/lib/policy";
import { sanitizeToolStartPayload } from "@/lib/observability/sse-sanitize";
import { compressToolResultForContext } from "@/lib/context/tool-result-compress";
import {
  getOAuthAccount,
  isEmailFeatureEnabled,
} from "@/lib/integrations/oauth";
import {
  buildEmailDraftInstructionsBlock,
  buildEmailDraftWritingBlock,
  injectEmailDraftWritingIntoContext,
} from "@/lib/email/draft";
import { getLocalAIRuntime } from "@/lib/runtime/factory";
import { applyMessageEdit } from "./edit-message";
import {
  buildChatContext,
  injectTemporalIntoContext,
  injectWebSearchFailureIntoContext,
  injectWebSearchIntoContext,
} from "./context-builder";
import type { ChatOrchestratorInput } from "./events";
import { runAgentLoop } from "./loop";
import type { ChatMode } from "./types";

export type { OrchestratorEvent, ChatOrchestratorInput } from "./events";

const MAX_TOOL_CALLS = 3;
const MAX_SAME_TOOL = 2;
const ORCHESTRATOR_TIMEOUT_MS = 120_000;
const STATUS_POLL_MS = 800;

function resolveMode(
  requestMode: ChatMode | undefined,
  convMode: string | null | undefined
): ChatMode {
  return requestMode ?? (convMode as ChatMode) ?? "chat";
}

async function runAutoWebSearchForChat(params: {
  input: ChatOrchestratorInput;
  settings: Awaited<ReturnType<typeof getSettings>>;
  query: string;
  toolCtxBase: Omit<ToolContext, "signal">;
}): Promise<
  | { ok: true; results: SearchResult[]; query: string; status: "success" }
  | { ok: false; query: string; status: WebSearchStatus; message: string }
> {
  const { input, settings, query, toolCtxBase } = params;
  input.onEvent({ type: "tool_start", tool: "web_search", input: { query } });

  try {
    const searchResult = (await executeToolWithPolicy(
      "web_search",
      { query },
      {
        ...toolCtxBase,
        signal:
          input.signal ??
          AbortSignal.timeout(settings.webSearchTimeoutMs + 5000),
      }
    )) as WebSearchOutput;

    if (searchResult.results.length === 0 || searchResult.status === "no_results") {
      input.onEvent({
        type: "tool_done",
        tool: "web_search",
        summary: "Aucun résultat",
        sourceCount: 0,
      });
      return {
        ok: false,
        query,
        status: "no_results",
        message:
          "La recherche web n'a retourné aucun résultat exploitable. Ne pas inventer de données actuelles.",
      };
    }

    input.onEvent({
      type: "tool_done",
      tool: "web_search",
      summary: "Recherche Web",
      sourceCount: searchResult.results.length,
    });
    input.onEvent({ type: "sources", sources: searchResult.results });

    return {
      ok: true,
      results: searchResult.results,
      query,
      status: "success",
    };
  } catch (error) {
    const status: WebSearchStatus =
      error instanceof WebSearchError ? error.status : "provider_error";
    const errMsg = error instanceof Error ? error.message : String(error);
    input.onEvent({
      type: "tool_done",
      tool: "web_search",
      summary: `Erreur: ${errMsg}`,
    });
    return {
      ok: false,
      query,
      status,
      message: `Recherche web échouée (${status}): ${errMsg}. Ne pas inventer de données actuelles.`,
    };
  }
}

async function persistAssistantMessage(params: {
  input: ChatOrchestratorInput;
  settings: Awaited<ReturnType<typeof getSettings>>;
  assistantId: string;
  fullContent: string;
  collectedSources: SearchResult[];
  pendingAttachments: Awaited<ReturnType<typeof getConversationAttachments>>;
  memoryIntent?: MemoryIntentDecision;
}): Promise<void> {
  const {
    input,
    assistantId,
    fullContent,
    collectedSources,
  } = params;
  const db = getDb();

  await db.insert(messages).values({
    id: assistantId,
    conversationId: input.conversationId,
    role: "assistant",
    content: fullContent,
  });

  if (collectedSources.length > 0) {
    await db.insert(messageSources).values(
      collectedSources.map((source) => ({
        id: nanoid(),
        messageId: assistantId,
        title: source.title,
        domain: source.domain,
        url: source.url,
        snippet: source.snippet,
      }))
    );
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

  if (params.memoryIntent?.shouldRemember && params.settings.memoryEnabled) {
    const saved = await applyMemoryAfterResponse({
      intent: params.memoryIntent,
      userMessage: input.userContent,
      assistantMessage: fullContent,
      memoryEnabled: params.settings.memoryEnabled,
    });
    emitMemorySaved(input.onEvent, assistantId, saved);
  }

  void maybeSummarizeConversation(input.conversationId);
}

async function streamChatTurn(params: {
  input: ChatOrchestratorInput;
  settings: Awaited<ReturnType<typeof getSettings>>;
  runtime: ReturnType<typeof getLocalAIRuntime>;
  contextMessages: Awaited<ReturnType<typeof buildChatContext>>["contextMessages"];
  tools: ReturnType<typeof getToolDefinitions>;
  reasoningEffort: string | null;
  flushInitialMemorySaves?: (messageId: string) => void;
}): Promise<{
  content: string;
  toolCalls?: Array<{ id: string; name: string; arguments: string }>;
  usage?: RuntimeUsage;
  assistantId: string;
  streamedToUi: boolean;
}> {
  const { input, settings, runtime, contextMessages, tools, reasoningEffort, flushInitialMemorySaves } =
    params;
  const assistantId = nanoid();
  let fullContent = "";
  let toolCalls: Array<{ id: string; name: string; arguments: string }> | undefined;
  let usage: RuntimeUsage | undefined;
  let streamedToUi = false;

  await new Promise<void>((resolve, reject) => {
    void runtime
      .stream(
        {
          requestId: nanoid(),
          model: settings.selectedModel,
          messages: contextMessages,
          tools: tools.length > 0 ? tools : undefined,
          temperature: settings.temperature,
          maxTokens: settings.maxTokens,
          signal: input.signal,
          reasoningEffort,
          streamContentOnly: true,
        },
        {
          onToken: (token) => {
            fullContent += token;
            if (!streamedToUi) {
              streamedToUi = true;
              input.onEvent({ type: "assistant_start", messageId: assistantId });
              flushInitialMemorySaves?.(assistantId);
            }
            input.onEvent({ type: "token", content: token });
          },
          onUsage: (u) => {
            usage = u;
            input.onEvent({ type: "generation_usage", usage: u });
          },
          onDone: (result) => {
            fullContent = result.content || fullContent;
            toolCalls = result.toolCalls;
            usage = result.usage ?? usage;
            resolve();
          },
          onError: (err) => {
            reject(err);
          },
        }
      )
      .catch(reject);
  });

  return {
    content: fullContent,
    toolCalls,
    usage,
    assistantId,
    streamedToUi,
  };
}

async function finalizeStreamedAssistant(params: {
  input: ChatOrchestratorInput;
  settings: Awaited<ReturnType<typeof getSettings>>;
  assistantId: string;
  fullContent: string;
  streamedToUi: boolean;
  collectedSources: SearchResult[];
  pendingAttachments: Awaited<ReturnType<typeof getConversationAttachments>>;
  memoryIntent?: MemoryIntentDecision;
  flushInitialMemorySaves?: (messageId: string) => void;
}): Promise<void> {
  const {
    input,
    settings,
    assistantId,
    streamedToUi,
    collectedSources,
    pendingAttachments,
    memoryIntent,
    flushInitialMemorySaves,
  } = params;
  let { fullContent } = params;

  if (!fullContent.trim()) {
    fullContent = "Je n'ai pas pu générer de réponse.";
  }

  if (!streamedToUi) {
    input.onEvent({ type: "assistant_start", messageId: assistantId });
    flushInitialMemorySaves?.(assistantId);
    input.onEvent({ type: "token", content: fullContent });
  } else if (!params.fullContent.trim()) {
    input.onEvent({ type: "token", content: fullContent });
  }

  if (collectedSources.length > 0) {
    input.onEvent({
      type: "sources",
      sources: dedupeAndCapSources(collectedSources, 20),
    });
  }

  input.onEvent({ type: "done", messageId: assistantId });

  void persistAssistantMessage({
    input,
    settings,
    assistantId,
    fullContent,
    collectedSources: dedupeAndCapSources(collectedSources, 20),
    pendingAttachments,
    memoryIntent,
  }).catch((error) => {
    input.onEvent({
      type: "error",
      message:
        error instanceof Error
          ? `Erreur de sauvegarde: ${error.message}`
          : "Erreur de sauvegarde",
    });
  });
}

export async function runChatOrchestrator(
  input: ChatOrchestratorInput
): Promise<void> {
  const settings = await getSettings();
  const runtime = getLocalAIRuntime();
  const db = getDb();
  const requestId = nanoid();
  const userId = input.userId?.trim() || "local";
  const emailPolicyContext = await resolveCombinedPolicyContext(userId);
  const taintState = createTaintState();
  const emailEnabled = isEmailFeatureEnabled();
  const filesEnabled = isFilesFeatureEnabled();
  const toolCtxBase: Omit<ToolContext, "signal"> = {
    settings,
    conversationId: input.conversationId,
    runtimeLocation: "local",
    userId,
    policyContext: emailPolicyContext,
    taintState,
  };

  if (!settings.selectedModel) {
    input.onEvent({
      type: "error",
      message: "Aucun modèle sélectionné. Configurez-en un dans Paramètres.",
    });
    return;
  }

  const convRow = await db.query.conversations.findFirst({
    where: eq(conversations.id, input.conversationId),
  });

  const chatMode = resolveMode(input.mode, convRow?.chatMode);

  const timeoutMs =
    chatMode === "agent"
      ? Math.max(ORCHESTRATOR_TIMEOUT_MS, 300_000)
      : ORCHESTRATOR_TIMEOUT_MS;

  const timeout = setTimeout(() => {
    runtime.abort(requestId);
  }, timeoutMs);

  try {
    const status = await runtime.status();
    input.onEvent({
      type: "runtime_status",
      status: status.status,
      message: status.message,
    });

    const statusPoll = setInterval(async () => {
      try {
        const s = await runtime.status();
        input.onEvent({
          type: "runtime_status",
          status: s.status,
          message: s.message,
        });
      } catch {
        // ignore poll errors
      }
    }, STATUS_POLL_MS);

    try {
      await runtime.ensureReady({
        signal: input.signal,
        model: settings.selectedModel,
        contextLength: settings.contextLength,
      });
    } finally {
      clearInterval(statusPoll);
    }

    let allDbMessages = await db.query.messages.findMany({
      where: eq(messages.conversationId, input.conversationId),
      orderBy: (m, { asc }) => [asc(m.createdAt)],
    });

    let pendingAttachments: Awaited<
      ReturnType<typeof getConversationAttachments>
    > = [];

    if (input.editMessageId) {
      const editResult = await applyMessageEdit({
        conversationId: input.conversationId,
        editMessageId: input.editMessageId,
        newText: input.userContent,
        attachmentIds: input.attachmentIds,
      });

      allDbMessages = await db.query.messages.findMany({
        where: eq(messages.conversationId, input.conversationId),
        orderBy: (m, { asc }) => [asc(m.createdAt)],
      });

      if (editResult.attachmentIds.length > 0) {
        pendingAttachments = await getConversationAttachments(
          input.conversationId,
          editResult.attachmentIds
        );
        if (pendingAttachments.length !== editResult.attachmentIds.length) {
          input.onEvent({
            type: "error",
            message: "Une ou plusieurs pièces jointes sont introuvables.",
          });
          return;
        }
      }
    } else {
      const attachmentIds = input.regenerate
        ? []
        : (input.attachmentIds ?? []);

      pendingAttachments = attachmentIds.length
        ? await getConversationAttachments(input.conversationId, attachmentIds)
        : [];

      if (input.regenerate) {
        const lastUser = [...allDbMessages]
          .reverse()
          .find((m) => m.role === "user");
        if (lastUser) {
          const map = await loadAttachmentsForMessages([lastUser.id]);
          pendingAttachments = map.get(lastUser.id) ?? [];
        }
      }

      if (
        attachmentIds.length > 0 &&
        pendingAttachments.length !== attachmentIds.length
      ) {
        input.onEvent({
          type: "error",
          message: "Une ou plusieurs pièces jointes sont introuvables.",
        });
        return;
      }

      if (input.regenerate) {
        const lastAssistant = [...allDbMessages]
          .reverse()
          .find((m) => m.role === "assistant");
        if (lastAssistant) {
          await db.delete(messages).where(eq(messages.id, lastAssistant.id));
        }
        allDbMessages = await db.query.messages.findMany({
          where: eq(messages.conversationId, input.conversationId),
          orderBy: (m, { asc }) => [asc(m.createdAt)],
        });
      } else {
        const userMessageId = nanoid();
        const storedContent = serializeContentForStorage(
          input.userContent,
          attachmentIds
        );
        await db.insert(messages).values({
          id: userMessageId,
          conversationId: input.conversationId,
          role: "user",
          content: storedContent,
        });
        if (attachmentIds.length > 0) {
          await attachToMessage(attachmentIds, userMessageId);
        }
        allDbMessages = await db.query.messages.findMany({
          where: eq(messages.conversationId, input.conversationId),
          orderBy: (m, { asc }) => [asc(m.createdAt)],
        });
      }
    }

    // PJ du tour courant → outils mail (auto-attach sur email_create_draft).
    toolCtxBase.pendingAttachmentIds = pendingAttachments.map((a) => a.id);

    const imageCount = pendingAttachments.filter((a) => a.type === "image").length;

    if (imageCount > 0) {
      const modelCaps = await getActiveModelCapabilities(settings.selectedModel);
      const visionError = assertVisionSupported(modelCaps.capabilities, imageCount);
      if (visionError) {
        input.onEvent({ type: "error", message: visionError });
        return;
      }
    }

    const analysis = await analyzeRequest(
      {
        message: input.userContent,
        webSearchEnabled: settings.webSearchEnabled,
        emailEnabled,
        emailConnected: emailPolicyContext.emailConnected,
        filesEnabled,
        filesConfigured: emailPolicyContext.hasConfiguredRoots,
        chatMode,
        imageCount,
        attachmentCount: pendingAttachments.length,
        modelId: settings.selectedModel,
        runtime,
        signal: input.signal,
        recentUserMessages: allDbMessages
          .filter((m) => m.role === "user")
          .slice(-3)
          .map((m) => contentToPlainText(m.content)),
      },
      { memoryEnabled: settings.memoryEnabled }
    );
    const route = analysis.route;
    input.onEvent({ type: "route_decision", decision: route });
    input.onEvent({ type: "memory_intent", decision: analysis.memory });

    const userId = input.userId ?? "local";
    const resolvedActive = await resolveActiveContext({
      userId,
      hint: input.activeContext,
    });

    const contextPlan = buildContextPlan({
      route,
      message: input.userContent,
      hasAttachments: pendingAttachments.length > 0,
      hasActiveFile: Boolean(resolvedActive.file),
      hasActiveMail: Boolean(resolvedActive.mail),
      recentUserMessages: allDbMessages
        .filter((m) => m.role === "user")
        .slice(-3)
        .map((m) => contentToPlainText(m.content)),
    });

    const emailIntent = route.email.intent;
    const isMailScopedConversation = convRow?.scope === "mail";
    const hasActiveMail = Boolean(resolvedActive.mail);
    const mailAssistantActive = isMailScopedConversation || hasActiveMail;

    const mailToolCandidates = mailAssistantActive
      ? [
          "email_get_thread",
          "email_create_draft",
          "email_list",
          "email_search",
          "email_analyze",
        ]
      : [];

    const shouldHandoffToMail =
      emailEnabled &&
      emailPolicyContext.emailConnected &&
      emailIntent !== "none" &&
      !mailAssistantActive;

    if (shouldHandoffToMail && chatMode === "chat") {
      const handoff = buildMailHandoffUrl({
        intent: emailIntent,
        query: route.email.searchQuery,
        label: emailIntent === "list" ? "INBOX" : undefined,
      });
      input.onEvent({
        type: "mail_handoff",
        url: handoff.url,
        intent: handoff.intent,
        query: handoff.query,
        threadId: handoff.threadId,
        label: handoff.label,
        reason: handoff.reason,
      });

      const assistantId = nanoid();
      const handoffText = `${handoffMessageForIntent(emailIntent)} [Ouvrir Mail](${handoff.url})`;
      input.onEvent({ type: "assistant_start", messageId: assistantId });
      input.onEvent({ type: "token", content: handoffText });
      await db.insert(messages).values({
        id: assistantId,
        conversationId: input.conversationId,
        role: "assistant",
        content: handoffText,
      });
      input.onEvent({ type: "done", messageId: assistantId });
      return;
    }

    let initialMemorySaves: SavedMemoryItem[] = [];
    if (analysis.memory.shouldRemember && settings.memoryEnabled) {
      initialMemorySaves = await applyImmediateMemories(analysis.memory);
    }

    let pendingInitialMemorySaves = initialMemorySaves;
    const flushInitialMemorySaves = (messageId: string) => {
      if (pendingInitialMemorySaves.length === 0) return;
      emitMemorySaved(input.onEvent, messageId, pendingInitialMemorySaves);
      pendingInitialMemorySaves = [];
    };

    const shouldAutoSearch =
      chatMode === "chat" &&
      route.web.autoSearch &&
      !input.regenerate &&
      imageCount === 0;

    const [builtContext, autoSearch] = await Promise.all([
      buildChatContext({
        conversationId: input.conversationId,
        userContent: input.userContent,
        settings,
        pendingAttachments,
        signal: input.signal,
        allDbMessages,
        convRow: convRow ?? null,
        plan: contextPlan,
        activeContext: resolvedActive,
      }),
      shouldAutoSearch
        ? runAutoWebSearchForChat({
            input,
            settings,
            query: route.web.searchQuery,
            toolCtxBase,
          })
        : Promise.resolve(null),
    ]);

    const {
      contextMessages,
      initialSnapshot,
      reasoningEffort,
      documentContext: builtDocumentContext,
      debugTrace,
    } = builtContext;

    let documentContext = builtDocumentContext;
    let mailAccountEmail: string | null = null;

    // Assistant Mail : forcer le chemin brouillon (l'envoi direct n'est jamais exposé au LLM).
    if (
      emailEnabled &&
      emailPolicyContext.emailConnected &&
      mailAssistantActive
    ) {
      const writingBlock = await buildEmailDraftWritingBlock();
      const gmailAccount = await getOAuthAccount(userId, "gmail");
      mailAccountEmail = gmailAccount?.accountEmail ?? null;
      const draftOpts = { accountEmail: mailAccountEmail };
      injectEmailDraftWritingIntoContext(
        contextMessages,
        writingBlock,
        draftOpts
      );
      const instructions = buildEmailDraftInstructionsBlock(
        writingBlock,
        draftOpts
      );
      if (!documentContext.includes("<email_draft_instructions>")) {
        documentContext = documentContext.trim()
          ? `${documentContext}\n\n${instructions}`
          : instructions;
      }
      if (pendingAttachments.length > 0) {
        const list = pendingAttachments
          .map((a) => `- ${a.filename} (id=${a.id}, type=${a.type})`)
          .join("\n");
        const attachBlock = `<chat_attachments>
Pièces jointes déjà fournies par l'utilisateur (NE PAS redemander) :
${list}
Elles seront attachées automatiquement au brouillon email_create_draft.
</chat_attachments>`;
        documentContext = documentContext.trim()
          ? `${documentContext}\n\n${attachBlock}`
          : attachBlock;
      }
    }

    if (route.temporal.isTimeSensitive && chatMode === "chat") {
      injectTemporalIntoContext(contextMessages, route.temporal);
    }

    if (autoSearch && !autoSearch.ok) {
      if (route.web.mandatory) {
        injectWebSearchFailureIntoContext(
          contextMessages,
          autoSearch.query,
          autoSearch.status,
          autoSearch.message
        );
      } else {
        input.onEvent({ type: "error", message: autoSearch.message });
        return;
      }
    }

    const collectedSources: SearchResult[] = [];
    if (autoSearch?.ok) {
      collectedSources.push(...autoSearch.results);
      injectWebSearchIntoContext(
        contextMessages,
        autoSearch.query,
        autoSearch.results
      );
    }

    input.onEvent({ type: "context_snapshot", snapshot: initialSnapshot });

    if (isContextDebugEnabled()) {
      debugTrace.intent = [
        route.files.intent !== "none" ? `files.${route.files.intent}` : null,
        route.email.intent !== "none" ? `email.${route.email.intent}` : null,
        route.web.mode !== "none" ? `web.${route.web.mode}` : null,
        route.knowledge,
      ]
        .filter(Boolean)
        .join("|");
      debugTrace.routeSummary = {
        knowledge: route.knowledge,
        webMode: route.web.mode,
        emailIntent: route.email.intent,
        filesIntent: route.files.intent,
      };
      debugTrace.web = {
        enabled: Boolean(autoSearch?.ok) || route.web.enabled,
        selectedCount: collectedSources.length,
        reason: autoSearch?.ok
          ? "auto_search"
          : route.web.mode === "none"
            ? "disabled"
            : "pending_tools",
      };
      debugTrace.tools = route.tools.candidates;
      input.onEvent({ type: "context_debug", trace: debugTrace });
    }

    if (chatMode === "agent" && imageCount === 0) {
      await runAgentLoop({
        conversationId: input.conversationId,
        userContent: input.userContent,
        settings,
        runtime,
        reasoningEffort,
        documentContext,
        signal: input.signal,
        onEvent: input.onEvent,
        pendingAttachmentNames: pendingAttachments.map((a) => a.filename),
        routeDecision: route,
        memoryIntent: analysis.memory,
        flushInitialMemorySaves,
        userId,
        toolCtxBase,
        emailEnabled:
          emailEnabled &&
          emailPolicyContext.emailConnected &&
          mailAssistantActive,
        emailToolCandidates: mailToolCandidates,
        accountEmail: mailAccountEmail,
        filesEnabled:
          filesEnabled && Boolean(emailPolicyContext.hasConfiguredRoots),
        fileToolCandidates: route.files.suggestedTools,
      });
      return;
    }

    await runChatMode({
      input,
      settings,
      runtime,
      contextMessages,
      initialSnapshot,
      allDbMessages,
      reasoningEffort,
      pendingAttachments,
      imageCount,
      requestId,
      collectedSources,
      routeDecision: route,
      memoryIntent: analysis.memory,
      flushInitialMemorySaves,
      toolCtxBase,
      emailEnabled: Boolean(
        emailEnabled &&
          emailPolicyContext.emailConnected &&
          mailAssistantActive
      ),
      emailToolCandidates: mailToolCandidates,
      filesEnabled: Boolean(
        filesEnabled && emailPolicyContext.hasConfiguredRoots
      ),
      fileToolCandidates: route.tools.candidates.filter((c) =>
        c.startsWith("file_")
      ),
    });
  } catch (error) {
    if (error instanceof DOMException && error.name === "AbortError") {
      return;
    }
    input.onEvent({
      type: "error",
      message: error instanceof Error ? error.message : String(error),
    });
  } finally {
    clearTimeout(timeout);
  }
}

async function runChatMode(params: {
  input: ChatOrchestratorInput;
  settings: Awaited<ReturnType<typeof getSettings>>;
  runtime: ReturnType<typeof getLocalAIRuntime>;
  contextMessages: Awaited<ReturnType<typeof buildChatContext>>["contextMessages"];
  initialSnapshot: Awaited<ReturnType<typeof buildChatContext>>["initialSnapshot"];
  allDbMessages: Awaited<ReturnType<typeof buildChatContext>>["allDbMessages"];
  reasoningEffort: string | null;
  pendingAttachments: Awaited<ReturnType<typeof getConversationAttachments>>;
  imageCount: number;
  requestId: string;
  collectedSources: SearchResult[];
  routeDecision: RouteDecision;
  memoryIntent?: MemoryIntentDecision;
  flushInitialMemorySaves?: (messageId: string) => void;
  toolCtxBase: Omit<ToolContext, "signal">;
  emailEnabled: boolean;
  emailToolCandidates: string[];
  filesEnabled: boolean;
  fileToolCandidates: string[];
}) {
  const {
    input,
    settings,
    runtime,
    contextMessages,
    initialSnapshot,
    allDbMessages,
    reasoningEffort,
    pendingAttachments,
    imageCount,
    requestId,
    collectedSources,
    routeDecision,
    memoryIntent,
    flushInitialMemorySaves,
    toolCtxBase,
    emailEnabled,
    emailToolCandidates,
    filesEnabled,
    fileToolCandidates,
  } = params;

  const db = getDb();
  const webAllowed =
    routeDecision.web.enabled && routeDecision.web.mode !== "none";
  const tools = getToolDefinitions({
    webSearchEnabled: webAllowed,
    emailEnabled,
    emailToolCandidates,
    filesEnabled,
    fileToolCandidates,
  });

  if (
    filesEnabled &&
    routeDecision.files.wouldBeUseful &&
    routeDecision.files.intent !== "none"
  ) {
    const handoff = buildFilesHandoffUrl({
      intent: routeDecision.files.intent,
      query: routeDecision.files.searchQuery,
    });
    input.onEvent({
      type: "files_handoff",
      url: handoff.url,
      intent: handoff.intent,
      query: handoff.query,
      rootId: handoff.rootId,
      reason: handoff.reason,
    });
  }

  const emitContextSnapshot = () => {
    input.onEvent({
      type: "context_snapshot",
      snapshot: snapshotFromMessages(contextMessages, settings, {
        breakdown: initialSnapshot.breakdown,
        includedMessageCount: contextMessages.filter(
          (m) => m.role === "user" || m.role === "assistant"
        ).length,
        totalMessageCount: allDbMessages.length,
        hasSummary: initialSnapshot.hasSummary,
      }),
    });
  };

  const toolCallCounts = new Map<string, number>();
  let totalToolCalls = 0;

  // Les images coupaient tout tool-calling → l'assistant mail inventait un refus
  // (« je ne peux pas envoyer de fichiers ») alors que email_create_draft existe.
  // En mode mail on garde les outils ; on rétrograde la vision en texte pour que
  // les modèles locaux puissent encore appeler l'outil.
  const allowToolLoop =
    imageCount === 0 ||
    (emailEnabled && emailToolCandidates.length > 0);

  if (allowToolLoop && imageCount > 0 && emailEnabled) {
    demoteVisionImagesForToolCalling(contextMessages, pendingAttachments);
  }

  if (allowToolLoop) {
    while (totalToolCalls < MAX_TOOL_CALLS) {
      if (input.signal?.aborted) return;

      const turn = await streamChatTurn({
        input,
        settings,
        runtime,
        contextMessages,
        tools,
        reasoningEffort,
        flushInitialMemorySaves,
      });

      if (!turn.toolCalls?.length) {
        await finalizeStreamedAssistant({
          input,
          settings,
          assistantId: turn.assistantId,
          fullContent: turn.content,
          streamedToUi: turn.streamedToUi,
          collectedSources,
          pendingAttachments,
          memoryIntent,
          flushInitialMemorySaves,
        });
        return;
      }

      if (turn.streamedToUi) {
        input.onEvent({
          type: "assistant_discard",
          messageId: turn.assistantId,
        });
      }

      contextMessages.push({
        role: "assistant",
        content: turn.content || null,
        tool_calls: turn.toolCalls.map((tc) => ({
          id: tc.id,
          type: "function" as const,
          function: { name: tc.name, arguments: tc.arguments },
        })),
      });

      const toolResults = await Promise.all(
        turn.toolCalls.map(async (tc) => {
          totalToolCalls++;
          const sameCount = (toolCallCounts.get(tc.name) ?? 0) + 1;
          toolCallCounts.set(tc.name, sameCount);

          if (sameCount > MAX_SAME_TOOL) {
            return {
              tc,
              message: {
                role: "tool" as const,
                content: JSON.stringify({
                  error: "Limite d'appels atteinte pour cet outil",
                }),
                tool_call_id: tc.id,
                name: tc.name,
              },
              sources: [] as SearchResult[],
            };
          }

          let args: unknown = {};
          try {
            args = JSON.parse(tc.arguments || "{}");
          } catch {
            args = {};
          }

          input.onEvent({
            type: "tool_start",
            tool: tc.name,
            input: sanitizeToolStartPayload(tc.name, args),
          });

          const toolCallId = nanoid();
          const start = Date.now();

          try {
            const result = await executeToolWithPolicy(tc.name, args, {
              ...toolCtxBase,
              signal:
                input.signal ??
                AbortSignal.timeout(settings.webSearchTimeoutMs + 5000),
            });

            const durationMs = Date.now() - start;
            const newSources: SearchResult[] = [];
            let toolSummary = tc.name;

            if (tc.name === "web_search") {
              const webResult = result as WebSearchOutput;
              newSources.push(...webResult.results);
              toolSummary = "Recherche Web";
              input.onEvent({
                type: "tool_done",
                tool: tc.name,
                summary: toolSummary,
                sourceCount: webResult.results.length,
              });
            } else if (
              tc.name === "file_create_directory" ||
              tc.name === "file_rename" ||
              tc.name === "file_move"
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
              toolSummary =
                pending.status === "pending_confirmation"
                  ? "Action fichiers en attente de confirmation"
                  : tc.name;
              input.onEvent({
                type: "tool_done",
                tool: tc.name,
                summary: toolSummary,
              });
              if (
                pending.status === "pending_confirmation" &&
                pending.actionId &&
                pending.confirmationToken &&
                pending.expiresAt &&
                pending.payload?.op &&
                pending.payload.destRootId &&
                pending.payload.destRelativePath
              ) {
                input.onEvent({
                  type: "file_action_pending",
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
            } else if (tc.name === "file_search" || tc.name === "file_list") {
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
                    typeof r.relativePath === "string"
                      ? r.relativePath
                      : undefined,
                  rootId: typeof r.rootId === "string" ? r.rootId : undefined,
                  sizeBytes:
                    typeof r.sizeBytes === "number" ? r.sizeBytes : undefined,
                  mtimeMs:
                    typeof r.mtimeMs === "number" ? r.mtimeMs : undefined,
                  extension:
                    typeof r.extension === "string" ? r.extension : undefined,
                }))
                .filter((f) => f.fileId.length > 0)
                .slice(0, 8);
              toolSummary =
                files.length > 0
                  ? `${files.length} fichier(s) trouvé(s)`
                  : tc.name === "file_search"
                    ? "Aucun fichier trouvé"
                    : tc.name;
              input.onEvent({
                type: "tool_done",
                tool: tc.name,
                summary: toolSummary,
                sourceCount: files.length,
              });
              if (files.length > 0) {
                input.onEvent({ type: "files_found", files });
              }
            } else if (tc.name.startsWith("email_")) {
              toolSummary = tc.name;
              input.onEvent({
                type: "tool_done",
                tool: tc.name,
                summary: toolSummary,
              });
              if (
                tc.name === "email_create_draft" &&
                result &&
                typeof result === "object" &&
                "draftId" in result
              ) {
                const draftId = (result as { draftId?: string }).draftId;
                if (draftId) {
                  const { getEmailDraftForUser, toEmailDraftPreview } =
                    await import("@/lib/email/draft");
                  const draft = await getEmailDraftForUser(
                    draftId,
                    toolCtxBase.userId ?? "local"
                  );
                  if (draft) {
                    input.onEvent({
                      type: "draft_preview",
                      draft: await toEmailDraftPreview(draft),
                    });
                  }
                }
              }
            } else {
              input.onEvent({
                type: "tool_done",
                tool: tc.name,
                summary: toolSummary,
              });
            }

            await db.insert(toolCalls).values({
              id: toolCallId,
              conversationId: input.conversationId,
              toolName: tc.name,
              input: JSON.stringify(args),
              output: JSON.stringify(result),
              status: "success",
              durationMs,
            });

            return {
              tc,
              message: {
                role: "tool" as const,
                content: compressToolResultForContext(result),
                tool_call_id: tc.id,
                name: tc.name,
              },
              sources: newSources,
            };
          } catch (error) {
            const durationMs = Date.now() - start;
            const errMsg = error instanceof Error ? error.message : String(error);

            await db.insert(toolCalls).values({
              id: toolCallId,
              conversationId: input.conversationId,
              toolName: tc.name,
              input: JSON.stringify(args),
              output: "",
              status: "error",
              error: errMsg,
              durationMs,
            });

            input.onEvent({
              type: "tool_done",
              tool: tc.name,
              summary: `Erreur: ${errMsg}`,
            });

            return {
              tc,
              message: {
                role: "tool" as const,
                content: JSON.stringify({ error: errMsg }),
                tool_call_id: tc.id,
                name: tc.name,
              },
              sources: [] as SearchResult[],
            };
          }
        })
      );

      for (const result of toolResults) {
        contextMessages.push(result.message);
        mergeUniqueSources(collectedSources, result.sources, { maxTotal: 25 });
      }

      emitContextSnapshot();
    }
  }

  await streamFinalResponse({
    input,
    settings,
    runtime,
    contextMessages,
    collectedSources,
    pendingAttachments,
    reasoningEffort,
    requestId,
    memoryIntent,
    flushInitialMemorySaves,
  });
}

async function streamFinalResponse(params: {
  input: ChatOrchestratorInput;
  settings: Awaited<ReturnType<typeof getSettings>>;
  runtime: ReturnType<typeof getLocalAIRuntime>;
  contextMessages: Awaited<ReturnType<typeof buildChatContext>>["contextMessages"];
  collectedSources: SearchResult[];
  pendingAttachments: Awaited<ReturnType<typeof getConversationAttachments>>;
  reasoningEffort: string | null;
  requestId?: string;
  memoryIntent?: MemoryIntentDecision;
  flushInitialMemorySaves?: (messageId: string) => void;
}) {
  const {
    input,
    settings,
    runtime,
    contextMessages,
    collectedSources,
    pendingAttachments,
    reasoningEffort,
    requestId,
    memoryIntent,
    flushInitialMemorySaves,
  } = params;

  const assistantId = nanoid();
  let fullContent = "";

  input.onEvent({ type: "assistant_start", messageId: assistantId });
  flushInitialMemorySaves?.(assistantId);

  await runtime.stream(
    {
      requestId: requestId ?? nanoid(),
      model: settings.selectedModel,
      messages: contextMessages,
      temperature: settings.temperature,
      maxTokens: settings.maxTokens,
      signal: input.signal,
      reasoningEffort,
      streamContentOnly: true,
    },
    {
      onToken: (token) => {
        fullContent += token;
        input.onEvent({ type: "token", content: token });
      },
      onUsage: (usage) => {
        input.onEvent({ type: "generation_usage", usage });
      },
      onDone: () => {},
      onError: (err) => {
        throw err;
      },
    }
  );

  if (!fullContent) {
    fullContent = "Je n'ai pas pu générer de réponse.";
    input.onEvent({ type: "token", content: fullContent });
  }

  if (collectedSources.length > 0) {
    const capped = dedupeAndCapSources(collectedSources, 20);
    input.onEvent({ type: "sources", sources: capped });
  }

  input.onEvent({ type: "done", messageId: assistantId });

  void persistAssistantMessage({
    input,
    settings,
    assistantId,
    fullContent,
    collectedSources: dedupeAndCapSources(collectedSources, 20),
    pendingAttachments,
    memoryIntent,
  }).catch((error) => {
    input.onEvent({
      type: "error",
      message:
        error instanceof Error
          ? `Erreur de sauvegarde: ${error.message}`
          : "Erreur de sauvegarde",
    });
  });
}

/**
 * Remplace les parts vision (image_url) par du texte listant les PJ.
 * Les modèles locaux gèrent mal tools + vision dans le même tour ; pour le mail
 * la PJ n'a pas besoin d'être « vue » — elle est auto-attachée via pendingAttachmentIds.
 */
function demoteVisionImagesForToolCalling(
  contextMessages: Array<{
    role: string;
    content:
      | string
      | Array<{ type: string; text?: string; image_url?: { url: string } }>
      | null;
  }>,
  pendingAttachments: Array<{ id: string; filename: string; type: string }>
): void {
  const imageList = pendingAttachments
    .filter((a) => a.type === "image")
    .map((a) => `${a.filename} (id=${a.id})`);
  const fallbackNotice =
    imageList.length > 0
      ? `[Pièces jointes images déjà fournies — à attacher via email_create_draft : ${imageList.join(", ")}]`
      : `[Pièces jointes images déjà fournies — à attacher via email_create_draft]`;

  for (const msg of contextMessages) {
    if (msg.role !== "user" || !Array.isArray(msg.content)) continue;
    const texts: string[] = [];
    let imageParts = 0;
    for (const part of msg.content) {
      if (part.type === "text" && part.text?.trim()) {
        texts.push(part.text.trim());
      } else if (part.type === "image_url") {
        imageParts += 1;
      }
    }
    if (imageParts === 0) continue;
    const base = texts.join("\n\n").trim();
    msg.content = base.includes("[Pièces jointes")
      ? base
      : base
        ? `${base}\n\n${fallbackNotice}`
        : fallbackNotice;
  }
}