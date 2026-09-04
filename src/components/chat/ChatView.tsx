"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import type { SearchResult } from "@/lib/tools/types";
import type { ContextSnapshot } from "@/lib/context/builder";
import type { RuntimeStatus, RuntimeUsage, ModelRuntimeSnapshot } from "@/lib/runtime/types";
import type { WebSearchPhase } from "@/components/chat/WebSearchActivity";
import { ChatInput } from "@/components/chat/ChatInput";
import { ChatHeader } from "@/components/chat/ChatHeader";
import { MessageList } from "@/components/chat/MessageList";
import { useAgentUiState } from "@/components/chat/useAgentUiState";
import type { OrchestratorEvent } from "@/lib/agent/events";
import type { SavedMemoryItem } from "@/lib/memory/saved-memory";
import type { ChatMode } from "@/lib/agent/types";
import type { MailHandoffInfo } from "@/components/mail/MailHandoffCard";
import type { ModelOption } from "@/components/chat/ModelSelector";
import type { WebRuntimeStatus } from "@/components/layout/WebStatusBadge";
import { resolveReasoningMode, normalizeAppDefaultReasoningMode } from "@/lib/runtime/reasoning-types";
import type { ReasoningCapabilities } from "@/lib/runtime/reasoning-types";
import { applyEditToLocalMessages } from "@/components/chat/user-message-edit";
import { useConversations } from "@/components/chat/ConversationsProvider";
import { useToast } from "@/components/ui/Toast";
import { ScrollToBottomButton } from "@/components/chat/ScrollToBottomButton";
import {
  isScrolledUpFromBottom,
  smoothScrollToBottom,
} from "@/lib/utils/smooth-scroll";
import {
  peekCachedMessages,
  putCachedMessages,
} from "@/lib/client/conversation-messages-cache";
import { apiFetch, ApiAuthError, ApiNetworkError } from "@/lib/client/api-fetch";

async function readJson<T>(response: Response): Promise<T> {
  return (await response.json()) as T;
}

interface ConversationRecord {
  id: string;
  title?: string;
  reasoningEffort?: string | null;
  chatMode?: string;
}

interface SettingsRecord {
  selectedModel?: string;
  webSearchEnabled?: boolean;
  defaultReasoningEffort?: string | null;
  contextLength?: number;
}

interface MessageSource {
  id: string;
  title: string;
  domain: string;
  url: string;
  snippet: string | null;
}

interface MessageAttachment {
  id: string;
  filename: string;
  mimeType: string;
  sizeBytes: number;
  type: string;
}

interface ChatMessage {
  id: string;
  role: string;
  content: string;
  streaming?: boolean;
  sources?: MessageSource[];
  attachments?: MessageAttachment[];
  savedMemories?: SavedMemoryItem[];
  mailHandoff?: MailHandoffInfo;
  filesHandoff?: import("@/components/files/FilesHandoffCard").FilesHandoffInfo;
  filesFound?: import("@/components/files/FilesFoundCard").FilesFoundItem[];
  filesMutationPending?: import("@/components/files/FilesMutationConfirmation").FilesMutationPending;
}

interface ChatViewProps {
  conversationId: string;
  initialTitle?: string;
  initialReasoningEffort?: string | null;
  initialChatMode?: ChatMode;
  initialMessages?: ChatMessage[];
}

function getInitialMessages(
  conversationId: string,
  initialMessages?: ChatMessage[]
): ChatMessage[] {
  if (conversationId === "new") return [];
  if (initialMessages !== undefined) return initialMessages;
  return peekCachedMessages<ChatMessage>(conversationId) ?? [];
}

