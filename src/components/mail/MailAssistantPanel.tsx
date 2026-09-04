"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import {
  Reply,
  Trash2,
  Lightbulb,
  Send,
  PenLine,
  Eye,
  EyeOff,
  Paperclip,
} from "lucide-react";
import { Button } from "@/components/ui/Button";
import { SendConfirmation } from "@/components/email/SendConfirmation";
import { TrashConfirmation } from "@/components/mail/TrashConfirmation";
import { MailMessageBody } from "@/components/mail/MailMessageBody";
import { MailDraftCard } from "@/components/mail/MailDraftCard";
import { MailSummaryCard } from "@/components/mail/MailSummaryCard";
import { ModelSelector, type ModelOption } from "@/components/chat/ModelSelector";
import { HeaderStatusCluster } from "@/components/layout/HeaderStatusCluster";
import {
  AttachmentPreviewList,
  type PendingAttachment,
} from "@/components/chat/AttachmentPreview";
import { AttachmentGallery } from "@/components/attachments/AttachmentActionSheet";
import type { EmailDraftPreview } from "@/lib/email/draft/types";
import type { SendProposalResponse } from "@/lib/email/email-client";
import type { ProposeTrashEmailResult } from "@/lib/email/trash/types";
import type { MailThread } from "@/lib/mail/mail-client";
import {
  cancelEmailSend,
  confirmEmailSend,
  mailAssistantChat,
  proposeEmailSend,
  suggestMailReply,
  summarizeMailThread,
  validateEmailDraft,
} from "@/lib/mail/mail-client";
import type { UpdateDraftInput } from "@/lib/email/email-client";
import type {
  ModelRuntimeSnapshot,
  RuntimeStatus,
} from "@/lib/runtime/types";
import { isSelectableChatModel } from "@/lib/models/chat-models";
import { cn } from "@/lib/utils/cn";

const MAIL_CONVERSATION_ID = "mail-workspace";

interface ChatMessage {
  id: string;
  role: "user" | "assistant";
  content: string;
  kind?: "text" | "summary";
}

interface MailAssistantPanelProps {
  thread: MailThread | null;
  selectedMessageId: string | null;
  accountEmail?: string;
  onTrashConfirmed: (messageId: string) => void;
  onTrashFailed: (messageId: string) => void;
  onClose?: () => void;
  fullScreen?: boolean;
  compact?: boolean;
}

export function MailAssistantPanel({
  thread,
  selectedMessageId,
  accountEmail,
  onTrashConfirmed,
  onTrashFailed,
  fullScreen,
  compact,
}: MailAssistantPanelProps) {
  const [messages, setMessages] = useState<ChatMessage[]>([
    {
      id: "welcome",
      role: "assistant",
      content:
        "Résumez, répondez ou rédigez un nouveau mail. Le brouillon apparaît ici avec Envoyer / Modifier.",
    },
  ]);
  const [input, setInput] = useState("");
  const [loadingSummary, setLoadingSummary] = useState(false);
  const [loadingReply, setLoadingReply] = useState(false);
  const [draft, setDraft] = useState<EmailDraftPreview | null>(null);
  const [sendProposal, setSendProposal] = useState<SendProposalResponse | null>(
    null
  );
  const [trashProposal, setTrashProposal] =
    useState<ProposeTrashEmailResult | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [models, setModels] = useState<ModelOption[]>([]);
  const [selectedModel, setSelectedModel] = useState("");
  const [modelsLoading, setModelsLoading] = useState(true);
  const [runtimeStatus, setRuntimeStatus] = useState<RuntimeStatus>("READY");
  const [modelRuntime, setModelRuntime] =
    useState<ModelRuntimeSnapshot | null>(null);
  const [attachments, setAttachments] = useState<PendingAttachment[]>([]);
  const scrollRef = useRef<HTMLDivElement>(null);
  const fileInputRef = useRef<HTMLInputElement>(null);

  const scrollToBottom = () => {
    requestAnimationFrame(() => {
      scrollRef.current?.scrollTo({
        top: scrollRef.current.scrollHeight,
        behavior: "smooth",
      });
    });
  };

  const applyRuntimePayload = useCallback(
    (data: { status?: RuntimeStatus; model?: ModelRuntimeSnapshot }) => {
      if (data.status) setRuntimeStatus(data.status);
      if (data.model) setModelRuntime(data.model);
    },
    []
  );

  const refreshRuntimeStatus = useCallback(async () => {
    try {
      const res = await fetch("/api/runtime/status");
      if (!res.ok) return;
      const data = (await res.json()) as {
        status?: RuntimeStatus;
        model?: ModelRuntimeSnapshot;
      };
      applyRuntimePayload(data);
    } catch {
      // ignore polling errors
    }
  }, [applyRuntimePayload]);

  useEffect(() => {
    void (async () => {
      try {
        const [modelsRes, statusRes] = await Promise.all([
          fetch("/api/lm-studio/models"),
          fetch("/api/runtime/status"),
        ]);
        const modelsData = (await modelsRes.json()) as {
          data?: { id: string; name?: string }[];
        };
        const statusData = (await statusRes.json()) as {
          status?: RuntimeStatus;
          model?: ModelRuntimeSnapshot;
        };
        const opts =
          modelsData.data
            ?.filter((m) => isSelectableChatModel(m.id, m.name))
            .map((m) => ({
            id: m.id,
            label: m.name ?? m.id.split("/").pop() ?? m.id,
          })) ?? [];
        setModels(opts);
        applyRuntimePayload(statusData);
        const preferred =
          statusData.model?.preferredModel ??
            statusData.model?.loadedModel ??
            opts[0]?.id ??
            "";
        setSelectedModel(
          opts.some((o) => o.id === preferred)
            ? preferred
            : statusData.model?.loadedModel &&
                opts.some((o) => o.id === statusData.model?.loadedModel)
              ? statusData.model.loadedModel!
              : opts[0]?.id ?? ""
        );
      } finally {
        setModelsLoading(false);
      }
    })();
  }, [applyRuntimePayload]);

  useEffect(() => {
    const phase = modelRuntime?.phase;
    if (phase !== "loading" && phase !== "unloading") return;
    const interval = window.setInterval(() => {
      void refreshRuntimeStatus();
    }, 1200);
    return () => window.clearInterval(interval);
  }, [modelRuntime?.phase, refreshRuntimeStatus]);

  const modelSwitching =
    modelRuntime?.phase === "loading" ||
    modelRuntime?.phase === "unloading" ||
    runtimeStatus === "LOADING_MODEL";

  const activeModelLabel =
    models.find((m) => m.id === selectedModel)?.label ?? selectedModel;

  const handleModelChange = async (modelId: string) => {
    const previous =
      modelRuntime?.loadedModel &&
      models.some((m) => m.id === modelRuntime.loadedModel)
        ? modelRuntime.loadedModel
        : selectedModel;
    setSelectedModel(modelId);
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
      for (let i = 0; i < 60; i++) {
        await new Promise((r) => setTimeout(r, 500));
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
      setSelectedModel(previous);
      void refreshRuntimeStatus();
    } catch {
      setSelectedModel(previous);
      void refreshRuntimeStatus();
    }
  };

  const uploadFile = useCallback(async (file: File) => {
    const tempId = `temp-${Date.now()}`;
    const previewUrl = file.type.startsWith("image/")
      ? URL.createObjectURL(file)
      : undefined;
    setAttachments((prev) => [
      ...prev,
      {
        id: tempId,
        filename: file.name,
        mimeType: file.type,
        sizeBytes: file.size,
        type: file.type.startsWith("image/") ? "image" : "document",
        previewUrl,
        uploading: true,
      },
    ]);

    const form = new FormData();
    form.append("file", file);
    form.append("conversationId", MAIL_CONVERSATION_ID);

    try {
      const res = await fetch("/api/attachments/upload", {
        method: "POST",
        body: form,
      });
      const data = (await res.json()) as {
        error?: string;
        attachment?: PendingAttachment;
      };
      if (!res.ok || !data.attachment) {
        setAttachments((prev) =>
          prev.map((a) =>
            a.id === tempId
              ? { ...a, uploading: false, error: data.error ?? "Échec upload" }
              : a
          )
        );
        return;
      }
      const att = data.attachment as {
        id: string;
        filename: string;
        mimeType: string;
        sizeBytes: number;
        type?: "image" | "document";
      };
      setAttachments((prev) =>
        prev.map((a) =>
          a.id === tempId
            ? {
                id: att.id,
                filename: att.filename,
                mimeType: att.mimeType,
                sizeBytes: att.sizeBytes,
                type:
                  att.type ??
                  (att.mimeType.startsWith("image/") ? "image" : "document"),
                previewUrl,
                uploading: false,
              }
            : a
        )
      );
    } catch {
      setAttachments((prev) =>
        prev.map((a) =>
          a.id === tempId
            ? { ...a, uploading: false, error: "Erreur réseau" }
            : a
        )
      );
    }
  }, []);

  const handleFiles = useCallback(
    async (files: FileList | File[]) => {
      for (const file of Array.from(files)) {
        await uploadFile(file);
      }
    },
    [uploadFile]
  );

  const handlePaste = (e: React.ClipboardEvent) => {
    const pasted: File[] = [];
    for (const item of e.clipboardData.items) {
      if (item.kind !== "file") continue;
      const file = item.getAsFile();
      if (file) pasted.push(file);
    }
    if (pasted.length === 0 && e.clipboardData.files.length > 0) {
      pasted.push(...Array.from(e.clipboardData.files));
    }
    if (pasted.length === 0) return;
    e.preventDefault();
    void handleFiles(pasted);
  };

  const handleDrop = (e: React.DragEvent) => {
    e.preventDefault();
    if (e.dataTransfer.files.length > 0) {
      void handleFiles(e.dataTransfer.files);
    }
  };

  const pushMessage = (
    role: ChatMessage["role"],
    content: string,
    kind: ChatMessage["kind"] = "text"
  ) => {
    setMessages((prev) => [
      ...prev,
      { id: `${Date.now()}-${prev.length}`, role, content, kind },
    ]);
  };

  const readyAttachments = attachments.filter(
    (a) => !a.uploading && !a.error && !a.id.startsWith("temp-")
  );
  const readyAttachmentNames = readyAttachments.map((a) => a.filename);
  const readyAttachmentIds = readyAttachments.map((a) => a.id);

  const handleSummarize = async () => {
    if (!thread || loadingSummary || busy || loadingReply) return;
    setLoadingSummary(true);
    setError(null);
    scrollToBottom();
    try {
      const text = await summarizeMailThread(
        thread.id,
        selectedModel || undefined
      );
      pushMessage("assistant", text, "summary");
      scrollToBottom();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Échec du résumé");
    } finally {
      setLoadingSummary(false);
      scrollToBottom();
    }
  };

  const handleSuggestReply = async () => {
    if (!thread || loadingReply || busy || loadingSummary) return;
    setLoadingReply(true);
    setError(null);
    scrollToBottom();
    try {
      const result = await suggestMailReply({
        threadId: thread.id,
        model: selectedModel || undefined,
        attachmentIds:
          readyAttachmentIds.length > 0 ? readyAttachmentIds : undefined,
      });
      if (!result.draft) {
        throw new Error("Aucun brouillon reçu.");
      }
      setDraft(result.draft);
      setSendProposal(null);
      if (readyAttachmentIds.length > 0) {
        setAttachments([]);
      }
      pushMessage(
        "assistant",
        readyAttachmentIds.length > 0
          ? "Brouillon de réponse prêt avec pièce(s) jointe(s) — vérifiez puis Envoyer."
          : "Brouillon de réponse prêt — vérifiez puis Envoyer."
      );
      scrollToBottom();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Échec de la suggestion");
    } finally {
      setLoadingReply(false);
      scrollToBottom();
    }
  };

  const handleSendChat = async () => {
    const trimmed = input.trim();
    if (!trimmed || busy || modelSwitching) return;
    setInput("");
    pushMessage("user", trimmed);
    setBusy(true);
    setError(null);
    try {
      const result = await mailAssistantChat({
        message: trimmed,
        threadId: thread?.id,
        draftId: draft?.draftId,
        model: selectedModel || undefined,
        accountEmail,
        attachmentNames:
          readyAttachmentNames.length > 0 ? readyAttachmentNames : undefined,
        attachmentIds:
          readyAttachmentIds.length > 0 ? readyAttachmentIds : undefined,
      });
      pushMessage("assistant", result.reply);
      if (result.draft) {
        setDraft(result.draft);
        setSendProposal(null);
      }
      if ((result.applied?.attachmentsAdded?.length ?? 0) > 0) {
        setAttachments([]);
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : "Erreur assistant");
    } finally {
      setBusy(false);
      scrollRef.current?.scrollTo({ top: scrollRef.current.scrollHeight });
    }
  };

  const handleSaveDraft = async (patch: UpdateDraftInput) => {
    if (!draft) return;
    const response = await fetch(`/api/email/drafts/${draft.draftId}`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(patch),
    });
    if (!response.ok) {
      const body = (await response.json()) as { error?: string };
      throw new Error(body.error ?? "Échec de la sauvegarde");
    }
    const updated = (await response.json()) as EmailDraftPreview;
    setDraft(updated);
  };

  const handleValidateAndSend = async () => {
    if (!draft) return;
    setBusy(true);
    setError(null);
    try {
      await validateEmailDraft(draft.draftId);
      const refreshed = await fetch(`/api/email/drafts/${draft.draftId}`).then(
        (r) => r.json() as Promise<EmailDraftPreview>
      );
      setDraft(refreshed);
      const proposal = await proposeEmailSend(refreshed.draftId);
      setSendProposal(proposal);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Échec de validation");
    } finally {
      setBusy(false);
    }
  };

  return (
    <aside
      className={cn(
        "flex h-full min-w-0 flex-col bg-surface",
        fullScreen ? "w-full" : "border-l border-border-subtle"
      )}
    >
      {!compact && (
        <div
          className={cn(
            "flex items-center gap-2 border-b border-border-subtle px-3 py-2",
            fullScreen ? "justify-end" : "flex-wrap justify-between"
          )}
        >
          {!fullScreen && (
            <div className="min-w-0 truncate text-[13px] font-medium text-foreground">
              Assistant Mail
            </div>
          )}
          <div className="flex min-w-0 flex-1 items-center justify-end gap-2">
            <HeaderStatusCluster
              runtimeStatus={runtimeStatus}
              modelRuntime={modelRuntime}
              activeModelLabel={activeModelLabel}
              showWeb={false}
              className="shrink-0"
            />
            <ModelSelector
              models={models}
              value={selectedModel}
              loading={modelsLoading}
              switching={modelSwitching}
              switchingLabel={modelRuntime?.message ?? "Chargement…"}
              disabled={busy || loadingSummary || loadingReply || modelSwitching}
              onChange={(id) => void handleModelChange(id)}
              placement="bottom"
              className="min-w-0 shrink"
            />
          </div>
        </div>
      )}

      <div
        className={cn(
          "flex items-center gap-2 border-b border-border-subtle",
          compact
            ? "flex-wrap px-3 py-2"
            : "overflow-x-auto p-3 [-ms-overflow-style:none] [scrollbar-width:none] [&::-webkit-scrollbar]:hidden"
        )}
      >
        {compact && (
          <div className="flex w-full min-w-0 items-center justify-between gap-2">
            <ModelSelector
              models={models}
              value={selectedModel}
              loading={modelsLoading}
              switching={modelSwitching}
              switchingLabel={modelRuntime?.message ?? "Chargement…"}
              disabled={
                busy || loadingSummary || loadingReply || modelSwitching
              }
              onChange={(id) => void handleModelChange(id)}
              placement="bottom"
              className="min-w-0 shrink"
            />
            <HeaderStatusCluster
              runtimeStatus={runtimeStatus}
              modelRuntime={modelRuntime}
              activeModelLabel={activeModelLabel}
              showWeb={false}
              className="shrink-0"
            />
          </div>
        )}
        <div className={cn("flex min-w-0 flex-1 gap-2", compact ? "w-full" : "")}>
          <Button
            variant="secondary"
            size="sm"
            loading={loadingSummary}
            disabled={
              !thread ||
              loadingSummary ||
              loadingReply ||
              busy ||
              modelSwitching
            }
            onClick={() => void handleSummarize()}
            className="shrink-0"
          >
            <Lightbulb className="h-3.5 w-3.5" />
            Résumer
          </Button>
          <Button
            variant="secondary"
            size="sm"
            loading={loadingReply}
            disabled={
              !thread ||
              loadingSummary ||
              loadingReply ||
              busy ||
              modelSwitching
            }
            onClick={() => void handleSuggestReply()}
            className="shrink-0"
          >
            <Reply className="h-3.5 w-3.5" />
            Répondre
          </Button>
          {!compact && (
            <Button
              variant="secondary"
              size="sm"
              disabled={busy || loadingSummary || loadingReply || modelSwitching}
              onClick={() => setInput("Rédige un nouveau mail à ")}
              className="shrink-0"
            >
              <PenLine className="h-3.5 w-3.5" />
              Nouveau mail
            </Button>
          )}
        </div>
      </div>

      <div
        ref={scrollRef}
        className="min-h-0 flex-1 space-y-3 overflow-y-auto overscroll-contain p-3"
      >
        {error && (
          <p className="text-sm text-red-500" role="alert">
            {error}
          </p>
        )}

        {messages.map((message) =>
          message.kind === "summary" ? (
            <MailSummaryCard key={message.id} content={message.content} />
          ) : (
            <div
              key={message.id}
              className={cn(
                "rounded-[var(--radius-lg)] px-3 py-2 text-sm whitespace-pre-wrap",
                message.role === "user"
                  ? "ml-4 bg-accent-muted/50 text-foreground"
                  : "mr-2 border border-border-subtle bg-background text-foreground"
              )}
            >
              {message.content}
            </div>
          )
        )}

        {(loadingSummary || loadingReply) && (
          <div
            className="mr-2 flex items-center gap-2 rounded-[var(--radius-lg)] border border-border-subtle bg-background px-3 py-2.5 text-sm text-muted-foreground"
            aria-live="polite"
          >
            <span className="inline-flex gap-1">
              <span className="h-1 w-1 animate-pulse rounded-full bg-muted-foreground" />
              <span className="h-1 w-1 animate-pulse rounded-full bg-muted-foreground [animation-delay:150ms]" />
              <span className="h-1 w-1 animate-pulse rounded-full bg-muted-foreground [animation-delay:300ms]" />
            </span>
            {loadingSummary
              ? "Résumé en cours…"
              : "Rédaction de la réponse…"}
          </div>
        )}

        {draft && (
          <MailDraftCard
            draft={draft}
            disabled={busy || loadingReply || loadingSummary}
            onSave={handleSaveDraft}
            onDismiss={() => setDraft(null)}
            onPrepareSend={() => void handleValidateAndSend()}
          />
        )}

        {sendProposal && draft && (
          <SendConfirmation
            draft={draft}
            proposal={sendProposal}
            conversationId={draft.conversationId}
            disabled={busy}
            onConfirm={async (actionId, token) => {
              await confirmEmailSend(actionId, {
                confirmationToken: token,
                conversationId: draft.conversationId,
              });
              setSendProposal(null);
              setDraft(null);
              pushMessage("assistant", "Email envoyé avec succès.");
            }}
            onCancel={async (actionId) => {
              await cancelEmailSend(actionId);
              setSendProposal(null);
            }}
            onDismiss={() => setSendProposal(null)}
          />
        )}

        {trashProposal && (
          <TrashConfirmation
            proposal={trashProposal}
            disabled={busy}
            onConfirm={async (actionId, token) => {
              try {
                const { confirmMailTrash } = await import(
                  "@/lib/mail/mail-client"
                );
                await confirmMailTrash(actionId, token);
                onTrashConfirmed(trashProposal.messageId);
                setTrashProposal(null);
              } catch (err) {
                onTrashFailed(trashProposal.messageId);
                throw err;
              }
            }}
            onCancel={() => setTrashProposal(null)}
          />
        )}
      </div>

      <div className="space-y-2 border-t border-border-subtle p-3 pb-[max(0.75rem,env(safe-area-inset-bottom))]">
        {thread && selectedMessageId && (
          <Button
            variant="secondary"
            size="sm"
            className="w-full text-red-600 hover:text-red-700"
            disabled={busy || !!trashProposal || loadingSummary || loadingReply}
            onClick={async () => {
              setBusy(true);
              setError(null);
              try {
                const { proposeMailTrash } = await import("@/lib/mail/mail-client");
                const proposal = await proposeMailTrash(selectedMessageId);
                setTrashProposal(proposal);
              } catch (err) {
                setError(
                  err instanceof Error
                    ? err.message
                    : "Impossible de préparer la corbeille"
                );
              } finally {
                setBusy(false);
              }
            }}
          >
            <Trash2 className="h-3.5 w-3.5" />
            Corbeille
          </Button>
        )}

        {attachments.length > 0 && (
          <div className="space-y-1">
            <AttachmentPreviewList
              items={attachments}
              onRemove={(id) =>
                setAttachments((prev) => prev.filter((a) => a.id !== id))
              }
            />
            <p className="px-0.5 text-[11px] text-muted-foreground">
              {draft
                ? "Fichiers prêts — dites de les joindre au brouillon (l’IA analyse votre message)."
                : "Fichiers prêts — composez / répondez en demandant de les joindre."}
            </p>
          </div>
        )}

        {draft && (draft.attachments?.length ?? 0) > 0 && (
          <p className="rounded-[var(--radius-sm)] bg-surface-hover px-2.5 py-1.5 text-[11px] text-muted">
            {draft.attachments!.length} pièce(s) jointe(s) sur le brouillon :{" "}
            {draft.attachments!.map((a) => a.filename).join(", ")}
          </p>
        )}

        <input
          ref={fileInputRef}
          type="file"
          className="hidden"
          multiple
          onChange={(e) => {
            const files = e.target.files;
            if (!files) return;
            void Promise.all([...files].map((f) => uploadFile(f)));
            e.target.value = "";
          }}
        />

        <div
          className="flex gap-2"
          onDragOver={(e) => {
            e.preventDefault();
            e.dataTransfer.dropEffect = "copy";
          }}
          onDrop={handleDrop}
        >
          <Button
            variant="ghost"
            size="sm"
            disabled={busy || modelSwitching}
            onClick={() => fileInputRef.current?.click()}
            aria-label="Ajouter une pièce jointe"
          >
            <Paperclip className="h-4 w-4" />
          </Button>
          <input
            type="text"
            value={input}
            onChange={(e) => setInput(e.target.value)}
            onPaste={handlePaste}
            onKeyDown={(e) => {
              if (e.key === "Enter" && !e.shiftKey) {
                e.preventDefault();
                void handleSendChat();
              }
            }}
            placeholder={
              modelSwitching
                ? "Chargement du modèle…"
                : "Demandez une action mail…"
            }
            className="min-h-[2.75rem] min-w-0 flex-1 rounded-[var(--radius-md)] border border-border-subtle bg-transparent px-3 py-2.5 text-base text-foreground outline-none focus:border-border-strong lg:text-sm"
            disabled={busy || modelSwitching}
          />
          <Button
            variant="primary"
            size="sm"
            disabled={busy || modelSwitching || !input.trim()}
            onClick={() => void handleSendChat()}
          >
            <Send className="h-3.5 w-3.5" />
          </Button>
        </div>
      </div>
    </aside>
  );
}