export function ChatView({
  conversationId,
  initialTitle,
  initialReasoningEffort,
  initialChatMode,
  initialMessages,
}: ChatViewProps) {
  const {
    conversations,
    refreshConversations,
  } = useConversations();
  const [activeConversationId, setActiveConversationId] = useState(conversationId);
  const [messages, setMessages] = useState<ChatMessage[]>(() =>
    getInitialMessages(conversationId, initialMessages)
  );
  const [title, setTitle] = useState(initialTitle ?? "Conversation");
  const [isGenerating, setIsGenerating] = useState(false);
  const [runtimeStatus, setRuntimeStatus] = useState<RuntimeStatus>("OFFLINE");
  const [webStatus, setWebStatus] = useState<WebRuntimeStatus>("unavailable");
  const [webStatusMessage, setWebStatusMessage] = useState<string | undefined>();
  const [modelRuntime, setModelRuntime] = useState<ModelRuntimeSnapshot | null>(
    null
  );
  const [selectedModel, setSelectedModel] = useState("");
  const [modelOptions, setModelOptions] = useState<ModelOption[]>([]);
  const [modelsLoading, setModelsLoading] = useState(true);
  const [reasoningEffort, setReasoningEffort] = useState<string | null>(
    initialReasoningEffort ?? "off"
  );
  const [defaultReasoningEffort, setDefaultReasoningEffort] = useState<string | null>("off");
  const [contextSnapshot, setContextSnapshot] = useState<ContextSnapshot | null>(null);
  const [contextLoading, setContextLoading] = useState(false);
  const [lastGenerationUsage, setLastGenerationUsage] = useState<RuntimeUsage | null>(null);
  const pendingAttachmentIdsRef = useRef<string[]>([]);
  const activeConversationIdRef = useRef(activeConversationId);
  activeConversationIdRef.current = activeConversationId;
  const [webSearchActivity, setWebSearchActivity] = useState<{
    phase: WebSearchPhase;
    query?: string;
    sourceCount?: number;
  }>({ phase: "idle" });
  const [toolState, setToolState] = useState<{
    status: "idle" | "running" | "done";
    tool?: string;
    summary?: string;
    sourceCount?: number;
  }>({ status: "idle" });
  const [editingMessageId, setEditingMessageId] = useState<string | null>(null);
  const [chatMode, setChatMode] = useState<ChatMode>(initialChatMode ?? "chat");
  const [webSearchEnabled, setWebSearchEnabled] = useState(true);
  const { agentUi, handleAgentEvent, resetAgentUi } = useAgentUiState();
  const { toast } = useToast();

  const abortRef = useRef<AbortController | null>(null);
  const streamingAssistantIdRef = useRef<string | null>(null);
  const pendingSourcesRef = useRef<MessageSource[]>([]);
  const pendingFilesHandoffRef = useRef<
    import("@/components/files/FilesHandoffCard").FilesHandoffInfo | null
  >(null);
  const pendingFilesFoundRef = useRef<
    import("@/components/files/FilesFoundCard").FilesFoundItem[] | null
  >(null);
  const bottomRef = useRef<HTMLDivElement>(null);
  const scrollContainerRef = useRef<HTMLDivElement>(null);
  const userScrolledRef = useRef(false);
  const [showScrollToBottom, setShowScrollToBottom] = useState(false);
  const loadGenerationRef = useRef(0);

  const updateScrollToBottomVisibility = useCallback(() => {
    const el = scrollContainerRef.current;
    if (!el) return;
    setShowScrollToBottom(isScrolledUpFromBottom(el));
  }, []);

  const scrollToBottom = useCallback((force = false) => {
    if (!force && userScrolledRef.current) return;
    const el = scrollContainerRef.current;
    if (!el) return;
    el.scrollTo({
      top: el.scrollHeight,
      behavior: force ? "auto" : "auto",
    });
    if (force) {
      setShowScrollToBottom(false);
    }
  }, []);

  const handleScrollToBottomClick = useCallback(() => {
    userScrolledRef.current = false;
    const el = scrollContainerRef.current;
    if (!el) return;
    smoothScrollToBottom(el);
  }, []);

  const loadConversations = refreshConversations;

  const reconcileWithServerMessages = useCallback(
    (local: ChatMessage[], server: ChatMessage[]): ChatMessage[] => {
      const serverById = new Map(server.map((m) => [m.id, m]));
      const claimedServerIds = new Set<string>();

      const reconciled = local.map((localMsg) => {
        const serverMsg = serverById.get(localMsg.id);
        if (serverMsg) {
          claimedServerIds.add(serverMsg.id);
          if (localMsg.streaming) {
            return {
              ...serverMsg,
              content: localMsg.content || serverMsg.content,
              sources: localMsg.sources ?? serverMsg.sources,
              streaming: true,
            };
          }
          return { ...serverMsg, streaming: false };
        }

        if (localMsg.id.startsWith("pending-user-")) {
          const match = server.find(
            (s) =>
              s.role === "user" &&
              !claimedServerIds.has(s.id) &&
              s.content === localMsg.content
          );
          if (match) {
            claimedServerIds.add(match.id);
            return {
              ...match,
              attachments: match.attachments ?? localMsg.attachments,
              streaming: false,
            };
          }
        }

        return localMsg;
      });

      for (const serverMsg of server) {
        if (!claimedServerIds.has(serverMsg.id)) {
          reconciled.push({ ...serverMsg, streaming: false });
        }
      }

      return reconciled;
    },
    []
  );

  const loadMessages = useCallback(
    async (id: string, options?: { merge?: boolean }): Promise<ChatMessage[]> => {
      const generation = ++loadGenerationRef.current;

      if (id === "new") {
        setMessages([]);
        return [];
      }
      const res = await fetch(`/api/conversations/${id}/messages`);
      if (generation !== loadGenerationRef.current) return [];
      if (res.ok) {
        const data = (await res.json()) as { messages: ChatMessage[] };
        const serverMessages = data.messages;
        putCachedMessages(id, serverMessages);
        if (generation !== loadGenerationRef.current) return [];
        if (options?.merge) {
          setMessages((prev) => reconcileWithServerMessages(prev, serverMessages));
        } else {
          setMessages(serverMessages);
        }
        return serverMessages;
      }
      return [];
    },
    [reconcileWithServerMessages]
  );

  const refreshContextUsage = useCallback(
    async (convId?: string) => {
      const id = convId ?? activeConversationIdRef.current;
      if (id === "new") {
        const { cachedGetJson } = await import("@/lib/client/fetch-cache");
        const settingsRes = await cachedGetJson<SettingsRecord>("/api/settings", {
          ttlMs: 30_000,
        });
        if (settingsRes.ok) {
          const s = settingsRes.data;
          setContextSnapshot({
            conversationTokens: 0,
            contextLengthMax: s.contextLength ?? 0,
            budgetTokens: Math.floor((s.contextLength ?? 0) * 0.9),
            usedPercent: 0,
            remainingPercent: 100,
            breakdown: {
              system: 0,
              memories: 0,
              summary: 0,
              documents: 0,
              tools: 0,
              messages: 0,
              images: 0,
            },
            includedMessageCount: 0,
            totalMessageCount: 0,
            hasSummary: false,
            estimator: "fallback",
          });
        }
        return;
      }
      setContextLoading(true);
      try {
        const params = new URLSearchParams();
        for (const attId of pendingAttachmentIdsRef.current) {
          params.append("attachmentId", attId);
        }
        const qs = params.toString();
        const res = await fetch(
          `/api/conversations/${id}/context${qs ? `?${qs}` : ""}`
        );
        if (res.ok) setContextSnapshot(await readJson<ContextSnapshot>(res));
      } finally {
        setContextLoading(false);
      }
    },
    []
  );

  const handleAttachmentsChange = useCallback((ids: string[]) => {
    pendingAttachmentIdsRef.current = ids;
    void refreshContextUsage();
  }, [refreshContextUsage]);

  const applyRuntimePayload = useCallback(
    (data: {
      status?: RuntimeStatus;
      model?: ModelRuntimeSnapshot;
      message?: string;
    }) => {
      if (data.status) setRuntimeStatus(data.status);
      if (data.model) setModelRuntime(data.model);
    },
    []
  );

  const loadRuntimeStatus = useCallback(async () => {
    setModelsLoading(true);
    const { cachedGetJson } = await import("@/lib/client/fetch-cache");
    const [statusRes, webRes, settingsRes, modelsRes] = await Promise.all([
      cachedGetJson<{
        status?: RuntimeStatus;
        model?: ModelRuntimeSnapshot;
        message?: string;
      }>("/api/runtime/status", { ttlMs: 5_000 }),
      cachedGetJson<{ status?: WebRuntimeStatus; message?: string }>(
        "/api/runtime/web-status",
        { ttlMs: 5_000 }
      ),
      cachedGetJson<SettingsRecord>("/api/settings", { ttlMs: 30_000 }),
      cachedGetJson<{ data?: Array<{ id: string; name: string }> }>(
        "/api/lm-studio/models",
        { ttlMs: 60_000 }
      ),
    ]);
    if (statusRes.ok) {
      applyRuntimePayload(statusRes.data);
    }
    if (webRes.ok) {
      if (webRes.data.status) setWebStatus(webRes.data.status);
      setWebStatusMessage(webRes.data.message);
    }
    if (settingsRes.ok) {
      const settings = settingsRes.data;
      setSelectedModel(settings.selectedModel || "");
      setWebSearchEnabled(settings.webSearchEnabled ?? true);
      setDefaultReasoningEffort(
        normalizeAppDefaultReasoningMode(settings.defaultReasoningEffort)
      );
    }
    if (modelsRes.ok) {
      setModelOptions(
        (modelsRes.data.data ?? []).map((m) => ({
          id: m.id,
          label: m.name,
        }))
      );
    }
    setModelsLoading(false);
  }, [applyRuntimePayload]);

  const loadConversationMeta = useCallback(async (id: string) => {
    const appDefault = normalizeAppDefaultReasoningMode(defaultReasoningEffort);
    const { cachedGetJson } = await import("@/lib/client/fetch-cache");

    if (id === "new") {
      const modelId = selectedModel;
      if (!modelId) {
        setReasoningEffort(appDefault);
        return;
      }
      try {
        const capsRes = await cachedGetJson<ReasoningCapabilities>(
          `/api/runtime/reasoning-capabilities?model=${encodeURIComponent(modelId)}`,
          { ttlMs: 60_000 }
        );
        if (capsRes.ok) {
          setReasoningEffort(
            resolveReasoningMode(appDefault, capsRes.data) ?? appDefault
          );
          return;
        }
      } catch {
        // fall through
      }
      setReasoningEffort(appDefault);
      return;
    }
    const [convRes, settingsRes] = await Promise.all([
      fetch(`/api/conversations/${id}`),
      cachedGetJson<SettingsRecord>("/api/settings", { ttlMs: 30_000 }),
    ]);
    if (!convRes.ok) return;
    const conv = await readJson<ConversationRecord>(convRes);
    setChatMode((conv.chatMode as ChatMode) ?? "chat");
    const settings = settingsRes.ok ? settingsRes.data : null;
    const modelId = settings?.selectedModel ?? selectedModel;
    if (!modelId) {
      setReasoningEffort(conv.reasoningEffort ?? appDefault);
      return;
    }
    try {
      const capsRes = await cachedGetJson<ReasoningCapabilities>(
        `/api/runtime/reasoning-capabilities?model=${encodeURIComponent(modelId)}`,
        { ttlMs: 60_000 }
      );
      if (capsRes.ok) {
        setReasoningEffort(
          resolveReasoningMode(conv.reasoningEffort ?? appDefault, capsRes.data) ??
            appDefault
        );
        return;
      }
    } catch {
      // fall through
    }
    setReasoningEffort(conv.reasoningEffort ?? appDefault);
  }, [defaultReasoningEffort, selectedModel]);

  useEffect(() => {
    if (conversationId !== "new" || initialReasoningEffort !== undefined) return;
    void loadConversationMeta("new");
  }, [
    conversationId,
    initialReasoningEffort,
    defaultReasoningEffort,
    selectedModel,
    loadConversationMeta,
  ]);

  useEffect(() => {
    if (conversationId !== "new") {
      setActiveConversationId(conversationId);
    } else {
      setActiveConversationId("new");
    }
    userScrolledRef.current = false;
    setTitle(
      initialTitle ??
        (conversationId === "new" ? "Nouvelle conversation" : "Conversation")
    );

    // RSC already provided messages → paint immediately, cache, skip blocking refetch
    if (conversationId !== "new" && initialMessages !== undefined) {
      setMessages(initialMessages);
      putCachedMessages(conversationId, initialMessages);
      requestAnimationFrame(() => scrollToBottom(true));
    } else {
      void loadMessages(conversationId).then(() => {
        requestAnimationFrame(() => scrollToBottom(true));
      });
    }

    // Context meter is non-critical for first paint
    let cancelled = false;
    const contextTimer = window.setTimeout(() => {
      if (!cancelled) void refreshContextUsage(conversationId);
    }, 150);

    if (initialReasoningEffort !== undefined) {
      setReasoningEffort(initialReasoningEffort);
    } else {
      void loadConversationMeta(conversationId);
    }

    return () => {
      cancelled = true;
      window.clearTimeout(contextTimer);
    };
  }, [
    conversationId,
    initialTitle,
    initialReasoningEffort,
    initialMessages,
    loadMessages,
    loadConversationMeta,
    refreshContextUsage,
    scrollToBottom,
  ]);

  useEffect(() => {
    loadRuntimeStatus();
    const interval = setInterval(() => {
      void fetch("/api/runtime/web-status")
        .then(async (r) =>
          r.ok
            ? readJson<{ status?: WebRuntimeStatus; message?: string }>(r)
            : null
        )
        .then((data) => {
          if (!data?.status) return;
          setWebStatus(data.status);
          setWebStatusMessage(data.message);
        })
        .catch(() => undefined);
    }, 10_000);
    return () => clearInterval(interval);
  }, [loadRuntimeStatus]);

  useEffect(() => {
    const phase = modelRuntime?.phase;
    if (phase !== "loading" && phase !== "unloading") return;

    const interval = setInterval(() => {
      void fetch("/api/runtime/status")
        .then(async (r) =>
          r.ok
            ? readJson<{
                status?: RuntimeStatus;
                model?: ModelRuntimeSnapshot;
                message?: string;
              }>(r)
            : null
        )
        .then((data) => {
          if (data) applyRuntimePayload(data);
        })
        .catch(() => undefined);
    }, 800);

    return () => clearInterval(interval);
  }, [modelRuntime?.phase, applyRuntimePayload]);

  useEffect(() => {
    if (!selectedModel) return;
    let cancelled = false;
    fetch(
      `/api/runtime/reasoning-capabilities?model=${encodeURIComponent(selectedModel)}`
    )
      .then((r) => readJson<ReasoningCapabilities>(r))
      .then((caps) => {
        if (cancelled) return;
        setReasoningEffort(
          (prev) =>
            resolveReasoningMode(prev, caps) ?? prev
        );
      })
      .catch(() => undefined);
    return () => {
      cancelled = true;
    };
  }, [selectedModel]);

  useEffect(() => {
    updateScrollToBottomVisibility();
  }, [messages, updateScrollToBottomVisibility]);

  const mapSources = useCallback(
    (sources: SearchResult[]): MessageSource[] =>
      sources.map((s) => ({
        id: s.url,
        title: s.title,
        domain: s.domain,
        url: s.url,
        snippet: s.snippet ?? null,
      })),
    []
  );

  const appendAssistantToken = useCallback((assistantId: string, token: string) => {
    setMessages((prev) =>
      prev.map((m) =>
        m.id === assistantId ? { ...m, content: m.content + token } : m
      )
    );
  }, []);

  const ensureStreamingAssistant = useCallback((messageId: string) => {
    streamingAssistantIdRef.current = messageId;
    const pendingSources = pendingSourcesRef.current;
    const pendingHandoff = pendingFilesHandoffRef.current;
    const pendingFound = pendingFilesFoundRef.current;
    pendingFilesHandoffRef.current = null;
    pendingFilesFoundRef.current = null;
    setMessages((prev) => {
      const patch = {
        ...(pendingSources.length > 0 ? { sources: pendingSources } : {}),
        ...(pendingHandoff ? { filesHandoff: pendingHandoff } : {}),
        ...(pendingFound?.length ? { filesFound: pendingFound } : {}),
      };
      if (prev.some((m) => m.id === messageId)) {
        if (Object.keys(patch).length === 0) return prev;
        return prev.map((m) =>
          m.id === messageId ? { ...m, ...patch } : m
        );
      }
      return [
        ...prev,
        {
          id: messageId,
          role: "assistant",
          content: "",
          streaming: true,
          ...patch,
        },
      ];
    });
  }, []);

  const ensureConversationId = useCallback(async () => {
    if (activeConversationId !== "new") return activeConversationId;
    const createRes = await fetch("/api/conversations", { method: "POST" });
    if (!createRes.ok) throw new Error("Impossible de créer la conversation");
    const conv = await readJson<ConversationRecord>(createRes);
    const id = conv.id as string;
    setActiveConversationId(id);
    window.history.replaceState(null, "", `/chat/${id}`);
    if (reasoningEffort && reasoningEffort !== conv.reasoningEffort) {
      await fetch(`/api/conversations/${id}`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ reasoningEffort }),
      });
    } else if (conv.reasoningEffort) {
      setReasoningEffort(conv.reasoningEffort);
    }
    if (chatMode !== conv.chatMode) {
      await fetch(`/api/conversations/${id}`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ chatMode }),
      });
    } else if (conv.chatMode) {
      setChatMode(conv.chatMode as ChatMode);
    }
    return id;
  }, [activeConversationId, reasoningEffort, chatMode]);

  const sendMessage = async (
    content: string,
    attachmentIds: string[] = [],
    options: boolean | { regenerate?: boolean; editMessageId?: string } = false
  ) => {
    const regenerate =
      typeof options === "boolean" ? options : (options.regenerate ?? false);
    const editMessageId =
      typeof options === "boolean" ? undefined : options.editMessageId;

    setIsGenerating(true);
    setToolState({ status: "idle" });
    setWebSearchActivity({ phase: "idle" });
    resetAgentUi();
    pendingSourcesRef.current = [];
    streamingAssistantIdRef.current = null;
    userScrolledRef.current = false;

    if (editMessageId) {
      setEditingMessageId(null);
      setMessages((prev) =>
        applyEditToLocalMessages(prev, editMessageId, content)
      );
    } else if (regenerate) {
      setMessages((prev) => {
        const lastAssistantIdx = prev.map((m) => m.role).lastIndexOf("assistant");
        if (lastAssistantIdx === -1) return prev;
        return prev.slice(0, lastAssistantIdx);
      });
    } else {
      setMessages((prev) => [
        ...prev,
        {
          id: `pending-user-${Date.now()}`,
          role: "user",
          content,
          ...(attachmentIds.length > 0
            ? {
                attachments: attachmentIds.map((id) => ({
                  id,
                  filename: "Pièce jointe",
                  mimeType: "",
                  sizeBytes: 0,
                  type: "document",
                })),
              }
            : {}),
        },
      ]);
    }

    requestAnimationFrame(() => scrollToBottom(true));

    abortRef.current = new AbortController();
    let streamConvId = activeConversationId;

    try {
      if (streamConvId === "new" && !regenerate && !editMessageId) {
        streamConvId = await ensureConversationId();
        void refreshContextUsage(streamConvId);
      }

      const res = await apiFetch("/api/chat", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          conversationId: streamConvId,
          message: content,
          attachmentIds,
          regenerate,
          editMessageId,
          mode: chatMode,
        }),
        signal: abortRef.current.signal,
      });

      if (!res.ok || !res.body) throw new Error("Erreur de connexion");

      const reader = res.body.getReader();
      const decoder = new TextDecoder();
      let buffer = "";
      let streamHadError = false;

      while (true) {
        const { done, value } = await reader.read();
        if (done) break;

        buffer += decoder.decode(value, { stream: true });
        const parts = buffer.split("\n\n");
        buffer = parts.pop() ?? "";

        for (const part of parts) {
          const line = part.trim();
          if (!line.startsWith("data: ")) continue;
          const event = JSON.parse(line.slice(6)) as OrchestratorEvent;

          switch (event.type) {
            case "assistant_start":
              if (event.messageId) ensureStreamingAssistant(event.messageId);
              break;
            case "assistant_discard":
              if (event.messageId) {
                setMessages((prev) =>
                  prev.filter((m) => m.id !== event.messageId)
                );
                if (streamingAssistantIdRef.current === event.messageId) {
                  streamingAssistantIdRef.current = null;
                }
              }
              break;
            case "context_snapshot":
              if (event.snapshot) setContextSnapshot(event.snapshot);
              break;
            case "context_debug":
              if (process.env.NODE_ENV !== "production") {
                console.debug("[context_debug]", event.trace);
              }
              break;
            case "route_decision":
              if (process.env.NODE_ENV !== "production") {
                console.debug("[route_decision]", event.decision);
              }
              break;
            case "memory_intent":
              if (process.env.NODE_ENV !== "production") {
                console.debug("[memory_intent]", event.decision);
              }
              break;
            case "memory_saved":
              if (event.messageId && event.memories?.length) {
                setMessages((prev) =>
                  prev.map((m) => {
                    if (m.id !== event.messageId) return m;
                    const existing = m.savedMemories ?? [];
                    const merged = [...existing];
                    for (const memory of event.memories) {
                      if (!merged.some((item) => item.id === memory.id)) {
                        merged.push(memory);
                      }
                    }
                    return { ...m, savedMemories: merged };
                  })
                );
              }
              break;
            case "mail_handoff": {
              const assistantId = streamingAssistantIdRef.current;
              if (assistantId) {
                setMessages((prev) =>
                  prev.map((m) =>
                    m.id === assistantId
                      ? {
                          ...m,
                          mailHandoff: {
                            intent: event.intent,
                            reason: event.reason,
                            query: event.query,
                            threadId: event.threadId,
                            label: event.label,
                            url: event.url,
                          },
                        }
                      : m
                  )
                );
              }
              break;
            }
            case "files_handoff": {
              const assistantId = streamingAssistantIdRef.current;
              const handoff = {
                intent: event.intent,
                reason: event.reason,
                query: event.query,
                rootId: event.rootId,
                url: event.url,
              };
              if (assistantId) {
                setMessages((prev) =>
                  prev.map((m) =>
                    m.id === assistantId
                      ? {
                          ...m,
                          filesHandoff: handoff,
                        }
                      : m
                  )
                );
              } else {
                // Buffer jusqu'à assistant_start (handoff peut arriver avant)
                pendingFilesHandoffRef.current = handoff;
              }
              break;
            }
            case "files_found": {
              const assistantId = streamingAssistantIdRef.current;
              const files = (event.files ?? []) as import("@/components/files/FilesFoundCard").FilesFoundItem[];
              if (assistantId && files.length > 0) {
                setMessages((prev) =>
                  prev.map((m) =>
                    m.id === assistantId
                      ? {
                          ...m,
                          filesFound: files,
                        }
                      : m
                  )
                );
              } else if (files.length > 0) {
                pendingFilesFoundRef.current = files;
              }
              break;
            }
            case "file_action_pending": {
              const assistantId = streamingAssistantIdRef.current;
              if (assistantId) {
                setMessages((prev) =>
                  prev.map((m) =>
                    m.id === assistantId
                      ? {
                          ...m,
                          filesMutationPending: {
                            actionId: event.actionId,
                            confirmationToken: event.confirmationToken,
                            expiresAt: event.expiresAt,
                            op: event.op,
                            payload: event.payload,
                            notice: event.notice,
                          },
                        }
                      : m
                  )
                );
              }
              break;
            }
            case "generation_usage":
              if (event.usage) setLastGenerationUsage(event.usage);
              break;
            case "token": {
              const token = event.content ?? "";
              setWebSearchActivity({ phase: "idle" });
              const assistantId = streamingAssistantIdRef.current;
              if (assistantId) {
                appendAssistantToken(assistantId, token);
              }
              scrollToBottom();
              break;
            }
            case "runtime_status":
              if (event.status && typeof event.status === "string") {
                const runtimeStatuses: RuntimeStatus[] = [
                  "OFFLINE",
                  "STARTING",
                  "BOOTING_SERVICES",
                  "LOADING_MODEL",
                  "READY",
                  "BUSY",
                  "STOPPING",
                  "ERROR",
                ];
                if (runtimeStatuses.includes(event.status as RuntimeStatus)) {
                  setRuntimeStatus(event.status as RuntimeStatus);
                  if (event.message) {
                    setModelRuntime((prev) =>
                      prev ? { ...prev, message: event.message } : prev
                    );
                  }
                }
              }
              break;
            case "tool_start":
              if (event.tool === "web_search") {
                const query = (event.input as { query?: string } | undefined)?.query;
                setWebSearchActivity({ phase: "searching", query });
              }
              setToolState({
                status: "running",
                tool: event.tool,
              });
              break;
            case "tool_done":
              if (event.tool === "web_search") {
                setWebSearchActivity((prev) => ({
                  ...prev,
                  phase: "done",
                  sourceCount: event.sourceCount ?? prev.sourceCount,
                }));
              }
              setToolState({
                status: "done",
                tool: event.tool,
                summary: event.summary,
                sourceCount: event.sourceCount,
              });
              break;
            case "sources":
              if (event.sources) {
                const mapped = mapSources(event.sources);
                pendingSourcesRef.current = mapped;
                setWebSearchActivity((prev) => ({
                  ...prev,
                  phase: "analyzing",
                  sourceCount: mapped.length,
                }));
                const assistantId = streamingAssistantIdRef.current;
                if (assistantId) {
                  setMessages((prev) =>
                    prev.map((m) =>
                      m.id === assistantId ? { ...m, sources: mapped } : m
                    )
                  );
                }
              }
              break;
            case "conversation_title":
              setTitle(event.title);
              void loadConversations({ bust: true });
              break;
            case "done":
              if (streamingAssistantIdRef.current) {
                const assistantId = streamingAssistantIdRef.current;
                setMessages((prev) =>
                  prev.map((m) =>
                    m.id === assistantId ? { ...m, streaming: false } : m
                  )
                );
              }
              if (event.messageId) streamingAssistantIdRef.current = event.messageId;
              break;
            case "error": {
              const aborted = event.code === "ABORTED";
              if (aborted) {
                // Stop / background — pas une erreur utilisateur
                if (streamingAssistantIdRef.current) {
                  const assistantId = streamingAssistantIdRef.current;
                  setMessages((prev) =>
                    prev.map((m) =>
                      m.id === assistantId ? { ...m, streaming: false } : m
                    )
                  );
                }
                setIsGenerating(false);
                break;
              }
              streamHadError = true;
              const message = event.message ?? "Erreur inconnue";
              let assistantId = streamingAssistantIdRef.current;
              if (!assistantId) {
                assistantId = `error-${Date.now()}`;
                streamingAssistantIdRef.current = assistantId;
                setMessages((prev) => [
                  ...prev,
                  {
                    id: assistantId!,
                    role: "assistant",
                    content: `**Erreur:** ${message}`,
                    streaming: false,
                  },
                ]);
              } else {
                appendAssistantToken(assistantId, `\n\n**Erreur:** ${message}`);
                setMessages((prev) =>
                  prev.map((m) =>
                    m.id === assistantId ? { ...m, streaming: false } : m
                  )
                );
              }
              setIsGenerating(false);
              break;
            }
            case "agent_start":
            case "agent_plan":
            case "agent_step_update":
            case "agent_action_start":
            case "agent_action_done":
            case "agent_status":
            case "agent_done":
              handleAgentEvent(event);
              break;
            case "agent_limit_reached":
              break;
          }
        }
      }

      setToolState({ status: "idle" });
      setWebSearchActivity({ phase: "idle" });
      setIsGenerating(false);
      streamingAssistantIdRef.current = null;
      if (!streamHadError) {
        await loadMessages(streamConvId, { merge: true });
      }

      await refreshContextUsage(streamConvId);
      await loadConversations({ bust: true });
      const convRes = await fetch(`/api/conversations/${streamConvId}`);
      if (convRes.ok) {
        const conv = await readJson<ConversationRecord>(convRes);
        setTitle(conv.title ?? "Conversation");
      }
    } catch (error) {
      if (error instanceof Error && error.name === "AbortError") {
        if (streamingAssistantIdRef.current) {
          const assistantId = streamingAssistantIdRef.current;
          setMessages((prev) =>
            prev.map((m) =>
              m.id === assistantId ? { ...m, streaming: false } : m
            )
          );
        }
        setToolState({ status: "idle" });
        setWebSearchActivity({ phase: "idle" });
        setIsGenerating(false);
        streamingAssistantIdRef.current = null;
        if (streamConvId && streamConvId !== "new") {
          await loadMessages(streamConvId, { merge: true });
        }
      } else if (error instanceof ApiAuthError || error instanceof ApiNetworkError) {
        // SessionGuards / offline banner gèrent l’UX ; stoppe le stream proprement.
        if (streamingAssistantIdRef.current) {
          const assistantId = streamingAssistantIdRef.current;
          setMessages((prev) =>
            prev.map((m) =>
              m.id === assistantId ? { ...m, streaming: false } : m
            )
          );
        }
        setToolState({ status: "idle" });
        setWebSearchActivity({ phase: "idle" });
        setIsGenerating(false);
        streamingAssistantIdRef.current = null;
      } else if (error instanceof Error) {
        const assistantId = streamingAssistantIdRef.current;
        if (assistantId) {
          setMessages((prev) =>
            prev.map((m) =>
              m.id === assistantId
                ? {
                    ...m,
                    content: `Erreur: ${error.message}`,
                    streaming: false,
                  }
                : m
            )
          );
        }
        setWebSearchActivity({ phase: "idle" });
        setIsGenerating(false);
        streamingAssistantIdRef.current = null;
      }
    } finally {
      abortRef.current = null;
      void fetch("/api/runtime/status")
        .then(async (r) =>
          r.ok
            ? readJson<{
                status?: RuntimeStatus;
                model?: ModelRuntimeSnapshot;
                message?: string;
              }>(r)
            : null
        )
        .then((data) => {
          if (data) applyRuntimePayload(data);
        })
        .catch(() => undefined);
    }
  };

  const handleRegenerate = () => {
    const lastUser = [...messages].reverse().find((m) => m.role === "user");
    if (lastUser) {
      sendMessage(
        lastUser.content,
        lastUser.attachments?.map((a) => a.id) ?? [],
        { regenerate: true }
      );
    }
  };

  const handleEditSubmit = (messageId: string, newContent: string) => {
    const message = messages.find((m) => m.id === messageId);
    if (!message) return;
    sendMessage(newContent, message.attachments?.map((a) => a.id) ?? [], {
      editMessageId: messageId,
    });
  };

  const handleReasoningChange = async (mode: string) => {
    setReasoningEffort(mode);
    const convId = activeConversationId;
    if (convId === "new") return;
    await fetch(`/api/conversations/${convId}`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ reasoningEffort: mode }),
    });
  };

  const handleModeChange = async (mode: ChatMode) => {
    setChatMode(mode);
    const convId = activeConversationId;
    if (convId === "new") return;
    await fetch(`/api/conversations/${convId}`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ chatMode: mode }),
    });
  };

  const handleWebSearchChange = async (enabled: boolean) => {
    setWebSearchEnabled(enabled);
    const { invalidateClientFetchCache } = await import("@/lib/client/fetch-cache");
    invalidateClientFetchCache("/api/settings");
    await fetch("/api/settings", {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ webSearchEnabled: enabled }),
    });
  };

  const handleModelChange = async (modelId: string) => {
    const previous =
      modelRuntime?.loadedModel &&
      modelOptions.some((m) => m.id === modelRuntime.loadedModel)
        ? modelRuntime.loadedModel
        : selectedModel;
    setSelectedModel(modelId);

    // Déjà prêt → pas de long "Chargement…".
    if (
      modelRuntime?.phase === "ready" &&
      modelRuntime.loadedModel === modelId
    ) {
      setRuntimeStatus("READY");
      return;
    }

    setModelRuntime((prev) =>
      prev
        ? {
            ...prev,
            phase: "loading",
            targetModel: modelId,
            preferredModel: modelId,
            message: "Chargement…",
            error: undefined,
          }
        : {
            phase: "loading",
            preferredModel: modelId,
            loadedModel: null,
            targetModel: modelId,
            message: "Chargement…",
            pendingRequestCount: 0,
          }
    );
    setRuntimeStatus("LOADING_MODEL");

    try {
      const res = await fetch("/api/runtime/model", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ modelKey: modelId }),
      });
      if (!(res.status === 202 || res.ok)) {
        throw new Error("Impossible de demander le chargement du modèle");
      }
      const accepted = (await res.json()) as ModelRuntimeSnapshot & {
        accepted?: boolean;
      };
      if (accepted.phase === "ready" && accepted.loadedModel === modelId) {
        setModelRuntime(accepted);
        setRuntimeStatus("READY");
        return;
      }
      // Observer l’état réel — ne pas traiter un délai comme échec si READY arrive.
      for (let i = 0; i < 80; i++) {
        await new Promise((r) => setTimeout(r, 250));
        const st = await fetch("/api/runtime/status");
        if (!st.ok) continue;
        const data = (await st.json()) as {
          status?: RuntimeStatus;
          model?: ModelRuntimeSnapshot;
        };
        if (data.status) setRuntimeStatus(data.status);
        if (data.model) setModelRuntime(data.model);
        const phase = data.model?.phase;
        if (phase === "ready" && data.model?.loadedModel === modelId) {
          setRuntimeStatus("READY");
          return;
        }
        if (phase === "error") {
          setSelectedModel(previous);
          setRuntimeStatus(data.model?.loadedModel ? "READY" : "ERROR");
          return;
        }
      }
      // Dernière sync : si déjà chargé, READY — sinon message factuel sans faux timeout.
      const finalSt = await fetch("/api/runtime/status");
      if (finalSt.ok) {
        const data = (await finalSt.json()) as {
          status?: RuntimeStatus;
          model?: ModelRuntimeSnapshot;
        };
        if (data.model) setModelRuntime(data.model);
        if (data.model?.loadedModel === modelId) {
          setRuntimeStatus("READY");
          return;
        }
        if (data.status) setRuntimeStatus(data.status);
      }
    } catch {
      setSelectedModel(previous);
      void loadRuntimeStatus();
    }

    try {
      const capsRes = await fetch(
        `/api/runtime/reasoning-capabilities?model=${encodeURIComponent(modelId)}`
      );
      if (capsRes.ok) {
        const caps = (await capsRes.json()) as ReasoningCapabilities;
        const resolved =
          resolveReasoningMode(reasoningEffort, caps) ??
          reasoningEffort ??
          "off";
        if (resolved) {
          setReasoningEffort(resolved);
          if (activeConversationId !== "new") {
            await fetch(`/api/conversations/${activeConversationId}`, {
              method: "PATCH",
              headers: { "Content-Type": "application/json" },
              body: JSON.stringify({ reasoningEffort: resolved }),
            });
          }
        }
      }
    } catch {
      // ignore capability refresh errors
    }

    void refreshContextUsage();
    void loadRuntimeStatus();
  };

  const modelSwitching =
    modelRuntime?.phase === "loading" ||
    modelRuntime?.phase === "unloading" ||
    (modelRuntime?.phase === "idle" && !!modelRuntime.preferredModel);

  const activeModelLabel =
    modelOptions.find((m) => m.id === selectedModel)?.label ??
    selectedModel;

  const handleMemorize = async (messageId: string) => {
    const res = await fetch("/api/memories", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ messageId }),
    });
    const data = await readJson<{ success?: boolean; reason?: string }>(res);
    toast(
      data.success ? "Message mémorisé" : (data.reason ?? "Échec de la mémorisation"),
      data.success ? "success" : "error"
    );
  };

  const handleDeleteSavedMemory = async (messageId: string, memoryId: string) => {
    const res = await fetch(`/api/memories/${memoryId}`, { method: "DELETE" });
    if (!res.ok) {
      toast("Impossible de supprimer la mémoire", "error");
      throw new Error("delete failed");
    }

    setMessages((prev) =>
      prev.map((m) =>
        m.id === messageId
          ? {
              ...m,
              savedMemories: m.savedMemories?.filter((item) => item.id !== memoryId),
            }
          : m
      )
    );
    toast("Mémoire supprimée", "success");
    void refreshContextUsage();
  };

  const handleFilesMutationDone = useCallback((messageId: string) => {
    setMessages((prev) =>
      prev.map((m) =>
        m.id === messageId ? { ...m, filesMutationPending: undefined } : m
      )
    );
  }, []);

  // Sync title when renamed from the persistent sidebar chrome
  useEffect(() => {
    if (conversationId === "new") return;
    const conv = conversations.find((c) => c.id === conversationId);
    if (conv?.title) setTitle(conv.title);
  }, [conversations, conversationId]);

  // Capacitor : abort SSE quand l'app passe en arrière-plan
  useEffect(() => {
    const onBackground = () => {
      abortRef.current?.abort();
    };
    window.addEventListener("chatbot:app-background", onBackground);
    return () => {
      window.removeEventListener("chatbot:app-background", onBackground);
    };
  }, []);

  return (
    <main className="flex min-h-0 min-w-0 flex-1 flex-col">
        <ChatHeader
          title={title}
          runtimeStatus={runtimeStatus}
          modelRuntime={modelRuntime}
          activeModelLabel={activeModelLabel}
          webStatus={webStatus}
          webStatusMessage={webStatusMessage}
        />

        <div className="relative min-h-0 flex-1">
          <div
            ref={scrollContainerRef}
            className="h-full overflow-x-hidden overflow-y-auto"
            onScroll={(e) => {
              const el = e.currentTarget;
              const distanceFromBottom =
                el.scrollHeight - el.scrollTop - el.clientHeight;
              userScrolledRef.current = distanceFromBottom > 80;
              setShowScrollToBottom(distanceFromBottom > 80);
            }}
          >
            <MessageList
              messages={messages}
              chatMode={chatMode}
              isGenerating={isGenerating}
              editingMessageId={editingMessageId}
              agentUi={agentUi}
              webSearchActivity={webSearchActivity}
              toolState={toolState}
              onEdit={setEditingMessageId}
              onEditSubmit={handleEditSubmit}
              onEditCancel={() => setEditingMessageId(null)}
              onRegenerate={handleRegenerate}
              onMemorize={handleMemorize}
              onDeleteSavedMemory={handleDeleteSavedMemory}
              onFilesMutationDone={handleFilesMutationDone}
              bottomRef={bottomRef}
            />
          </div>
          <ScrollToBottomButton
            visible={showScrollToBottom}
            onClick={handleScrollToBottomClick}
          />
        </div>

        <ChatInput
          conversationId={activeConversationId}
          onEnsureConversationId={ensureConversationId}
          onSend={(msg, attachmentIds) => sendMessage(msg, attachmentIds)}
          onStop={() => abortRef.current?.abort()}
          isGenerating={isGenerating}
          disabled={runtimeStatus === "ERROR"}
          contextSnapshot={contextSnapshot}
          contextLoading={contextLoading}
          lastGenerationUsage={lastGenerationUsage}
          onAttachmentsChange={handleAttachmentsChange}
          models={modelOptions}
          selectedModel={selectedModel}
          onModelChange={handleModelChange}
          modelsLoading={modelsLoading}
          modelSwitching={modelSwitching && !isGenerating}
          modelSwitchMessage={modelRuntime?.message ?? "Chargement…"}
          reasoningMode={reasoningEffort}
          onReasoningChange={handleReasoningChange}
          chatMode={chatMode}
          onModeChange={handleModeChange}
          webSearchEnabled={webSearchEnabled}
          onWebSearchChange={handleWebSearchChange}
          placeholder="Écrire un message..."
        />
    </main>
  );
}