export function MailThreadPanel({
  thread,
  loading,
  collapsed,
  onToggleCollapse,
  compactHeader,
}: {
  thread: MailThread | null;
  selectedMessageId: string | null;
  loading?: boolean;
  collapsed: boolean;
  onToggleCollapse: () => void;
  compactHeader?: boolean;
}) {
  if (collapsed) {
    return (
      <div className="hidden h-full w-full min-w-0 flex-1 items-start p-2 lg:flex">
        <Button variant="ghost" size="sm" onClick={onToggleCollapse}>
          <Eye className="h-3.5 w-3.5" />
          Afficher
        </Button>
      </div>
    );
  }

  if (loading) {
    return (
      <div className="flex h-full w-full min-w-0 flex-1 items-center justify-center p-8 text-sm text-muted-foreground">
        Chargement du fil…
      </div>
    );
  }

  if (!thread) {
    return (
      <div className="hidden h-full w-full min-w-0 flex-1 items-center justify-center p-8 text-center text-sm text-muted-foreground lg:flex">
        Sélectionnez un message pour afficher le fil.
      </div>
    );
  }

  return (
    <div className="flex h-full w-full min-w-0 flex-1 flex-col">
      {!compactHeader && (
        <div className="hidden items-center justify-between gap-2 border-b border-border-subtle px-4 py-2 lg:flex">
          <h2 className="truncate text-sm font-semibold text-foreground">
            {thread.subject}
          </h2>
          <Button variant="ghost" size="sm" onClick={onToggleCollapse}>
            <EyeOff className="h-3.5 w-3.5" />
            Masquer
          </Button>
        </div>
      )}
      <div className="min-h-0 min-w-0 flex-1 overflow-x-hidden overflow-y-auto overscroll-contain pb-[max(5.5rem,calc(env(safe-area-inset-bottom)+4.5rem))]">
        {thread.messages.map((message) => (
          <article
            key={message.id}
            className="min-h-full min-w-0 max-w-full overflow-x-hidden bg-background"
          >
            <header className="sticky top-0 z-[1] border-b border-border-subtle bg-background/95 px-4 py-3 backdrop-blur-sm">
              <div className="flex flex-wrap items-baseline justify-between gap-2">
                <p className="min-w-0 flex-1 truncate text-sm font-medium text-foreground">
                  {message.from.name ?? message.from.email}
                </p>
                <time className="shrink-0 text-xs text-muted-foreground">
                  {new Date(message.date).toLocaleString("fr-FR")}
                </time>
              </div>
              <p className="mt-1 line-clamp-2 text-sm text-muted-foreground">
                {message.subject}
              </p>
            </header>
            <div className="w-full min-w-0 max-w-full overflow-x-hidden px-3 pb-4 lg:px-5">
              <MailMessageBody
                bodyText={message.bodyText}
                bodyHtml={message.bodyHtml}
                snippet={message.snippet}
              />
              {(message.attachments?.length ?? 0) > 0 && (
                <AttachmentGallery
                  attachments={message.attachments!.map((att) => {
                    const params = new URLSearchParams({
                      attachmentId: att.id,
                      filename: att.filename,
                      mimeType: att.mimeType,
                      size: String(att.sizeBytes),
                    });
                    return {
                      id: att.id,
                      filename: att.filename,
                      mimeType: att.mimeType,
                      sizeBytes: att.sizeBytes,
                      url: `/api/mail/messages/${message.id}/attachment?${params.toString()}`,
                    };
                  })}
                />
              )}
            </div>
          </article>
        ))}
      </div>
    </div>
  );
}
